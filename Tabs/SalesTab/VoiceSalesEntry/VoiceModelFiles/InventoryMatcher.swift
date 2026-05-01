
import Foundation
struct MatchResult {
    let item: Item
    let confidence: Double
    let matchType: String
}

final class InventoryMatcher {
    
    static let shared = InventoryMatcher()
    
    
     let aliases: [String: String] = [
        "aloo": "aloo", "aaloo": "aloo", "alu": "aloo", "alloo": "aloo", "potato": "aloo", "potatoes": "aloo", "batata": "aloo",
        "pyaaz": "onion", "pyaz": "onion", "piyas": "onion", "piyaz": "onion", "onion": "onion", "onions": "onion", "kanda": "onion",
        "tamatar": "tomato", "tomato": "tomato", "tomatoes": "tomato",
        "gobhi": "cauliflower", "gobi": "cauliflower", "cauliflower": "cauliflower", "phool gobhi": "cauliflower",
        "band gobhi": "cabbage", "patta gobhi": "cabbage", "cabbage": "cabbage",
        "bhindi": "ladyfinger", "bhendi": "ladyfinger", "okra": "ladyfinger", "ladyfinger": "ladyfinger",
        "palak": "spinach", "spinach": "spinach",
        "gajar": "carrot", "carrot": "carrot", "carrots": "carrot",
        "matar": "peas", "peas": "peas", "green peas": "peas",
        "shimla": "capsicum", "shimla mirch": "capsicum", "capsicum": "capsicum",
        "adrak": "ginger", "ginger": "ginger",
        "lehsun": "garlic", "garlic": "garlic", "lasun": "garlic", "lasan": "garlic",
        "dhaniya": "coriander", "dhania": "coriander", "coriander": "coriander", "kothimbir": "coriander",
        "baingan": "brinjal", "brinjal": "brinjal", "eggplant": "brinjal", "vangi": "brinjal",
        "mirch": "chilli", "mirchi": "chilli", "chilli": "chilli", "chillies": "chilli", "green chilli": "chilli", "hari mirch": "chilli",
        "lal mirch": "red chilli", "red chilli": "red chilli",
        "lauki": "bottle gourd", "dudhi": "bottle gourd", "bottle gourd": "bottle gourd",
        "karela": "bitter gourd", "bitter gourd": "bitter gourd",
        "mooli": "radish", "radish": "radish",
        "kheera": "cucumber", "kakdi": "cucumber", "cucumber": "cucumber",
        "neebu": "lemon", "nimbu": "lemon", "lemon": "lemon", "lime": "lemon",
        
        "seb": "apple", "apple": "apple", "apples": "apple",
        "kela": "banana", "banana": "banana", "bananas": "banana",
        "santra": "orange", "orange": "orange", "oranges": "orange",
        "aam": "mango", "mango": "mango", "mangoes": "mango",
        "angoor": "grapes", "grapes": "grapes",
        "anar": "pomegranate", "pomegranate": "pomegranate",
        "papita": "papaya", "papaya": "papaya",
        "tarbooz": "watermelon", "watermelon": "watermelon",
        
        "doodh": "milk", "milk": "milk",
        "dahi": "curd", "curd": "curd", "yogurt": "curd",
        "makhan": "butter", "butter": "butter",
        "ghee": "ghee",
        "paneer": "paneer", "cheese": "paneer", "cottage cheese": "paneer",
        "chaas": "buttermilk", "buttermilk": "buttermilk", "lassi": "lassi",
        
        "chawal": "rice", "rice": "rice", "basmati": "rice",
        "gehun": "wheat", "wheat": "wheat",
        "atta": "atta", "flour": "atta", "wheat flour": "atta",
        "maida": "maida", "all purpose flour": "maida", "refined flour": "maida",
        "besan": "besan", "gram flour": "besan",
        "suji": "suji", "semolina": "suji", "rava": "suji",
        "cheeni": "sugar", "sugar": "sugar", "shakkar": "sugar",
        "namak": "salt", "salt": "salt",
        "tel": "oil", "oil": "oil", "cooking oil": "oil",
        "sarso tel": "mustard oil", "mustard oil": "mustard oil",
        "refine": "refined oil", "refined oil": "refined oil",
        "dal": "dal", "daal": "dal", "lentils": "dal",
        
        "chana": "chana", "chickpea": "chana", "chickpeas": "chana", "kala chana": "chana",
        "moong": "moong dal", "mung": "moong dal", "moong dal": "moong dal",
        "masoor": "masoor dal", "masoor dal": "masoor dal",
        "urad": "urad dal", "urad dal": "urad dal",
        "tuvar": "toor dal", "toor": "toor dal", "arhar": "toor dal",
        "rajma": "rajma", "kidney beans": "rajma",
        "chole": "chole", "kabuli chana": "chole",
        
        "haldi": "turmeric", "turmeric": "turmeric", "turmeric powder": "turmeric",
        "jeera": "cumin", "cumin": "cumin", "cumin seeds": "cumin",
        "dhania powder": "coriander powder", "coriander powder": "coriander powder",
        "garam masala": "garam masala",
        "rai": "mustard seeds", "mustard seeds": "mustard seeds",
        "methi": "fenugreek", "fenugreek": "fenugreek",
        "saunf": "fennel", "fennel seeds": "fennel",
        "elaichi": "cardamom", "cardamom": "cardamom",
        "laung": "clove", "cloves": "clove",
        "kaali mirch": "black pepper", "black pepper": "black pepper",
        
        "maggi": "maggi", "noodles": "maggi", "instant noodles": "maggi",
        "biscuit": "biscuit", "biscuits": "biscuit", "parle g": "biscuit", "mari gold": "biscuit",
        "bread": "bread",
        "chips": "chips", "lays": "chips", "kurkure": "chips",
        "chocolate": "chocolate", "cadbury": "chocolate", "5star": "5 star", "five star": "5 star", "kitkat": "chocolate",
        "coke": "coca cola", "cocacola": "coca cola", "coca cola": "coca cola", "pepsi": "pepsi", "thums up": "thums up", "7up": "7 up", "seven up": "7 up", "sprite": "sprite", "maaza": "maaza", "frooti": "frooti",
        "water": "water", "paani": "water", "bisleri": "water", "mineral water": "water",
        
        "sabun": "soap", "soap": "soap", "lux": "soap", "lifebuoy": "soap", "dettol": "soap",
        "detergent": "detergent", "surf": "detergent", "surf excel": "detergent", "tide": "detergent", "ariel": "detergent", "washing powder": "detergent",
        "shampoo": "shampoo", "clinic plus": "shampoo", "sunsilk": "shampoo", "head and shoulders": "shampoo",
        "toothpaste": "toothpaste", "colgate": "toothpaste", "pepsodent": "toothpaste", "close up": "toothpaste",
        "brush": "toothbrush", "toothbrush": "toothbrush",
        "incense": "agarbatti", "agarbatti": "agarbatti",
        "matchbox": "matchbox", "maachis": "matchbox",
    ]
    
    
     var inventoryEmbeddings: [String: [Float]] = [:]
    
    
    func indexInventory(_ items: [Item]) {
        let itemNames = items.map { $0.name }
        MiniLMEncoder.shared.batchEncode(itemNames) { embeddings in
            for (index, embedding) in embeddings.enumerated() {
                if let emb = embedding {
                    self.inventoryEmbeddings[itemNames[index]] = emb
                }
            }
            if !self.inventoryEmbeddings.isEmpty {
            }
        }
    }
    
     func rerank(query: String, candidates: [(item: Item, score: Double)]) -> MatchResult? {
        guard let queryEmbedding = MiniLMEncoder.shared.encode(query),
              !inventoryEmbeddings.isEmpty else {
            return nil
        }
        
        var bestSemMatch: (item: Item, score: Double)?
        
        
        for (item, baseScore) in candidates {
            if let itemEmb = inventoryEmbeddings[item.name] {
                let semScore = Double(queryEmbedding.cosineSimilarity(with: itemEmb))
                let finalScore = (semScore * 0.7) + (baseScore * 0.3)
                
                if finalScore > 0.6 {
                    if bestSemMatch == nil || finalScore > bestSemMatch!.score {
                        bestSemMatch = (item, finalScore)
                    }
                }
            }
        }
        
        if bestSemMatch == nil {
             for (name, emb) in inventoryEmbeddings {
                 let score = Double(queryEmbedding.cosineSimilarity(with: emb))
                 if score > 0.75 {
                     if let item = candidates.first(where: { $0.item.name == name })?.item {
                          if bestSemMatch == nil || score > bestSemMatch!.score {
                             bestSemMatch = (item, score)
                         }
                     }
                 }
             }
        }

        if let best = bestSemMatch {
            return MatchResult(item: best.item, confidence: best.score, matchType: "semantic_minilm")
        }
        
        return nil
    }
    
    
    func match(name: String, against items: [Item]) -> MatchResult? {
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !normalizedName.isEmpty, !items.isEmpty else { return nil }
        
        if let userCanonical = UserAliasManager.shared.getCanonical(for: normalizedName) {
            if let userMatch = items.first(where: { $0.name.lowercased() == userCanonical }) {
                return MatchResult(item: userMatch, confidence: 1.0, matchType: "user_alias")
            }
        }
        
        if let exactMatch = items.first(where: { $0.name.lowercased() == normalizedName }) {
            return MatchResult(item: exactMatch, confidence: 1.0, matchType: "exact")
        }
        
        if let translitMatch = matchViaTransliteration(normalizedName, items: items) {
            return translitMatch
        }
        
        var candidates: [(item: Item, score: Double)] = []
        
        if let canonical = aliases[normalizedName] {
            if let aliasMatch = items.first(where: { $0.name.lowercased() == canonical }) {
                return MatchResult(item: aliasMatch, confidence: 0.98, matchType: "alias_exact")
            }
            if let aliasContains = items.first(where: { $0.name.lowercased().contains(canonical) }) {
                 candidates.append((aliasContains, 0.95))
            }
        }
        
        let latinForm = transliterateToLatin(normalizedName)
        if latinForm != normalizedName, let canonical = aliases[latinForm] {
            if let aliasMatch = items.first(where: { $0.name.lowercased() == canonical }) {
                return MatchResult(item: aliasMatch, confidence: 0.96, matchType: "translit_alias")
            }
            if let aliasContains = items.first(where: { $0.name.lowercased().contains(canonical) }) {
                candidates.append((aliasContains, 0.93))
            }
        }
        
        for item in items {
            let itemName = item.name.lowercased()
             if itemName.split(separator: " ").contains(where: { normalizedName.contains($0) }) {
                 candidates.append((item, 0.85))
             }
        }
        
        for item in items {
            let itemName = item.name.lowercased()
            let dist = levenshteinDistance(normalizedName, itemName)
            let minLen = min(normalizedName.count, itemName.count)
            let maxAllowedDist = minLen < 4 ? 0 : (minLen <= 6 ? 1 : 2)
            
            if dist <= maxAllowedDist {
                 let score = dist == 0 ? 1.0 : (dist == 1 ? 0.9 : 0.8)
                 candidates.append((item, score))
            }
        }
        
        if candidates.isEmpty {
            let queryLatin = transliterateToLatin(normalizedName)
            for item in items {
                let itemLatin = transliterateToLatin(item.name.lowercased())
                let dist = levenshteinDistance(queryLatin, itemLatin)
                let minLen = min(queryLatin.count, itemLatin.count)
                let maxAllowedDist = minLen < 4 ? 1 : (minLen <= 6 ? 2 : 3)
                if dist <= maxAllowedDist && dist < minLen {
                    let score = dist == 0 ? 0.95 : (dist <= 1 ? 0.85 : 0.75)
                    candidates.append((item, score))
                }
            }
        }
        
        candidates.sort { $0.score > $1.score }
        
       
        if let semanticMatch = rerank(query: normalizedName, candidates: candidates) {
            return semanticMatch
        }
        
        if let best = candidates.first {
            return MatchResult(item: best.item, confidence: best.score, matchType: "fuzzy_best")
        }
        
        let nameSoundex = soundex(normalizedName)
        for item in items {
            let itemSoundex = soundex(item.name.lowercased())
            if nameSoundex == itemSoundex && nameSoundex != "0000" && abs(normalizedName.count - item.name.count) <= 2 {
                return MatchResult(item: item, confidence: 0.70, matchType: "soundex")
            }
        }
        
        return nil
    }
    
   
    func getSuggestions(for query: String, against items: [Item], limit: Int = 5) -> [Item] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        
        let exactMatches = items.filter { item in
            let name = item.name.lowercased()
            return name.hasPrefix(normalizedQuery) || name.contains(normalizedQuery)
        }
        
        var results = exactMatches.sorted { a, b in
            let aName = a.name.lowercased()
            let bName = b.name.lowercased()
            let aPrefix = aName.hasPrefix(normalizedQuery)
            let bPrefix = bName.hasPrefix(normalizedQuery)
            
            if aPrefix && !bPrefix { return true }
            if !aPrefix && bPrefix { return false }
            return aName.count < bName.count
        }
        
        if results.count < limit {
            let maxDist = normalizedQuery.count < 4 ? 1 : 2
            
            let fuzzyMatches = items.filter { item in
                if results.contains(where: { $0.id == item.id }) { return false }
                
                let name = item.name.lowercased()
                
                if abs(name.count - normalizedQuery.count) > maxDist { return false }
                
                let dist = levenshteinDistance(normalizedQuery, name)
                return dist <= maxDist
            }
            
            let sortedFuzzy = fuzzyMatches.sorted { a, b in
                let distA = levenshteinDistance(normalizedQuery, a.name.lowercased())
                let distB = levenshteinDistance(normalizedQuery, b.name.lowercased())
                return distA < distB
            }
            
            results.append(contentsOf: sortedFuzzy)
        }
        
        return Array(results.prefix(limit))
    }
    
    func matchProducts(
        products: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)],
        items: [Item]
    ) -> [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?, itemID: UUID?, matchConfidence: Double, originalName: String)] {
        
        return products.map { product in
            if let result = match(name: product.name, against: items) {
                
                let price = product.price
                let unit = product.unit
                let costPrice = product.costPrice
                
                return (
                    name: result.item.name,
                    quantity: product.quantity,
                    unit: unit,
                    price: price,
                    costPrice: costPrice,
                    itemID: result.item.id,
                    matchConfidence: result.confidence,
                    originalName: product.name
                )
            } else {
                return (
                    name: product.name,
                    quantity: product.quantity,
                    unit: product.unit,
                    price: product.price,
                    costPrice: product.costPrice,
                    itemID: nil as UUID?,
                    matchConfidence: 0.0,
                    originalName: product.name
                )
            }
        }
    }
    
    
    func transliterateToLatin(_ text: String) -> String {
        guard let latinized = text.applyingTransform(.toLatin, reverse: false) else {
            return text
        }
        guard let stripped = latinized.applyingTransform(.stripDiacritics, reverse: false) else {
            return latinized.lowercased()
        }
        return stripped.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func transliterateToDevanagari(_ text: String) -> String {
        guard let devnagari = text.applyingTransform(StringTransform("Latin-Devanagari"), reverse: false) else {
            return text
        }
        return devnagari
    }
    
    func containsDevanagari(_ text: String) -> Bool {
        return text.unicodeScalars.contains { scalar in
            return (0x0900...0x097F).contains(scalar.value)
        }
    }
    
     func matchViaTransliteration(_ normalizedName: String, items: [Item]) -> MatchResult? {
        let isDevanagari = containsDevanagari(normalizedName)
        
        if isDevanagari {
            let latinForm = transliterateToLatin(normalizedName)
            print("[InventoryMatcher] Transliterated '\(normalizedName)' → '\(latinForm)'")
            
            if let match = items.first(where: { $0.name.lowercased() == latinForm }) {
                return MatchResult(item: match, confidence: 0.97, matchType: "translit_exact")
            }
            
            if let match = items.first(where: {
                $0.name.lowercased().contains(latinForm) || latinForm.contains($0.name.lowercased())
            }) {
                return MatchResult(item: match, confidence: 0.92, matchType: "translit_contains")
            }
            
            if let canonical = aliases[latinForm] {
                if let match = items.first(where: { $0.name.lowercased() == canonical }) {
                    return MatchResult(item: match, confidence: 0.95, matchType: "translit_alias")
                }
                if let match = items.first(where: { $0.name.lowercased().contains(canonical) }) {
                    return MatchResult(item: match, confidence: 0.90, matchType: "translit_alias_contains")
                }
            }
            
            for item in items {
                let itemLower = item.name.lowercased()
                let dist = levenshteinDistance(latinForm, itemLower)
                let minLen = min(latinForm.count, itemLower.count)
                if dist <= 2 && dist < minLen {
                    return MatchResult(item: item, confidence: 0.85, matchType: "translit_fuzzy")
                }
            }
        } else {
            for item in items {
                let itemName = item.name.lowercased()
                if containsDevanagari(itemName) {
                    let itemLatin = transliterateToLatin(itemName)
                    if itemLatin == normalizedName {
                        return MatchResult(item: item, confidence: 0.97, matchType: "translit_exact")
                    }
                    let dist = levenshteinDistance(normalizedName, itemLatin)
                    if dist <= 2 && dist < min(normalizedName.count, itemLatin.count) {
                        return MatchResult(item: item, confidence: 0.85, matchType: "translit_fuzzy")
                    }
                }
            }
        }
        
        return nil
    }
    
    
     func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                dp[i][j] = min(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + cost
                )
            }
        }
        
        return dp[m][n]
    }
    
   
     func soundex(_ input: String) -> String {
        let str = input.lowercased().filter { $0.isLetter }
        guard let first = str.first else { return "0000" }
        
        let mapping: [Character: Character] = [
            "b": "1", "f": "1", "p": "1", "v": "1",
            "c": "2", "g": "2", "j": "2", "k": "2", "q": "2", "s": "2", "x": "2", "z": "2",
            "d": "3", "t": "3",
            "l": "4",
            "m": "5", "n": "5",
            "r": "6"
        ]
        
        var result = String(first).uppercased()
        var lastCode: Character? = mapping[first]
        
        for char in str.dropFirst() {
            if let code = mapping[char] {
                if code != lastCode {
                    result.append(code)
                    if result.count == 4 { break }
                }
                lastCode = code
            } else {
                lastCode = nil
            }
        }
        
        while result.count < 4 { result.append("0") }
        return result
    }
}
