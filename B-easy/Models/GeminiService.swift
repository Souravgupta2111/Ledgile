
import UIKit
import Foundation

final class GeminiService {
    
    static let shared = GeminiService()
    
    // AI requests go through Supabase Edge Function `gemini-proxy`.
    // Voice JSON → OpenRouter paid Gemma 3 27B. Camera → paid Gemini 2.5 Flash-Lite.
    // API keys live ONLY on the server. The app authenticates with the user's JWT.
    
    private static func resolveConfigValue(key: String, plistValue: String?) -> String {
        if let val = plistValue, !val.isEmpty, !val.hasPrefix("$(") {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        print("[GeminiService] Failed to resolve \(key) from Info.plist.")
        return ""
    }

    private let supabaseURL: String = {
        resolveConfigValue(key: "SUPABASE_URL", plistValue: Bundle.main.infoDictionary?["SUPABASE_URL"] as? String)
    }()
    
    private let supabaseAnonKey: String = {
        resolveConfigValue(key: "SUPABASE_ANON_KEY", plistValue: Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String)
    }()
    
    private let session = URLSession.shared
    
    private let maxImageDimension: CGFloat = 768
    private let timeoutInterval: TimeInterval = 30
    
    private init() {
        let hasAuth = AuthManager.shared.accessToken != nil
        print("[GeminiService] 🔑 Secured via Edge Function proxy")
        print("[GeminiService] 🔑 supabaseURL=\(!supabaseURL.isEmpty), hasJWT=\(hasAuth), isConfigured=\(isConfigured), isLimitReached=\(isLimitReached)")
    }
    
    
    var isLimitReached: Bool {
        return !UsageTracker.shared.canUseGemini
    }

    func isConfigured(for kind: UsageTracker.AIKind) -> Bool {
        let hasSupabase = !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
        let hasAuth = AuthManager.shared.accessToken != nil
        return hasSupabase && hasAuth && UsageTracker.shared.canUse(kind)
    }
    
    
    func parseVoiceForSale(text: String, completion: @escaping (ParsedResult?) -> Void) {
        print("[GeminiService] parseVoiceForSale | chars=\(text.count)")
        if let cachedJSON = RequestCacheManager.shared.getCachedSaleResponse(for: text),
           let result = Self.parseSaleJSON(cachedJSON, spokenText: text) {
            print("[GeminiService] Cache Hit! Zero latency and $0.00 cost for: '\(text)'")
            completion(result)
            return
        }
        
        sendTextRequest(
            systemPrompt: Self.cachedSystemPrompt(
                GeminiPromptTemplates.voiceSaleSystem,
                schema: GeminiPromptTemplates.voiceSaleSchema
            ),
            userPrompt: text
        ) { jsonString in
            guard let jsonString = jsonString,
                  let result = Self.parseSaleJSON(jsonString, spokenText: text) else {
                completion(nil)
                return
            }
            
            RequestCacheManager.shared.cacheSaleResponse(for: text, json: jsonString)
            UsageTracker.shared.record(.voice)
            completion(result)
        }
    }
    
    func parseVoiceForPurchase(text: String, completion: @escaping (ParsedResult?) -> Void) {
        print("[GeminiService] parseVoiceForPurchase | chars=\(text.count)")
        if let cachedJSON = RequestCacheManager.shared.getCachedPurchaseResponse(for: text),
           let result = Self.parsePurchaseVoiceJSON(cachedJSON, spokenText: text) {
            print("[GeminiService] Cache Hit! Zero latency and $0.00 cost for: '\(text)'")
            completion(result)
            return
        }
        
        sendTextRequest(
            systemPrompt: Self.cachedSystemPrompt(
                GeminiPromptTemplates.voicePurchaseSystem,
                schema: GeminiPromptTemplates.voicePurchaseSchema
            ),
            userPrompt: text
        ) { jsonString in
            guard let jsonString = jsonString,
                  let result = Self.parsePurchaseVoiceJSON(jsonString, spokenText: text) else {
                completion(nil)
                return
            }
            
            RequestCacheManager.shared.cachePurchaseResponse(for: text, json: jsonString)
            UsageTracker.shared.record(.voice)
            completion(result)
        }
    }
    
    func parseBillForSale(image: UIImage, completion: @escaping (ParsedResult?) -> Void) {
        print("[GeminiService] ➡️ parseBillForSale called | imageSize=\(image.size) | isConfigured=\(isConfigured)")
        sendImageRequest(
            image: image,
            systemPrompt: Self.cachedSystemPrompt(
                GeminiPromptTemplates.billSaleSystem,
                schema: GeminiPromptTemplates.billSaleSchema
            ),
            userPrompt: "Extract all sale line items from this bill image."
        ) { jsonString in
            guard let jsonString = jsonString,
                  let result = Self.parseSaleJSON(jsonString) else {
                completion(nil)
                return
            }
            UsageTracker.shared.record(.camera)
            completion(result)
        }
    }
    
    func parseBillForPurchase(image: UIImage, completion: @escaping (ParsedPurchaseResult?) -> Void) {
        print("[GeminiService] ➡️ parseBillForPurchase called | imageSize=\(image.size) | isConfigured=\(isConfigured)")
        let isGST = (try? AppDataModel.shared.dataModel.db.getSettings())?.isGSTRegistered ?? false
        
        let schema = isGST ? GeminiPromptTemplates.billPurchaseSchemaGST : GeminiPromptTemplates.billPurchaseSchema
        let sysPrompt = isGST ? GeminiPromptTemplates.billPurchaseSystemGST : GeminiPromptTemplates.billPurchaseSystem
        
        sendImageRequest(
            image: image,
            systemPrompt: Self.cachedSystemPrompt(sysPrompt, schema: schema),
            userPrompt: "Extract supplier name and all purchase line items from this bill image."
        ) { jsonString in
            guard let jsonString = jsonString,
                  let result = Self.parsePurchaseBillJSON(jsonString) else {
                completion(nil)
                return
            }
            UsageTracker.shared.record(.camera)
            completion(result)
        }
    }
    
    /// Stable system prefix (rules + schema). Unique utterance/image stays in the user turn.
    private static func cachedSystemPrompt(_ system: String, schema: String) -> String {
        """
        \(system)
        
        Return ONLY valid JSON matching this schema:
        \(schema)
        """
    }
    
    private func sendTextRequest(
        systemPrompt: String,
        userPrompt: String,
        completion: @escaping (String?) -> Void
    ) {
        let body: [String: Any] = [
            "task": "voice",
            "systemPrompt": systemPrompt,
            "userPrompt": userPrompt,
            "maxOutputTokens": 1024
        ]
        
        performRequest(body: body, completion: completion)
    }
    
    private func sendImageRequest(
        image: UIImage,
        systemPrompt: String,
        userPrompt: String,
        completion: @escaping (String?) -> Void
    ) {
        guard let imageData = compressImage(image) else {
            print("[GeminiService] Failed to compress image")
            completion(nil)
            return
        }
        
        let base64Image = imageData.base64EncodedString()
        
        let body: [String: Any] = [
            "task": "vision",
            "systemPrompt": systemPrompt,
            "userPrompt": userPrompt,
            "image": [
                "mime_type": "image/jpeg",
                "data": base64Image
            ],
            "maxOutputTokens": 2048
        ]
        
        performRequest(body: body, completion: completion)
    }
    
    private func performRequest(body: [String: Any], completion: @escaping (String?) -> Void) {
        // Route through the Supabase Edge Function proxy
        let urlString = "\(supabaseURL)/functions/v1/gemini-proxy"
        
        guard let url = URL(string: urlString) else {
            print("[GeminiService] Invalid Edge Function URL")
            completion(nil)
            return
        }
        
        guard let jwt = AuthManager.shared.accessToken else {
            print("[GeminiService] No auth token — user must be logged in to use AI features")
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
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
            
            // Check for HTTP-level errors from the Edge Function
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                if httpResponse.statusCode == 402 {
                    UsageTracker.shared.markCloudQuotaExhausted()
                    print("[GeminiService] Server quota exceeded")
                } else {
                    let raw = String(data: data, encoding: .utf8) ?? "(no body)"
                    print("[GeminiService] Edge Function HTTP \(httpResponse.statusCode): \(raw.prefix(120))")
                }
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[GeminiService] Invalid response format")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                if let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("[GeminiService] API error: \(message)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                if let quota = json["quota"] as? [String: Any] {
                    UsageTracker.shared.applyServerQuota(quota)
                }
                
                if let candidates = json["candidates"] as? [[String: Any]],
                   let content = candidates.first?["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    print("[GeminiService] Response (\(String(format: "%.1f", elapsed))s), \(text.count) chars")
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
    
    /// Safely extracts a String from a JSON value that could be a String, Int, Double, or NSNumber.
    /// Gemini sometimes returns numeric fields as JSON numbers instead of strings.
    private static func flexString(from value: Any?) -> String? {
        guard let value = value else { return nil }
        if let str = value as? String {
            return str.isEmpty ? nil : str
        }
        if let num = value as? NSNumber {
            // Check if it's a boolean (NSNumber wraps bools too)
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return nil }
            // If the number has no decimal part, format as integer
            let doubleVal = num.doubleValue
            if doubleVal == doubleVal.rounded() && doubleVal < 1e15 {
                return String(format: "%.0f", doubleVal)
            }
            return num.stringValue
        }
        return nil
    }

    /// Drops a customer/supplier the model invented from the whole utterance or an item line.
    private static func sanitizedPartyName(_ raw: String?, spokenText: String?, itemNames: [String]) -> String? {
        guard let raw else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let folded = name.lowercased()
        let junk: Set<String> = [
            "null", "none", "nil", "n/a", "na", "unknown",
            "customer", "supplier", "cash", "credit"
        ]
        if junk.contains(folded) { return nil }

        func normalize(_ s: String) -> String {
            s.lowercased()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let normalizedName = normalize(name)

        if let spoken = spokenText, !spoken.isEmpty {
            let spokenNorm = normalize(spoken)
            if normalizedName == spokenNorm { return nil }
        }

        for item in itemNames {
            let itemNorm = normalize(item)
            if !itemNorm.isEmpty, normalizedName == itemNorm { return nil }
        }

        if normalizedName.range(
            of: #"^\d+(\.\d+)?\s*(kg|kilo|g|gm|gram|litre|liter|ltr|ml|pcs|pc|packet|pkt|dozen)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return nil
        }

        return name
    }
    
    static func parseSaleJSON(_ jsonString: String, spokenText: String? = nil) -> ParsedResult? {
        let cleanJSON = sanitizeJSONString(jsonString)
        guard let data = cleanJSON.data(using: .utf8) else { return nil }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            let paymentMode = json["payment_mode"] as? String
            let isNegation = json["is_negation"] as? Bool ?? false
            
            var rawProducts: [(displayName: String, matchingName: String, quantity: String, unit: String?, price: String?)] = []
            
            if let items = json["items"] as? [[String: Any]] {
                for item in items {
                    let nameRaw = item["name"] as? String ?? ""
                    let alias = item["category_alias"] as? String ?? ""
                    let quantity = flexString(from: item["quantity"]) ?? "1"
                    let unit = item["unit"] as? String
                    let price = flexString(from: item["price"])
                    
                    // Diagnostic: log raw JSON types for price fields
                    print("[GeminiService] 🔍 SALE JSON item: name='\(nameRaw)' | price raw type=\(type(of: item["price"] as Any)) value=\(item["price"] ?? "nil") | parsed: \(price ?? "nil")")
                    print("[GeminiService] 🔍   quantity raw type=\(type(of: item["quantity"] as Any)) value=\(item["quantity"] ?? "nil") | unit=\(unit ?? "nil")")
                    
                    guard !nameRaw.isEmpty else { continue }
                    
                    let matchingName = alias.isEmpty ? nameRaw : "\(nameRaw) \(alias)"
                    
                    rawProducts.append((
                        displayName: nameRaw.trimmingCharacters(in: .whitespaces),
                        matchingName: matchingName.trimmingCharacters(in: .whitespaces),
                        quantity: quantity,
                        unit: unit,
                        price: price
                    ))
                }
            }
            
            guard !rawProducts.isEmpty else { return nil }

            let customer = sanitizedPartyName(
                flexString(from: json["customer"]),
                spokenText: spokenText,
                itemNames: rawProducts.map(\.displayName)
            )
            
            let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            InventoryMatcher.shared.indexInventory(inventory)
            
            let matchInput = rawProducts.map {
                (name: $0.matchingName, quantity: $0.quantity, unit: $0.unit, price: $0.price, costPrice: nil as String?)
            }
            let matched = InventoryMatcher.shared.matchProducts(products: matchInput, items: inventory)
            
            var products: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = []
            for (i, m) in matched.enumerated() {
                let displayName = rawProducts[i].displayName
                products.append((name: displayName, quantity: m.quantity, unit: m.unit, price: m.price, costPrice: m.costPrice))
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
                productConfidences: matched.map { String(format: "%.2f", $0.matchConfidence) }
            )
        } catch {
            print("[GeminiService] Sale JSON parse error: \(error)")
            return nil
        }
    }
    
    static func parsePurchaseVoiceJSON(_ jsonString: String, spokenText: String? = nil) -> ParsedResult? {
        let cleanJSON = sanitizeJSONString(jsonString)
        guard let data = cleanJSON.data(using: .utf8) else { return nil }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            var rawProducts: [(displayName: String, matchingName: String, quantity: String, unit: String?, costPrice: String?, sellingPrice: String?)] = []
            
            if let items = json["items"] as? [[String: Any]] {
                for item in items {
                    let nameRaw = item["name"] as? String ?? ""
                    let alias = item["category_alias"] as? String ?? ""
                    let quantity = flexString(from: item["quantity"]) ?? "1"
                    let unit = item["unit"] as? String
                    let costPrice = flexString(from: item["cost_price"])
                    let sellingPrice = flexString(from: item["selling_price"])
                    
                    // Diagnostic: log raw JSON types for price fields
                    print("[GeminiService] 🔍 PURCHASE VOICE item: name='\(nameRaw)' | cost_price raw type=\(type(of: item["cost_price"] as Any)) value=\(item["cost_price"] ?? "nil") | parsed: \(costPrice ?? "nil")")
                    print("[GeminiService] 🔍   selling_price raw type=\(type(of: item["selling_price"] as Any)) value=\(item["selling_price"] ?? "nil") | parsed: \(sellingPrice ?? "nil")")
                    
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

            let supplier = sanitizedPartyName(
                flexString(from: json["supplier"]),
                spokenText: spokenText,
                itemNames: rawProducts.map(\.displayName)
            )
            
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
    
    static func parsePurchaseBillJSON(_ jsonString: String) -> ParsedPurchaseResult? {
        let cleanJSON = sanitizeJSONString(jsonString)
        guard let data = cleanJSON.data(using: .utf8) else { return nil }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            let supplier = json["supplier"] as? String
            let supplierGSTIN = json["supplier_gstin"] as? String
            let invoiceNumber = flexString(from: json["invoice_number"])
            let invoiceDate = json["invoice_date"] as? String
            let totalCGST = flexString(from: json["total_cgst"])
            let totalSGST = flexString(from: json["total_sgst"])
            let totalIGST = flexString(from: json["total_igst"])
            let totalTaxableValue = flexString(from: json["total_taxable_value"])
            
            var rawItems: [(displayName: String, matchingName: String, quantity: String, unit: String?, costPrice: String?, sellingPrice: String?, hsnCode: String?, gstRate: String?)] = []
            
            if let jsonItems = json["items"] as? [[String: Any]] {
                for item in jsonItems {
                    let nameRaw = item["name"] as? String ?? ""
                    let alias = item["category_alias"] as? String ?? ""
                    let quantity = flexString(from: item["quantity"]) ?? "1"
                    let unit = item["unit"] as? String
                    let costPrice = flexString(from: item["cost_price"])
                    let sellingPrice = flexString(from: item["selling_price"])
                    let hsnCode = flexString(from: item["hsn_code"])
                    let gstRate = flexString(from: item["gst_rate"])
                    
                    // Diagnostic: log raw JSON types for price fields
                    print("[GeminiService] 🔍 PURCHASE BILL item: name='\(nameRaw)' | cost_price raw type=\(type(of: item["cost_price"] as Any)) value=\(item["cost_price"] ?? "nil") | parsed: \(costPrice ?? "nil")")
                    print("[GeminiService] 🔍   selling_price raw type=\(type(of: item["selling_price"] as Any)) value=\(item["selling_price"] ?? "nil") | parsed: \(sellingPrice ?? "nil")")
                    
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
            
            let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            InventoryMatcher.shared.indexInventory(inventory)
            
            var items: [ParsedPurchaseItem] = []
            for raw in rawItems {
                if let match = InventoryMatcher.shared.match(name: raw.matchingName, against: inventory) {
                    items.append(ParsedPurchaseItem(
                        name: raw.displayName,
                        quantity: raw.quantity,
                        unit: raw.unit ?? match.item.unit,
                        costPrice: raw.costPrice,
                        sellingPrice: raw.sellingPrice ?? String(format: "%.0f", match.item.defaultSellingPrice),
                        itemLikelihood: match.confidence,
                        hsnCode: raw.hsnCode ?? match.item.hsnCode,
                        gstRate: raw.gstRate ?? (match.item.gstRate != nil ? String(format: "%.0f", match.item.gstRate!) : nil)
                    ))
                } else {
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
    
    
    var isConfigured: Bool {
        isConfigured(for: .voice) || isConfigured(for: .camera)
    }
    
    var hasAPIKey: Bool {
        // API key is now on the server; we just need Supabase + auth
        return !supabaseURL.isEmpty && AuthManager.shared.accessToken != nil
    }

    func syncProEntitlement(jws: String) {
        let urlString = "\(supabaseURL)/functions/v1/gemini-proxy"
        guard let url = URL(string: urlString),
              let jwt = AuthManager.shared.accessToken else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "task": "markPro",
            "jws": jws
        ])
        session.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let quota = json["quota"] as? [String: Any] else { return }
            UsageTracker.shared.applyServerQuota(quota)
        }.resume()
    }
}
