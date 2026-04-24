// GeminiService.swift
// Unified Gemini 2.5 Flash Lite API client for OCR, voice parsing, and object detection.

import UIKit
import Foundation

final class GeminiService {
    
    static let shared = GeminiService()
    
    // MARK: - Configuration
    
    private let apiKey: String = {
        Bundle.main.infoDictionary?["GEMINI_API_KEY"] as? String ?? ""
    }()
    private let model = "gemini-2.5-flash-lite"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let session = URLSession.shared
    
    /// Max image dimension before sending (cost optimization)
    private let maxImageDimension: CGFloat = 768
    private let timeoutInterval: TimeInterval = 15
    
    private init() {}
    
    // MARK: - Freemium Usage
    
    /// Whether the user has exhausted their free Gemini actions.
    var isLimitReached: Bool {
        return !UsageTracker.shared.canUseGemini
    }
    
    // MARK: - Public API
    
    /// Parse Whisper-transcribed text into a structured sale result.
    func parseVoiceForSale(text: String, completion: @escaping (ParsedResult?) -> Void) {
        // Core Cost Optimization: Check local cache first
        if let cachedJSON = RequestCacheManager.shared.getCachedSaleResponse(for: text),
           let result = Self.parseSaleJSON(cachedJSON) {
            print("[GeminiService] Cache Hit! Zero latency and $0.00 cost for: '\(text)'")
            completion(result)
            return
        }
        
        let userPrompt = """
        Parse this spoken text into a sale transaction JSON.
        
        Text: "\(text)"
        
        Return JSON matching this schema:
        \(GeminiPromptTemplates.voiceSaleSchema)
        """
        
        sendTextRequest(
            systemPrompt: GeminiPromptTemplates.voiceSaleSystem,
            userPrompt: userPrompt
        ) { jsonString in
            guard let jsonString = jsonString,
                  let result = Self.parseSaleJSON(jsonString) else {
                completion(nil)
                return
            }
            
            // Cache successful result and track usage
            RequestCacheManager.shared.cacheSaleResponse(for: text, json: jsonString)
            UsageTracker.shared.recordGeminiUsage()
            completion(result)
        }
    }
    
    /// Parse Whisper-transcribed text into a structured purchase result.
    func parseVoiceForPurchase(text: String, completion: @escaping (ParsedResult?) -> Void) {
        // Core Cost Optimization: Check local cache first
        if let cachedJSON = RequestCacheManager.shared.getCachedPurchaseResponse(for: text),
           let result = Self.parsePurchaseVoiceJSON(cachedJSON) {
            print("[GeminiService] Cache Hit! Zero latency and $0.00 cost for: '\(text)'")
            completion(result)
            return
        }
        
        let userPrompt = """
        Parse this spoken text into a purchase/stock entry JSON.
        
        Text: "\(text)"
        
        Return JSON matching this schema:
        \(GeminiPromptTemplates.voicePurchaseSchema)
        """
        
        sendTextRequest(
            systemPrompt: GeminiPromptTemplates.voicePurchaseSystem,
            userPrompt: userPrompt
        ) { jsonString in
            guard let jsonString = jsonString,
                  let result = Self.parsePurchaseVoiceJSON(jsonString) else {
                completion(nil)
                return
            }
            
            // Cache successful result and track usage
            RequestCacheManager.shared.cachePurchaseResponse(for: text, json: jsonString)
            UsageTracker.shared.recordGeminiUsage()
            completion(result)
        }
    }
    
    /// Parse a bill image into a sale result (OCR + structured extraction in one call).
    func parseBillForSale(image: UIImage, completion: @escaping (ParsedResult?) -> Void) {
        let userPrompt = """
        Extract all sale line items from this bill image.
        Return JSON matching this schema:
        \(GeminiPromptTemplates.billSaleSchema)
        """
        
        sendImageRequest(
            image: image,
            systemPrompt: GeminiPromptTemplates.billSaleSystem,
            userPrompt: userPrompt
        ) { jsonString in
            guard let jsonString = jsonString,
                  let result = Self.parseSaleJSON(jsonString) else {
                completion(nil)
                return
            }
            UsageTracker.shared.recordGeminiUsage()
            completion(result)
        }
    }
    
    /// Parse a bill image into a purchase result.
    func parseBillForPurchase(image: UIImage, completion: @escaping (ParsedPurchaseResult?) -> Void) {
        let isGST = (try? AppDataModel.shared.dataModel.db.getSettings())?.isGSTRegistered ?? false
        
        let schema = isGST ? GeminiPromptTemplates.billPurchaseSchemaGST : GeminiPromptTemplates.billPurchaseSchema
        let sysPrompt = isGST ? GeminiPromptTemplates.billPurchaseSystemGST : GeminiPromptTemplates.billPurchaseSystem
        
        let userPrompt = """
        Extract supplier name and all purchase line items from this bill image.
        Return JSON matching this schema:
        \(schema)
        """
        
        sendImageRequest(
            image: image,
            systemPrompt: sysPrompt,
            userPrompt: userPrompt
        ) { jsonString in
            guard let jsonString = jsonString,
                  let result = Self.parsePurchaseBillJSON(jsonString) else {
                completion(nil)
                return
            }
            UsageTracker.shared.recordGeminiUsage()
            completion(result)
        }
    }
    
    /// Identify products in a photo (object detection replacement).
    func identifyProducts(image: UIImage, completion: @escaping (ParsedResult?) -> Void) {
        let userPrompt = """
        Identify EVERY distinct retail product visible in this image.
        Do NOT group them into a single item. List EACH product separately. that you can find in the image so we can identify as a product from the image , can be multiple .
        Return JSON matching this schema:
        \(GeminiPromptTemplates.objectDetectionSchema)
        """
        
        sendImageRequest(
            image: image,
            systemPrompt: GeminiPromptTemplates.objectDetectionSystem,
            userPrompt: userPrompt
        ) { jsonString in
            guard let jsonString = jsonString,
                  let result = Self.parseObjectJSON(jsonString) else {
                completion(nil)
                return
            }
            UsageTracker.shared.recordGeminiUsage()
            completion(result)
        }
    }
    
    // MARK: - Network Layer
    
    /// Send a text-only request to Gemini.
    private func sendTextRequest(
        systemPrompt: String,
        userPrompt: String,
        completion: @escaping (String?) -> Void
    ) {
        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userPrompt]]
                ]
            ],
            "generationConfig": [
                "response_mime_type": "application/json",
                "temperature": 0.1,
                "maxOutputTokens": 1024
            ]
        ]
        
        performRequest(body: body, completion: completion)
    }
    
    /// Send an image + text request to Gemini.
    private func sendImageRequest(
        image: UIImage,
        systemPrompt: String,
        userPrompt: String,
        completion: @escaping (String?) -> Void
    ) {
        // Compress and resize image for cost optimization
        guard let imageData = compressImage(image) else {
            print("[GeminiService] Failed to compress image")
            completion(nil)
            return
        }
        
        let base64Image = imageData.base64EncodedString()
        
        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        ["text": userPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "response_mime_type": "application/json",
                "temperature": 0.1,
                "maxOutputTokens": 2048
            ]
        ]
        
        performRequest(body: body, completion: completion)
    }
    
    /// Execute the HTTP request to Gemini API.
    private func performRequest(body: [String: Any], completion: @escaping (String?) -> Void) {
        let urlString = "\(baseURL)/\(model):generateContent?key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            print("[GeminiService] Invalid URL")
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[GeminiService] JSON serialization error: \(error)")
            completion(nil)
            return
        }
        
        let requestStart = CFAbsoluteTimeGetCurrent()
        
        session.dataTask(with: request) { data, response, error in
            let elapsed = CFAbsoluteTimeGetCurrent() - requestStart
            
            if let error = error {
                print("[GeminiService] Network error (\(String(format: "%.1f", elapsed))s): \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            guard let data = data else {
                print("[GeminiService] No data received")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // Parse Gemini response
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[GeminiService] Invalid response format")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                // Check for error
                if let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("[GeminiService] API error: \(message)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                // Extract text from candidates[0].content.parts[0].text
                if let candidates = json["candidates"] as? [[String: Any]],
                   let content = candidates.first?["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    print("[GeminiService] Response (\(String(format: "%.1f", elapsed))s): \(text.prefix(200))...")
                    DispatchQueue.main.async { completion(text) }
                } else {
                    print("[GeminiService] Could not extract text from response")
                    if let raw = String(data: data, encoding: .utf8) {
                        print("[GeminiService] Raw: \(raw.prefix(500))")
                    }
                    DispatchQueue.main.async { completion(nil) }
                }
            } catch {
                print("[GeminiService] Parse error: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }
    
    // MARK: - Image Compression
    
    /// Resize image to max dimension and compress as JPEG for cost-effective API calls.
    private func compressImage(_ image: UIImage) -> Data? {
        let size = image.size
        let maxDim = maxImageDimension
        
        var targetSize = size
        if size.width > maxDim || size.height > maxDim {
            let scale = maxDim / max(size.width, size.height)
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        }
        
        UIGraphicsBeginImageContextWithOptions(targetSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resized?.jpegData(compressionQuality: 0.8)
    }
    
    // MARK: - JSON Parsing → App Models
    
    /// Strip Markdown code blocks from JSON string
    private static func sanitizeJSONString(_ jsonString: String) -> String {
        var clean = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```json") {
            clean.removeFirst(7)
        } else if clean.hasPrefix("```") {
            clean.removeFirst(3)
        }
        if clean.hasSuffix("```") {
            clean.removeLast(3)
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Parse sale JSON (from voice or bill) into ParsedResult.
    /// Uses category_alias only for inventory matching, never for display.
    static func parseSaleJSON(_ jsonString: String) -> ParsedResult? {
        let cleanJSON = sanitizeJSONString(jsonString)
        guard let data = cleanJSON.data(using: .utf8) else { return nil }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            let customer = json["customer"] as? String
            let paymentMode = json["payment_mode"] as? String
            let isNegation = json["is_negation"] as? Bool ?? false
            
            // Collect raw products with both display name and matching name
            var rawProducts: [(displayName: String, matchingName: String, quantity: String, unit: String?, price: String?)] = []
            
            if let items = json["items"] as? [[String: Any]] {
                for item in items {
                    let nameRaw = item["name"] as? String ?? ""
                    let alias = item["category_alias"] as? String ?? ""
                    let quantity = item["quantity"] as? String ?? "1"
                    let unit = item["unit"] as? String
                    let price = item["price"] as? String
                    
                    guard !nameRaw.isEmpty else { continue }
                    
                    // Alias is used ONLY for matching, not displayed
                    let matchingName = alias.isEmpty ? nameRaw : "\(nameRaw) \(alias)"
                    
                    rawProducts.append((
                        displayName: nameRaw.trimmingCharacters(in: .whitespaces),
                        matchingName: matchingName.trimmingCharacters(in: .whitespaces),
                        quantity: quantity,
                        unit: unit ?? "pcs",
                        price: price
                    ))
                }
            }
            
            guard !rawProducts.isEmpty else { return nil }
            
            // Run inventory matching using the matching name (with alias)
            let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            InventoryMatcher.shared.indexInventory(inventory)
            
            let matchInput = rawProducts.map {
                (name: $0.matchingName, quantity: $0.quantity, unit: $0.unit, price: $0.price, costPrice: nil as String?)
            }
            let matched = InventoryMatcher.shared.matchProducts(products: matchInput, items: inventory)
            
            // Build final products: use inventory name if matched, else original display name
            var products: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = []
            for (i, m) in matched.enumerated() {
                let displayName = rawProducts[i].displayName
                if m.itemID != nil {
                    // Matched: use canonical inventory name and fill missing info
                    products.append((name: m.name, quantity: m.quantity, unit: m.unit, price: m.price, costPrice: m.costPrice))
                } else {
                    // Unmatched: use original display name (no alias)
                    products.append((name: displayName, quantity: m.quantity, unit: m.unit, price: m.price, costPrice: nil))
                }
            }
            
            print("\n[GeminiService] --- DETECTED SALE ITEMS LOG ---")
            print("[GeminiService] Raw JSON: \(cleanJSON)")
            for (i, p) in products.enumerated() {
                let status = matched[i].itemID != nil ? "✅ (Matched)" : "⚠️ (New)"
                let priceLog = p.price != nil ? " | Price: ₹\(p.price!)" : ""
                let unitLog = p.unit != nil ? " | Unit: \(p.unit!)" : ""
                print("[GeminiService] \(i+1). \(p.name) (Qty: \(p.quantity))\(unitLog)\(priceLog) - \(status)")
            }
            let custLog = customer != nil ? "Customer: \(customer!)" : "No Customer"
            print("[GeminiService] \(custLog) | Payment: \(paymentMode ?? "cash")")
            print("[GeminiService] -------------------------------\n")
            
            return ParsedResult(
                entities: [],
                products: products,
                customerName: customer,
                isNegation: isNegation,
                isReference: false,
                productItemIDs: matched.compactMap { $0.itemID },
                productConfidences: nil
            )
        } catch {
            print("[GeminiService] Sale JSON parse error: \(error)")
            return nil
        }
    }
    
    /// Parse purchase voice JSON into ParsedResult (used by VoicePurchaseEntryViewController).
    /// Uses category_alias only for inventory matching, never for display.
    static func parsePurchaseVoiceJSON(_ jsonString: String) -> ParsedResult? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            let supplier = json["supplier"] as? String
            
            var rawProducts: [(displayName: String, matchingName: String, quantity: String, unit: String?, costPrice: String?, sellingPrice: String?)] = []
            
            if let items = json["items"] as? [[String: Any]] {
                for item in items {
                    let nameRaw = item["name"] as? String ?? ""
                    let alias = item["category_alias"] as? String ?? ""
                    let quantity = item["quantity"] as? String ?? "1"
                    let unit = item["unit"] as? String
                    let costPrice = item["cost_price"] as? String
                    let sellingPrice = item["selling_price"] as? String
                    
                    guard !nameRaw.isEmpty else { continue }
                    
                    let matchingName = alias.isEmpty ? nameRaw : "\(nameRaw) \(alias)"
                    
                    rawProducts.append((
                        displayName: nameRaw.trimmingCharacters(in: .whitespaces),
                        matchingName: matchingName.trimmingCharacters(in: .whitespaces),
                        quantity: quantity,
                        unit: unit ?? "pcs",
                        costPrice: costPrice,
                        sellingPrice: sellingPrice
                    ))
                }
            }
            
            guard !rawProducts.isEmpty else { return nil }
            
            // Run inventory matching
            let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            InventoryMatcher.shared.indexInventory(inventory)
            
            let matchInput = rawProducts.map {
                (name: $0.matchingName, quantity: $0.quantity, unit: $0.unit, price: $0.sellingPrice, costPrice: $0.costPrice)
            }
            let matched = InventoryMatcher.shared.matchProducts(products: matchInput, items: inventory)
            
            var products: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = []
            for (i, m) in matched.enumerated() {
                let displayName = rawProducts[i].displayName
                if m.itemID != nil {
                    products.append((name: m.name, quantity: m.quantity, unit: m.unit, price: m.price, costPrice: m.costPrice))
                } else {
                    products.append((name: displayName, quantity: m.quantity, unit: m.unit, price: rawProducts[i].sellingPrice, costPrice: rawProducts[i].costPrice))
                }
            }
            
            print("[GeminiService] Parsed purchase: \(products.count) items, supplier=\(supplier ?? "nil")")
            
            // Store supplier in customerName field (same as MLInference does)
            return ParsedResult(
                entities: [],
                products: products,
                customerName: supplier,
                isNegation: false,
                isReference: false,
                productItemIDs: matched.compactMap { $0.itemID },
                productConfidences: nil
            )
        } catch {
            print("[GeminiService] Purchase voice JSON parse error: \(error)")
            return nil
        }
    }
    
    /// Parse purchase bill JSON into ParsedPurchaseResult.
    /// Uses category_alias only for inventory matching, never for display.
    static func parsePurchaseBillJSON(_ jsonString: String) -> ParsedPurchaseResult? {
        let cleanJSON = sanitizeJSONString(jsonString)
        guard let data = cleanJSON.data(using: .utf8) else { return nil }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            let supplier = json["supplier"] as? String
            let supplierGSTIN = json["supplier_gstin"] as? String
            let invoiceNumber = json["invoice_number"] as? String
            let invoiceDate = json["invoice_date"] as? String
            let totalCGST = json["total_cgst"] as? String
            let totalSGST = json["total_sgst"] as? String
            let totalIGST = json["total_igst"] as? String
            let totalTaxableValue = json["total_taxable_value"] as? String
            
            // Collect raw items with both display and matching names
            var rawItems: [(displayName: String, matchingName: String, quantity: String, unit: String?, costPrice: String?, sellingPrice: String?, hsnCode: String?, gstRate: String?)] = []
            
            if let jsonItems = json["items"] as? [[String: Any]] {
                for item in jsonItems {
                    let nameRaw = item["name"] as? String ?? ""
                    let alias = item["category_alias"] as? String ?? ""
                    let quantity = item["quantity"] as? String ?? "1"
                    let unit = item["unit"] as? String
                    let costPrice = item["cost_price"] as? String
                    let sellingPrice = item["selling_price"] as? String
                    let hsnCode = item["hsn_code"] as? String
                    let gstRate = item["gst_rate"] as? String
                    
                    guard !nameRaw.isEmpty else { continue }
                    
                    let matchingName = alias.isEmpty ? nameRaw : "\(nameRaw) \(alias)"
                    
                    rawItems.append((
                        displayName: nameRaw.trimmingCharacters(in: .whitespaces),
                        matchingName: matchingName.trimmingCharacters(in: .whitespaces),
                        quantity: quantity,
                        unit: unit ?? "pcs",
                        costPrice: costPrice,
                        sellingPrice: sellingPrice,
                        hsnCode: hsnCode,
                        gstRate: gstRate
                    ))
                }
            }
            
            guard !rawItems.isEmpty else { return nil }
            
            // Run inventory matching
            let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            InventoryMatcher.shared.indexInventory(inventory)
            
            var items: [ParsedPurchaseItem] = []
            for raw in rawItems {
                if let match = InventoryMatcher.shared.match(name: raw.matchingName, against: inventory) {
                    // Matched: use canonical inventory name and fill inventory info
                    items.append(ParsedPurchaseItem(
                        name: match.item.name,
                        quantity: raw.quantity,
                        unit: raw.unit ?? match.item.unit,
                        costPrice: raw.costPrice,
                        sellingPrice: raw.sellingPrice ?? String(format: "%.0f", match.item.defaultSellingPrice),
                        itemLikelihood: match.confidence,
                        hsnCode: raw.hsnCode ?? match.item.hsnCode,
                        gstRate: raw.gstRate ?? (match.item.gstRate != nil ? String(format: "%.0f", match.item.gstRate!) : nil)
                    ))
                } else {
                    // Unmatched: use original display name (no alias)
                    items.append(ParsedPurchaseItem(
                        name: raw.displayName,
                        quantity: raw.quantity,
                        unit: raw.unit,
                        costPrice: raw.costPrice,
                        sellingPrice: raw.sellingPrice,
                        itemLikelihood: 0.7,
                        hsnCode: raw.hsnCode,
                        gstRate: raw.gstRate
                    ))
                }
            }
            
            print("\n[GeminiService] --- DETECTED PURCHASE ITEMS LOG ---")
            print("[GeminiService] Raw JSON: \(cleanJSON)")
            for (i, p) in items.enumerated() {
                let status = (rawItems[i].displayName != p.name || (p.itemLikelihood ?? 0.0) > 0.70) ? "✅ (Matched)" : "⚠️ (New)"
                let costLog = p.costPrice != nil ? " | CP: ₹\(p.costPrice!)" : ""
                let spLog = p.sellingPrice != nil ? " | SP: ₹\(p.sellingPrice!)" : ""
                let unitLog = p.unit != nil ? " | Unit: \(p.unit!)" : ""
                print("[GeminiService] \(i+1). \(p.name) (Qty: \(p.quantity))\(unitLog)\(costLog)\(spLog) - \(status)")
            }
            let supLog = supplier != nil ? "Supplier: \(supplier!)" : "No Supplier"
            print("[GeminiService] \(supLog)")
            print("[GeminiService] -----------------------------------\n")
            
            return ParsedPurchaseResult(
                supplierName: supplier,
                supplierGSTIN: supplierGSTIN,
                invoiceNumber: invoiceNumber,
                invoiceDate: invoiceDate,
                items: items,
                totalCGST: totalCGST,
                totalSGST: totalSGST,
                totalIGST: totalIGST,
                totalTaxableValue: totalTaxableValue
            )
        } catch {
            print("[GeminiService] Purchase bill JSON parse error: \(error)")
            return nil
        }
    }
    
    /// Parse object detection JSON into ParsedResult.
    /// Uses category_alias only for inventory matching, never for display.
    /// If item matches inventory, fills price/unit from inventory.
    static func parseObjectJSON(_ jsonString: String) -> ParsedResult? {
        let cleanJSON = sanitizeJSONString(jsonString)
        guard let data = cleanJSON.data(using: .utf8) else { return nil }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            var rawProducts: [(displayName: String, matchingName: String, quantity: String, price: String?)] = []
            
            if let jsonProducts = json["products"] as? [[String: Any]] {
                for product in jsonProducts {
                    let nameRaw = product["name"] as? String ?? ""
                    let alias = product["category_alias"] as? String ?? ""
                    let quantity = product["quantity"] as? String ?? "1"
                    let price = product["price"] as? String
                    
                    guard !nameRaw.isEmpty else { continue }
                    
                    let matchingName = alias.isEmpty ? nameRaw : "\(nameRaw) \(alias)"
                    
                    rawProducts.append((
                        displayName: nameRaw.trimmingCharacters(in: .whitespaces),
                        matchingName: matchingName.trimmingCharacters(in: .whitespaces),
                        quantity: quantity,
                        price: price
                    ))
                }
            }
            
            guard !rawProducts.isEmpty else { return nil }
            
            // Run inventory matching
            let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            InventoryMatcher.shared.indexInventory(inventory)
            
            let matchInput = rawProducts.map {
                (name: $0.matchingName, quantity: $0.quantity, unit: "pcs" as String?, price: $0.price, costPrice: nil as String?)
            }
            let matched = InventoryMatcher.shared.matchProducts(products: matchInput, items: inventory)
            
            var products: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = []
            var itemIDs: [UUID] = []
            
            for (i, m) in matched.enumerated() {
                let displayName = rawProducts[i].displayName
                if m.itemID != nil {
                    // Matched: use inventory name, price, unit
                    products.append((name: m.name, quantity: m.quantity, unit: m.unit, price: m.price, costPrice: m.costPrice))
                    itemIDs.append(m.itemID!)
                } else {
                    // Unmatched: use original display name (still useful, user can fill rest)
                    products.append((name: displayName, quantity: m.quantity, unit: "pcs", price: rawProducts[i].price, costPrice: nil))
                }
            }
            
            print("\n[GeminiService] --- DETECTED OBJECTS LOG ---")
            print("[GeminiService] Raw JSON: \(cleanJSON)")
            for (i, p) in products.enumerated() {
                let status = matched[i].itemID != nil ? "✅ (Matched Inventory)" : "⚠️ (New/Unmatched)"
                let priceLog = p.price != nil ? " | Price: ₹\(p.price!)" : ""
                print("[GeminiService] \(i+1). \(p.name) (Qty: \(p.quantity))\(priceLog) - \(status)")
            }
            print("[GeminiService] ----------------------------\n")
            
            return ParsedResult(
                entities: [],
                products: products,
                customerName: nil,
                isNegation: false,
                isReference: false,
                productItemIDs: itemIDs.isEmpty ? nil : itemIDs,
                productConfidences: nil
            )
        } catch {
            print("[GeminiService] Object JSON parse error: \(error)")
            return nil
        }
    }
    
    // MARK: - Availability Check
    
    /// Check if GeminiService has a valid API key configured AND the user can still use it.
    var isConfigured: Bool {
        return !apiKey.isEmpty && apiKey != "YOUR_KEY_HERE" && !isLimitReached
    }
    
    /// Check if the API key is present (regardless of usage limit).
    /// Use this to determine if the app was ever configured with Gemini.
    var hasAPIKey: Bool {
        return !apiKey.isEmpty && apiKey != "YOUR_KEY_HERE"
    }
}
