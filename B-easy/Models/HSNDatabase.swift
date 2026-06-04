import Foundation

struct HSNCode: Codable {
    let code: String        
    let description: String 
    let gstRate: Double?  

    enum CodingKeys: String, CodingKey {
        case code, description
        case gstRate = "gstRate"
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
    private var codeMap: [String: HSNCode] = [:]
    private var isLoaded = false

    private let chapterRateMap: [String: Double] = [
        "01": 0, "02": 0, "03": 5, "04": 0, "0405": 12, "0406": 12,
        "07": 0, "08": 0, "0801": 5, "0802": 5,
        "09": 5,
        "10": 0, "1006": 5, "11": 0,
        "15": 5,
        "1701": 5, "1702": 18, "1704": 18,
        "18": 18,
        "19": 18, "190540": 5,
        "20": 12,
        "21": 18, "2106": 12,
        "2201": 18, "2202": 28,
        "24": 28,
        "30": 12,
        "3304": 28, "3305": 18, "3306": 18, "3307": 28,
        "3401": 18, "3402": 18,
        "4818": 12, "4820": 12, "48": 18,
        "85": 18,
        "96": 18,
    ]

    private init() {
        loadCodes()
    }

    private func loadCodes() {
        guard !isLoaded else { return }

        if let url = Bundle.main.url(forResource: "hsn_codes", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let codes = try? JSONDecoder().decode([HSNCode].self, from: data) {
            allCodes = codes
            codeMap = Dictionary(codes.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
            isLoaded = true
            print("[HSNDatabase] Loaded \(codes.count) HSN/SAC codes from bundle")
            return
        }

        allCodes = Self.commonKiranaHSNCodes
        codeMap = Dictionary(allCodes.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        isLoaded = true
        print("[HSNDatabase] Using built-in \(allCodes.count) common HSN codes")
    }

    func search(query: String, limit: Int = 20) -> [HSNCode] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        if let exact = codeMap[q] {
            return [exact]
        }

        let isNumericQuery = q.allSatisfy { $0.isNumber }
        if isNumericQuery {
            let codeMatches = allCodes.filter { $0.code.hasPrefix(q) }
            if !codeMatches.isEmpty {
                return Array(codeMatches.prefix(limit))
            }
        }

        let queryWords = q.split(separator: " ").map(String.init)
        var scored: [(code: HSNCode, score: Int)] = []

        for code in allCodes {
            let desc = code.description.lowercased()

            if desc.contains(q) {
                scored.append((code, 100))
                continue
            }

            var wordScore = 0
            for word in queryWords {
                if desc.contains(word) { wordScore += 10 }
            }
            if wordScore > 0 {
                let lengthBonus = max(0, 10 - code.code.count)
                scored.append((code, wordScore + lengthBonus))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.code)
    }

    func searchByName(query: String) -> HSNCode? {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return nil } 
        
        let queryWords = q.split(separator: " ").map(String.init)
        var bestMatch: HSNCode?
        var bestScore = 0
        
        for code in allCodes {
            let desc = code.description.lowercased()
            var score = 0
            
            if desc == q {
                return code
            }
            
            if desc.contains(q) {
                score = 100 + (q.count * 2)
            } else {
                for word in queryWords where word.count >= 3 {
                    if desc.contains(word) {
                        score += 15
                    }
                }
            }
            
            if score > 0 && code.gstRate != nil {
                score += 5
            }
            
            if score > 0 {
                score += max(0, 8 - code.code.count)
            }
            
            if score > bestScore {
                bestScore = score
                bestMatch = code
            }
        }
        
        return bestScore >= 15 ? bestMatch : nil
    }

    func lookup(code: String) -> HSNCode? {
        codeMap[code]
    }
    
    func lookupGSTRate(hsnCode: String) -> Double? {
        let code = hsnCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        
        if let entry = codeMap[code], let rate = entry.gstRate {
            return rate
        }
        
        let prefixMatches = allCodes.filter { $0.code.hasPrefix(code) && $0.gstRate != nil }
        if let first = prefixMatches.first {
            return first.gstRate
        }
    
        return suggestedGSTRate(for: code)
    }

    func suggestedGSTRate(for code: String) -> Double? {

        if let rate = codeMap[code]?.gstRate {
            return rate
        }

        var prefix = code
        while prefix.count >= 2 {
            if let rate = chapterRateMap[prefix] {
                return rate
            }
            prefix = String(prefix.dropLast())
        }

        return nil
    }

    var totalCodes: Int { allCodes.count }

    private static let commonKiranaHSNCodes: [HSNCode] = [
        HSNCode(code: "0401", description: "Fresh milk and pasteurised milk", gstRate: 0),
        HSNCode(code: "0402", description: "Milk powder, condensed milk", gstRate: 5),
        HSNCode(code: "0403", description: "Curd, lassi, buttermilk", gstRate: 0),
        HSNCode(code: "0405", description: "Butter and ghee", gstRate: 12),
        HSNCode(code: "0406", description: "Cheese and paneer", gstRate: 12),

        HSNCode(code: "0701", description: "Potatoes, fresh or chilled", gstRate: 0),
        HSNCode(code: "0702", description: "Tomatoes, fresh or chilled", gstRate: 0),
        HSNCode(code: "0703", description: "Onions, garlic, leeks", gstRate: 0),
        HSNCode(code: "0713", description: "Dried leguminous vegetables (dal, chana)", gstRate: 0),

        HSNCode(code: "0801", description: "Coconuts, cashew nuts", gstRate: 5),
        HSNCode(code: "0802", description: "Almonds, walnuts, pistachios", gstRate: 5),

        HSNCode(code: "0904", description: "Pepper (black/white)", gstRate: 5),
        HSNCode(code: "0909", description: "Cumin, coriander, fennel seeds", gstRate: 5),
        HSNCode(code: "0910", description: "Ginger, turmeric, saffron", gstRate: 5),

        HSNCode(code: "1001", description: "Wheat and meslin", gstRate: 0),
        HSNCode(code: "1006", description: "Rice", gstRate: 5),
        HSNCode(code: "1101", description: "Wheat flour (atta)", gstRate: 0),
        HSNCode(code: "1102", description: "Cereal flour (besan, rice flour)", gstRate: 0),

        HSNCode(code: "1512", description: "Sunflower or safflower oil", gstRate: 5),
        HSNCode(code: "1515", description: "Mustard oil, sesame oil", gstRate: 5),

        HSNCode(code: "1701", description: "Cane or beet sugar", gstRate: 5),
        HSNCode(code: "1806", description: "Chocolate", gstRate: 18),

        HSNCode(code: "1902", description: "Pasta, noodles, Maggi", gstRate: 18),
        HSNCode(code: "1905", description: "Bread, biscuits, cakes", gstRate: 18),

        HSNCode(code: "2201", description: "Mineral/packaged water", gstRate: 18),
        HSNCode(code: "2202", description: "Soft drinks, cola", gstRate: 28),

        HSNCode(code: "3305", description: "Shampoo, hair oil", gstRate: 18),
        HSNCode(code: "3306", description: "Toothpaste, mouthwash", gstRate: 18),
        HSNCode(code: "3401", description: "Soap", gstRate: 18),
        HSNCode(code: "3402", description: "Detergent (Surf, Tide)", gstRate: 18),

        HSNCode(code: "4820", description: "Notebooks, registers", gstRate: 12),
        HSNCode(code: "8506", description: "Batteries (dry cells)", gstRate: 18),
    ]
}
