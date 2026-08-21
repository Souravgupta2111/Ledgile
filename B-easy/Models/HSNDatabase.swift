// HSNDatabase.swift
// HSN (Harmonized System of Nomenclature) + SAC code database for product/service classification

import Foundation

struct HSNCode: Codable {
    let code: String        // e.g., "19021100" or "9954" (SAC)
    let description: String // e.g., "Uncooked pasta, not stuffed"
    let gstRate: Double?    // Suggested GST rate (nil if not known)

    enum CodingKeys: String, CodingKey {
        case code, description
        case gstRate = "gstRate"      // Not present in bundled JSON
    }

    init(code: String, description: String, gstRate: Double? = nil) {
        self.code = code
        self.description = description
        self.gstRate = gstRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        description = try container.decode(String.self, forKey: .description)
        gstRate = try container.decodeIfPresent(Double.self, forKey: .gstRate)
    }
}

final class HSNDatabase {

    static let shared = HSNDatabase()

    private var allCodes: [HSNCode] = []
    private var codeMap: [String: HSNCode] = [:]  // Exact code → HSNCode
    private var isLoaded = false

    // Common GST rate mappings by chapter prefix (for suggestion when rate isn't in JSON)
    private let chapterRateMap: [String: Double] = [
        // Chapter 01–05: Live animals, meat, dairy
        "01": 0, "02": 0, "03": 5, "04": 0, "0405": 12, "0406": 12,
        // Chapter 07–08: Vegetables, Fruits
        "07": 0, "08": 0, "0801": 5, "0802": 5,
        // Chapter 09: Spices
        "09": 5,
        // Chapter 10–11: Cereals, Flour
        "10": 0, "1006": 5, "11": 0,
        // Chapter 15: Oils
        "15": 5,
        // Chapter 17: Sugar
        "1701": 5, "1702": 18, "1704": 18,
        // Chapter 18: Chocolate
        "18": 18,
        // Chapter 19: Bakery, Noodles
        "19": 18, "190540": 5,
        // Chapter 20: Preserved food
        "20": 12,
        // Chapter 21: Misc food
        "21": 18, "2106": 12,
        // Chapter 22: Beverages
        "2201": 18, "2202": 28,
        // Chapter 24: Tobacco
        "24": 28,
        // Chapter 30: Pharma
        "30": 12,
        // Chapter 33–34: Personal care, Cleaning
        "3304": 28, "3305": 18, "3306": 18, "3307": 28,
        "3401": 18, "3402": 18,
        // Chapter 48: Paper
        "4818": 12, "4820": 12, "48": 18,
        // Chapter 85: Electronics
        "85": 18,
        // Chapter 96: Miscellaneous manufactured
        "96": 18,
    ]

    private init() {
        loadCodes()
    }

    // MARK: - Load from bundled JSON

    private func loadCodes() {
        guard !isLoaded else { return }

        if let url = Bundle.main.url(forResource: "hsn_codes", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let codes = try? JSONDecoder().decode([HSNCode].self, from: data) {
            allCodes = codes
            codeMap = Dictionary(codes.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
            isLoaded = true
            print("[HSNDatabase] ✅ Loaded \(codes.count) HSN/SAC codes from bundle")
            return
        }

        // Fallback: load built-in common codes
        allCodes = Self.commonKiranaHSNCodes
        codeMap = Dictionary(allCodes.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        isLoaded = true
        print("[HSNDatabase] ⚠️ Using built-in \(allCodes.count) common HSN codes")
    }

    // MARK: - Search

    /// Search HSN/SAC codes by description or code prefix
    /// Returns top matches, limited to `limit`
    func search(query: String, limit: Int = 20) -> [HSNCode] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        // Exact code match first
        if let exact = codeMap[q] {
            return [exact]
        }

        // Code prefix match (e.g., "1902" → all 1902xxx codes)
        let isNumericQuery = q.allSatisfy { $0.isNumber }
        if isNumericQuery {
            let codeMatches = allCodes.filter { $0.code.hasPrefix(q) }
            if !codeMatches.isEmpty {
                return Array(codeMatches.prefix(limit))
            }
        }

        // Description search — score by relevance
        let queryWords = q.split(separator: " ").map(String.init)
        var scored: [(code: HSNCode, score: Int)] = []

        for code in allCodes {
            let desc = code.description.lowercased()

            // Full query match (best)
            if desc.contains(q) {
                scored.append((code, 100))
                continue
            }

            // Word-level match
            var wordScore = 0
            for word in queryWords {
                if desc.contains(word) { wordScore += 10 }
            }
            if wordScore > 0 {
                // Prefer shorter codes (chapter-level) since they are more general
                let lengthBonus = max(0, 10 - code.code.count)
                scored.append((code, wordScore + lengthBonus))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.code)
    }

    // MARK: - Search by Item Name (fuzzy matching for autocomplete)
    
    /// Search for HSN codes by product/item name.
    /// Returns the best match (if any) with HSN code and GST rate.
    func searchByName(query: String) -> HSNCode? {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return nil }  // Need at least 3 chars for meaningful match
        
        let queryWords = q.split(separator: " ").map(String.init)
        var bestMatch: HSNCode?
        var bestScore = 0
        
        for code in allCodes {
            let desc = code.description.lowercased()
            var score = 0
            
            // Exact full match
            if desc == q {
                return code
            }
            
            // Full query contained in description
            if desc.contains(q) {
                score = 100 + (q.count * 2)  // Longer matches score higher
            } else {
                // Word-level matching
                for word in queryWords where word.count >= 3 {
                    if desc.contains(word) {
                        score += 15
                    }
                }
            }
            
            // Prefer entries with a GST rate defined
            if score > 0 && code.gstRate != nil {
                score += 5
            }
            
            // Prefer shorter HSN codes (more general/common)
            if score > 0 {
                score += max(0, 8 - code.code.count)
            }
            
            if score > bestScore {
                bestScore = score
                bestMatch = code
            }
        }
        
        // Only return if score is meaningful (at least one word match)
        return bestScore >= 15 ? bestMatch : nil
    }

    /// Lookup a specific HSN code
    func lookup(code: String) -> HSNCode? {
        codeMap[code]
    }
    
    /// Lookup GST rate for a given HSN code.
    /// First checks exact code, then walks up prefix hierarchy.
    /// Returns the rate as a Double (e.g. 18.0) or nil if not found.
    func lookupGSTRate(hsnCode: String) -> Double? {
        let code = hsnCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        
        // 1. Exact match in database
        if let entry = codeMap[code], let rate = entry.gstRate {
            return rate
        }
        
        // 2. Prefix match — find any code that starts with this
        let prefixMatches = allCodes.filter { $0.code.hasPrefix(code) && $0.gstRate != nil }
        if let first = prefixMatches.first {
            return first.gstRate
        }
        
        // 3. Walk up the chapter hierarchy
        return suggestedGSTRate(for: code)
    }

    /// Get suggested GST rate for an HSN code
    /// First checks the code's own rate, then walks up the chapter hierarchy
    func suggestedGSTRate(for code: String) -> Double? {
        // Check if the code itself has a rate
        if let rate = codeMap[code]?.gstRate {
            return rate
        }

        // Walk up the prefix hierarchy for chapter-level rate
        var prefix = code
        while prefix.count >= 2 {
            if let rate = chapterRateMap[prefix] {
                return rate
            }
            prefix = String(prefix.dropLast())
        }

        return nil
    }

    /// Total number of loaded codes
    var totalCodes: Int { allCodes.count }

    // MARK: - Built-in Common Kirana Store HSN Codes (Fallback)

    private static let commonKiranaHSNCodes: [HSNCode] = [
        // Dairy
        HSNCode(code: "0401", description: "Fresh milk and pasteurised milk", gstRate: 0),
        HSNCode(code: "0402", description: "Milk powder, condensed milk", gstRate: 5),
        HSNCode(code: "0403", description: "Curd, lassi, buttermilk", gstRate: 0),
        HSNCode(code: "0405", description: "Butter and ghee", gstRate: 12),
        HSNCode(code: "0406", description: "Cheese and paneer", gstRate: 12),

        // Vegetables
        HSNCode(code: "0701", description: "Potatoes, fresh or chilled", gstRate: 0),
        HSNCode(code: "0702", description: "Tomatoes, fresh or chilled", gstRate: 0),
        HSNCode(code: "0703", description: "Onions, garlic, leeks", gstRate: 0),
        HSNCode(code: "0713", description: "Dried leguminous vegetables (dal, chana)", gstRate: 0),

        // Fruits & Nuts
        HSNCode(code: "0801", description: "Coconuts, cashew nuts", gstRate: 5),
        HSNCode(code: "0802", description: "Almonds, walnuts, pistachios", gstRate: 5),

        // Spices
        HSNCode(code: "0904", description: "Pepper (black/white)", gstRate: 5),
        HSNCode(code: "0909", description: "Cumin, coriander, fennel seeds", gstRate: 5),
        HSNCode(code: "0910", description: "Ginger, turmeric, saffron", gstRate: 5),

        // Cereals & Flour
        HSNCode(code: "1001", description: "Wheat and meslin", gstRate: 0),
        HSNCode(code: "1006", description: "Rice", gstRate: 5),
        HSNCode(code: "1101", description: "Wheat flour (atta)", gstRate: 0),
        HSNCode(code: "1102", description: "Cereal flour (besan, rice flour)", gstRate: 0),

        // Oils
        HSNCode(code: "1512", description: "Sunflower or safflower oil", gstRate: 5),
        HSNCode(code: "1515", description: "Mustard oil, sesame oil", gstRate: 5),

        // Sugar & Confectionery
        HSNCode(code: "1701", description: "Cane or beet sugar", gstRate: 5),
        HSNCode(code: "1806", description: "Chocolate", gstRate: 18),

        // Bakery & Noodles
        HSNCode(code: "1902", description: "Pasta, noodles, Maggi", gstRate: 18),
        HSNCode(code: "1905", description: "Bread, biscuits, cakes", gstRate: 18),

        // Beverages
        HSNCode(code: "2201", description: "Mineral/packaged water", gstRate: 18),
        HSNCode(code: "2202", description: "Soft drinks, cola", gstRate: 28),

        // Personal care
        HSNCode(code: "3305", description: "Shampoo, hair oil", gstRate: 18),
        HSNCode(code: "3306", description: "Toothpaste, mouthwash", gstRate: 18),
        HSNCode(code: "3401", description: "Soap", gstRate: 18),
        HSNCode(code: "3402", description: "Detergent (Surf, Tide)", gstRate: 18),

        // Stationery
        HSNCode(code: "4820", description: "Notebooks, registers", gstRate: 12),
        HSNCode(code: "8506", description: "Batteries (dry cells)", gstRate: 18),
    ]
}
