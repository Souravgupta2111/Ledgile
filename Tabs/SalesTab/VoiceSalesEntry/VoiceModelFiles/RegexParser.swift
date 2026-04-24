
import Foundation

class RegexParser {
    
    static let shared = RegexParser()
    
    // MARK: - Cached Regex (compiled once, reused)
     var cachedNumberRegex: [(NSRegularExpression, String)] = []
     var _unitSet: Set<String>?
     var _cachedProductRegexes: [String: NSRegularExpression] = [:]
    
    // MARK: - Number Dictionaries
    
   
     let hindiNumbers: [String: String] = [
        // Basic 1-10
        "ek": "1", "एक": "1",
        "do": "2", "दो": "2",
        "teen": "3", "tin": "3", "तीन": "3",
        "char": "4", "chaar": "4", "चार": "4",
        "paanch": "5", "panch": "5", "punch": "5", "पांच": "5", "पाँच": "5",
        "chhe": "6", "che": "6", "chhah": "6", "छह": "6", "छः": "6",
        "saat": "7", "sat": "7", "सात": "7",
        "aath": "8", "aat": "8", "आठ": "8",
        "nau": "9", "no": "9", "नौ": "9",
        "das": "10", "dus": "10", "दस": "10",
        
        // 11-20
        "gyarah": "11", "gyara": "11", "ग्यारह": "11",
        "barah": "12", "bara": "12", "बारह": "12",
        "terah": "13", "tera": "13", "तेरह": "13",
        "chaudah": "14", "chauda": "14", "चौदह": "14",
        "pandrah": "15", "pandra": "15", "पंद्रह": "15",
        "solah": "16", "sola": "16", "सोलह": "16",
        "satrah": "17", "satra": "17", "सत्रह": "17",
        "atharah": "18", "athara": "18", "अठारह": "18",
        "unnis": "19", "उन्नीस": "19",
        "bees": "20", "bis": "20", "बीस": "20",
        
        // Tens
        "tees": "30", "tis": "30", "तीस": "30",
        "chalis": "40", "challis": "40", "चालीस": "40",
        "pachas": "50", "pachpan": "55", "पचास": "50",
        "saath": "60", "साठ": "60",
        "sattar": "70", "सत्तर": "70",
        "assi": "80", "अस्सी": "80",
        "nabbe": "90", "नब्बे": "90",
        "sau": "100", "सौ": "100",
        
        // Fractions (very common in retail)
        "aadha": "0.5", "adha": "0.5", "आधा": "0.5",
        "paav": "0.25", "pav": "0.25", "pao": "0.25", "पाव": "0.25",
        "sawa": "1.25", "sava": "1.25", "सवा": "1.25",
        "dedh": "1.5", "dhadh": "1.5", "डेढ़": "1.5",
        "dhai": "2.5", "dhaai": "2.5", "ढाई": "2.5",
        "saadhe": "0.5", "sadhe": "0.5", // prefix for X.5
        
        // Multiples
        "darjan": "12", "darzan": "12", "दर्जन": "12",
        "hazaar": "1000", "hazar": "1000", "हज़ार": "1000"
    ]
    
    /// English numbers
     let englishNumbers: [String: String] = [
        "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
        "eleven": "11", "twelve": "12", "thirteen": "13", "fourteen": "14", "fifteen": "15",
        "sixteen": "16", "seventeen": "17", "eighteen": "18", "nineteen": "19", "twenty": "20",
        "thirty": "30", "forty": "40", "fifty": "50", "sixty": "60",
        "seventy": "70", "eighty": "80", "ninety": "90", "hundred": "100",
        "dozen": "12", "half": "0.5", "quarter": "0.25"
    ]
    
    // MARK: - Unit Dictionaries
    

     let unitMappings: [String: String] = [
      
        "kg": "kg", "kilo": "kg", "kilos": "kg", "kilogram": "kg", "kilograms": "kg",
        "केजी": "kg", "किलो": "kg",
        
     
        "g": "g", "gm": "g", "gms": "g", "gram": "g", "grams": "g", "grm": "g",
        "ग्राम": "g",
        
 
        "quintal": "quintal", "क्विंटल": "quintal",
        "ton": "ton", "टन": "ton",
        
      
        "l": "l", "ltr": "l", "litre": "l", "litres": "l", "liter": "l", "liters": "l",
        "लीटर": "l",
        
     
        "ml": "ml", "milliliter": "ml", "milliliters": "ml", "मिली": "ml",
        

        "pcs": "pcs", "pc": "pcs", "piece": "pcs", "pieces": "pcs", "nos": "pcs", "number": "pcs",
        "पीस": "pcs", "नग": "pcs", "dana": "pcs", "daana": "pcs", "दाना": "pcs",
        
       
        "pack": "pack", "packs": "pack", "packet": "pack", "packets": "pack",
        "पैकेट": "pack",
        
    
        "box": "box", "boxes": "box", "dabba": "box", "डब्बा": "box",
      
        "dozen": "dozen", "doz": "dozen", "dz": "dozen", "darjan": "dozen", "darzan": "dozen",
        "दर्जन": "dozen",
        
     
        "bundle": "bundle", "bundles": "bundle", "bunch": "bundle",
        "गड्डी": "bundle", "जोड़ी": "pair",
        
   
        "bag": "bag", "bags": "bag", "bori": "bag", "बोरी": "bag",
        "crate": "crate", "peti": "crate", "पेटी": "crate",
        "tray": "tray", "plate": "plate", "thali": "plate",
        

        "katta": "katta", "कट्टा": "katta",
        "ladi": "ladi", "लड़ी": "ladi",
        "patta": "patta", "पत्ता": "patta",
    ]
    
     var allUnits: [String] { Array(unitMappings.keys) }
    
    // MARK: - Common Retail Items (for validation)
    
     let commonItems = Set([
       
        "potato", "potatoes", "onion", "onions", "tomato", "tomatoes",
        "cabbage", "carrot", "carrots", "beans", "peas", "spinach",
        "cauliflower", "brinjal", "okra", "ladyfinger", "capsicum",
        "cucumber", "ginger", "garlic", "chilli", "chillies", "coriander",
        
       
        "aloo", "aaloo", "आलू", "pyaaz", "pyaz", "प्याज़", "tamatar", "टमाटर",
        "gobhi", "गोभी", "gajar", "गाजर", "matar", "मटर", "palak", "पालक",
        "bhindi", "भिंडी", "baingan", "बैंगन", "shimla", "mirch", "मिर्च",
        "adrak", "अदरक", "lehsun", "लहसुन", "dhaniya", "धनिया",
        

        "apple", "apples", "banana", "bananas", "orange", "oranges",
        "mango", "mangoes", "grapes", "watermelon", "papaya",
        "seb", "सेब", "kela", "केला", "santra", "संतरा", "aam", "आम",
        "angoor", "अंगूर", "tarbooz", "तरबूज",
        
     
        "milk", "doodh", "दूध", "curd", "dahi", "दही",
        "butter", "makhan", "मक्खन", "ghee", "घी",
        "paneer", "पनीर", "cheese", "cream",
        
    
        "rice", "chawal", "चावल", "wheat", "gehun", "गेहूं",
        "flour", "atta", "आटा", "maida", "मैदा",
        "sugar", "cheeni", "चीनी", "salt", "namak", "नमक",
        "oil", "tel", "तेल", "dal", "daal", "दाल",
        
     
        "chana", "चना", "moong", "मूंग", "masoor", "मसूर",
        "urad", "उड़द", "rajma", "राजमा", "chole", "छोले",
        
   
        "haldi", "हल्दी", "jeera", "जीरा", "dhania", "सरसों",
        
 
        "pen", "pens", "pencil", "pencils", "eraser", "erasers",
        "notebook", "notebooks", "copy", "copies", "book", "books",
        "paper", "papers", "register", "registers",
 
        "item", "items", "product", "products", "goods", "samaan", "सामान",

         // Dry Fruits & Nuts
         "cashew", "cashews", "kaju", "काजू",
         "almond", "almonds", "badam", "बादाम",
         "raisin", "raisins", "kishmish", "किशमिश",
         "peanut", "peanuts", "moongfali", "मूंगफली",
         "walnut", "walnuts", "akhrot", "अखरोट",
         "pistachio", "pistachios", "pista", "पिस्ता",
         "nuts"
    ])
    
    // MARK: - Main Parse Function
    
    func parse(text: String) -> ParsedResult {
        
        let processed = preprocessText(text)
        
        let customerName = extractCustomer(from: text)
        if let cust = customerName {
        }
        
        let prices = extractPrices(from: processed)
        
        // First check for Variant patterns (Item + Size + Qty) to avoid splitting them
        let variantProducts = extractVariantProducts(from: processed, prices: prices, excludeNames: [customerName?.lowercased()].compactMap { $0 })
        var products = variantProducts
        
        //  Extract standard products WITH units (exclude names already found in variants)
        var excludeList = [customerName?.lowercased()].compactMap { $0 }
        for vp in variantProducts {
            excludeList.append(vp.name)
        }
        
        let standardProducts = extractProducts(from: processed, prices: prices, excludeNames: excludeList)
        products.append(contentsOf: standardProducts)
        let existingNames = products.map { $0.name.lowercased() }
        let noUnitProducts = extractProductsWithoutUnit(from: processed, prices: prices, excludeNames: excludeList + existingNames)
        products.append(contentsOf: noUnitProducts)
        
        if products.isEmpty {
            products = extractProductsFallback(from: processed, prices: prices, excludeNames: [customerName?.lowercased()].compactMap { $0 })
        }
        
        for p in products {
        }
        
        return ParsedResult(
            entities: [],
            products: products,
            customerName: customerName,
            isNegation: false,
            isReference: false,
            productItemIDs: nil,
            productConfidences: nil
        )
    }
    
    // MARK: - Preprocessing
    
     func preprocessText(_ text: String) -> String {
        var result = text.lowercased()
        
        // Fix common speech recognition errors
        let corrections: [String: String] = [
            "penton": "pencil", "pentatonic": "pencil",
            "chalo": "char", // common mishearing
            "aaloo": "aloo", "alloo": "aloo",
            "piyas": "pyaaz", "piyaz": "pyaaz",
            "killo": "kilo", "keelo": "kilo",
            "rupay": "rupees", "rupaye": "rupees", "rupiyaa": "rupees",
            "of400": "of 400", "of40": "of 40", "of100": "of 100", // fix space
        ]
        
        for (wrong, correct) in corrections {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }
        
        result = result.replacingOccurrences(of: "₹", with: " ₹")
        
        
        result = result.replacingOccurrences(of: ",", with: " ")
        
        // Strip question marks and other punctuation that can break patterns
        result = result.replacingOccurrences(of: "?", with: " ")
        result = result.replacingOccurrences(of: "!", with: " ")
        // Strip periods only when NOT between digits (preserve decimals like 49.50)
        result = result.replacingOccurrences(
            of: "(?<!\\d)\\.(?!\\d)",
            with: " ",
            options: .regularExpression
        )
        
        result = convertNumbersToDigits(result)
        
        
        result = result.replacingOccurrences(of: "\\b5 star\\b", with: "5star", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\bfive star\\b", with: "5star", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\b7 up\\b", with: "7up", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\bseven up\\b", with: "7up", options: .regularExpression)
        
        // Normalize spaces
        result = result.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        
        return result
    }
    
     func convertNumbersToDigits(_ text: String) -> String {
        if cachedNumberRegex.isEmpty {
            var allNumbers = hindiNumbers
            allNumbers.merge(englishNumbers) { (_, new) in new }
            let sortedWords = allNumbers.keys.sorted { $0.count > $1.count }
            for word in sortedWords {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    cachedNumberRegex.append((regex, allNumbers[word]!))
                }
            }
        }
        
        var result = text
        for (regex, replacement) in cachedNumberRegex {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }
        return result
    }
    
    // MARK: - Customer Extraction
    
     func extractCustomer(from text: String) -> String? {
        let patterns = [
            // Hindi patterns — capture multi-word names
            "([a-z]+(?:\\s+[a-z]+)*)\\s+ko\\b",           // "rahul sharma ko"
            "([a-z]+(?:\\s+[a-z]+)*)\\s+ke\\s+liye\\b",   // "rahul ke liye"
            "([a-z]+(?:\\s+[a-z]+)*)\\s+ka\\s+bill\\b",   // "rahul ka bill"
            "([a-z]+(?:\\s+[a-z]+)*)\\s+ke\\s+naam\\b",   // "rahul ke naam"
            
            // English patterns — capture multi-word names
            "sold\\s+to\\s+(?:mr\\.?\\s+|mrs\\.?\\s+|ms\\.?\\s+)?([a-z]+(?:\\s+[a-z]+)*)",  // "sold to rahul sharma"
            "\\bto\\s+([a-z]+(?:\\s+[a-z]+)*)\\s+at\\b",                                    // "to rahul at the rate"
            "\\bto\\s+(?:mr\\.?\\s+)?([a-z]+(?:\\s+[a-z]+)?)(?:\\s+at|\\s*$)",             // "to mr rahul sharma"
            "\\bfor\\s+(?:mr\\.?\\s+)?([a-z]+(?:\\s+[a-z]+)?)\\b",                         // "for rahul sharma"
            "customer\\s+(?:is\\s+)?(?:mr\\.?\\s+)?([a-z]+(?:\\s+[a-z]+)?)",               // "customer is rahul sharma"
            "\\bmr\\.?\\s+([a-z]+(?:\\s+[a-z]+)?)\\b",                                     // "mr rahul sharma"
            "\\bgive\\s+(?:mr\\.?\\s+)?([a-z]+(?:\\s+[a-z]+)?)\\s+\\d",                    // "give mr rahul 10 kg"
        ]
        
        for pattern in patterns {
            if let name = matchGroup(pattern: pattern, in: text, group: 1) {
                var filtered = name.trimmingCharacters(in: .whitespaces)
                let invalidNames = Set(["the", "a", "an", "this", "that", "total", "rate", "price",
                                       "char", "ek", "do", "teen", "four", "five", "give", "sold",
                                       "kg", "kilo", "piece", "pieces"])
                // Check each word in the name isn't fully invalid
                let nameWords = filtered.lowercased().split(separator: " ").map { String($0) }
                let validWords = nameWords.filter { !invalidNames.contains($0) }
                
                if !validWords.isEmpty {
                    filtered = validWords.joined(separator: " ")
                    if filtered.count > 2 {
                        // Capitalize each word of the customer name
                        return filtered.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
                    }
                }
            }
        }
        return nil
    }
    
    // MARK: - Price Extraction
    
     func extractPrices(from text: String) -> [String] {
        var prices: [String] = []
        
        let patterns = [
            "₹\\s*(\\d+(?:\\.\\d+)?)",                    // ₹400, ₹ 400
            "(\\d+(?:\\.\\d+)?)\\s*(?:₹|rupees?|rs\\.?)", // 400₹, 400 rupees
            "(?:rate|bhav|bhaw)\\s+(?:of\\s+)?(\\d+(?:\\.\\d+)?)",  // rate of 400, bhav 400
            "(?:total|kul)\\s+(?:of\\s+)?(\\d+(?:\\.\\d+)?)",      // total 400
            "@\\s*(\\d+(?:\\.\\d+)?)",                    // @400
            "(?:per|prति)\\s+(?:kg|kilo|piece)?\\s*(\\d+(?:\\.\\d+)?)", // per kg 40
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsString = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
                for match in matches {
                    if match.numberOfRanges > 1 {
                        let price = nsString.substring(with: match.range(at: 1))
                        if !prices.contains(price) {
                            prices.append(price)
                        }
                    }
                }
            }
        }
        
        return prices
    }
    
    // MARK: - Product Extraction (Performance-optimized)
    
     var unitSet: Set<String> {
        if let s = _unitSet { return s }
        _unitSet = Set(unitMappings.keys.map { $0.lowercased() })
        return _unitSet!
    }
    
     func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        if let cached = _cachedProductRegexes[pattern] {
            return cached
        }
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            _cachedProductRegexes[pattern] = regex
            return regex
        }
        return nil
    }
    
     func extractProducts(from text: String, prices: [String], excludeNames: [String] = []) -> [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] {
        var results: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = []
        
        let unitsPattern = allUnits.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        
        // Track ranges consumed by Pattern 1 so Pattern 2 doesn't steal their quantities
        var consumedRanges: [NSRange] = []
        
        // Pattern 1: Qty + Unit + [of]? + Item (single word capture, expand after)
       
        let pattern1 = "(\\d+(?:\\.\\d+)?)\\s*(\(unitsPattern))\\s+(?:of\\s+)?([\\p{L}0-9][\\p{L}0-9'-]*)"
        
        if let regex = cachedRegex(pattern1) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let qty = nsString.substring(with: match.range(at: 1))
                let unitRaw = nsString.substring(with: match.range(at: 2)).lowercased()
                let firstWord = nsString.substring(with: match.range(at: 3)).lowercased()
                
                guard isValidItem(firstWord, excludeNames: excludeNames) else { continue }
                
                // Expand: scan forward for multi-word item name (up to 2 more words)
                let afterMatch = match.range(at: 3).location + match.range(at: 3).length
                let item = expandItemName(firstWord, in: text, startingAfter: afterMatch, excludeNames: excludeNames)
                
                let unit = normalizeUnit(unitRaw)
                let price = findPriceForItem(item: item, in: text, globalPrices: prices)
                results.append((name: item, quantity: qty, unit: unit, price: price, costPrice: nil))
                consumedRanges.append(match.range)
            }
        }
        
        // Pattern 2: Item + Qty + Unit (Hindi style: "aloo 4 kilo")
        
        let pattern2 = "([\\p{L}0-9][\\p{L}0-9'-]*)\\s+(\\d+(?:\\.\\d+)?)\\s*(\(unitsPattern))"
        
        if let regex = cachedRegex(pattern2) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                // Skip if this match's qty+unit range overlaps with a Pattern 1 match
                let qtyUnitRange = NSUnionRange(match.range(at: 2), match.range(at: 3))
                let isConsumed = consumedRanges.contains { NSIntersectionRange($0, qtyUnitRange).length > 0 }
                if isConsumed { continue }
                
                let firstWord = nsString.substring(with: match.range(at: 1)).lowercased()
                let qty = nsString.substring(with: match.range(at: 2))
                let unitRaw = nsString.substring(with: match.range(at: 3)).lowercased()
                
                guard isValidItem(firstWord, excludeNames: excludeNames) else { continue }
                guard !unitSet.contains(firstWord) else { continue }
                
                // Scan backward for multi-word item (e.g. "tomato sauce 2 kg")
                let item = expandItemNameBackward(firstWord, in: text, endingBefore: match.range(at: 1).location, excludeNames: excludeNames)
                
                let unit = normalizeUnit(unitRaw)
                let price = findPriceForItem(item: item, in: text, globalPrices: prices)
                results.append((name: item, quantity: qty, unit: unit, price: price, costPrice: nil))
                consumedRanges.append(match.range)
            }
        }
        
        return results
    }
    
     func expandItemName(_ firstWord: String, in text: String, startingAfter pos: Int, excludeNames: [String]) -> String {
        let nsString = text as NSString
        var name = firstWord
        var currentPos = pos
        var wordsAdded = 0
        
        while wordsAdded < 2 && currentPos < nsString.length {
            while currentPos < nsString.length && nsString.character(at: currentPos) == 32 { currentPos += 1 }
            if currentPos >= nsString.length { break }
            

            var wordEnd = currentPos
            while wordEnd < nsString.length {
                let ch = nsString.character(at: wordEnd)
                if ch == 32 || ch == 44 { break } // space or comma
                wordEnd += 1
            }
            if wordEnd == currentPos { break }
            
            let nextWord = nsString.substring(with: NSRange(location: currentPos, length: wordEnd - currentPos)).lowercased()
            
            // Stop if it's a digit (next item's qty), unit, or invalid
            if nextWord.first?.isNumber == true { break }
            if unitSet.contains(nextWord) { break }
            if !isValidItem(nextWord, excludeNames: excludeNames) { break }
            
            name += " " + nextWord
            currentPos = wordEnd
            wordsAdded += 1
        }
        return name
    }
    
     func expandItemNameBackward(_ lastWord: String, in text: String, endingBefore pos: Int, excludeNames: [String]) -> String {
        let nsString = text as NSString
        var name = lastWord
        var currentPos = pos
        var wordsAdded = 0
        
        while wordsAdded < 2 && currentPos > 0 {
            currentPos -= 1
            while currentPos > 0 && nsString.character(at: currentPos) == 32 { currentPos -= 1 }
            if currentPos <= 0 { break }
            
            // Read previous word backward
            var wordStart = currentPos
            while wordStart > 0 {
                let ch = nsString.character(at: wordStart - 1)
                if ch == 32 || ch == 44 { break }
                wordStart -= 1
            }
            
            let prevWord = nsString.substring(with: NSRange(location: wordStart, length: currentPos - wordStart + 1)).lowercased()
            
            // Stop if digit, unit, or invalid
            if prevWord.first?.isNumber == true { break }
            if unitSet.contains(prevWord) { break }
            if !isValidItem(prevWord, excludeNames: excludeNames) { break }
            
            name = prevWord + " " + name
            currentPos = wordStart
            wordsAdded += 1
        }
        return name
    }
    
    // MARK: - No-Unit Product Extraction (Performance-optimized)
   
     func extractProductsWithoutUnit(from text: String, prices: [String], excludeNames: [String] = []) -> [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] {
        var results: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = []
        
        // Pattern A: Qty + Item (no unit) — "4 potatoes", "3 parasitamol", "3 5star"
    
        let patternA = "(\\d+)\\s+([\\p{L}0-9][\\p{L}0-9'-]*)"
        
        if let regex = try? NSRegularExpression(pattern: patternA, options: .caseInsensitive) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let qty = nsString.substring(with: match.range(at: 1))
                let firstWord = nsString.substring(with: match.range(at: 2)).lowercased()
                
                
                guard !unitSet.contains(firstWord) else { continue }
                guard isValidItem(firstWord, excludeNames: excludeNames) else { continue }
  
                let afterMatch = match.range(at: 2).location + match.range(at: 2).length
                let item = expandItemName(firstWord, in: text, startingAfter: afterMatch, excludeNames: excludeNames)
                
                if !excludeNames.contains(where: { $0 == item || item.contains($0) || $0.contains(item) }) &&
                   !results.contains(where: { $0.name == item }) {
                    let price = findPriceForItem(item: item, in: text, globalPrices: prices)
                    results.append((name: item, quantity: qty, unit: "pcs", price: price, costPrice: nil))
                }
            }
        }
        
        // Pattern B: Item + Qty (no unit) — "maggi 2", "soap 5", "5star 3"
       
        let patternB = "([\\p{L}0-9][\\p{L}0-9'-]*)\\s+(\\d+)(?!\\s*\\d)"
        
        if let regex = try? NSRegularExpression(pattern: patternB, options: .caseInsensitive) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let firstWord = nsString.substring(with: match.range(at: 1)).lowercased()
                let qty = nsString.substring(with: match.range(at: 2))
                
                // Check the word AFTER qty isn't a unit (that would be Pattern 2 from extractProducts)
                let afterQty = match.range(at: 2).location + match.range(at: 2).length
                if afterQty < nsString.length {
                    let remaining = nsString.substring(from: afterQty).trimmingCharacters(in: .whitespaces)
                    let nextWord = remaining.components(separatedBy: .whitespaces).first?.lowercased() ?? ""
                    if unitSet.contains(nextWord) { continue }  // This is Qty+Unit pattern, skip
                }
                
                guard !unitSet.contains(firstWord) else { continue }
                guard isValidItem(firstWord, excludeNames: excludeNames) else { continue }
                
                let item = expandItemNameBackward(firstWord, in: text, endingBefore: match.range(at: 1).location, excludeNames: excludeNames)
                
                if !excludeNames.contains(where: { $0 == item || item.contains($0) || $0.contains(item) }) &&
                   !results.contains(where: { $0.name == item }) {
                    let price = findPriceForItem(item: item, in: text, globalPrices: prices)
                    results.append((name: item, quantity: qty, unit: "pcs", price: price, costPrice: nil))
                }
            }
        }
        
        return results
    }
    
     func extractProductsFallback(from text: String, prices: [String], excludeNames: [String] = []) -> [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] {
        var results: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = []
        
        // Pattern 1: Value-first - "₹300 worth (of) ITEM"
        let valueFirstPattern1 = "₹?\\s*\\d+(?:\\.\\d+)?\\s+worth\\s+(?:of\\s+)?([a-z]+)"
        if let regex = try? NSRegularExpression(pattern: valueFirstPattern1, options: .caseInsensitive) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let item = nsString.substring(with: match.range(at: 1)).lowercased()
                
                if isValidItem(item, excludeNames: excludeNames) {
                    let price = prices.first
                   
                    results.append((name: item, quantity: "1", unit: nil, price: price, costPrice: nil))
                }
            }
        }
        
        
        if results.isEmpty {
            let valueFirstPattern2 = "(?:sold\\s+)?₹\\s*\\d+(?:\\.\\d+)?\\s+(?:per\\s+)?(?:piece\\s+)?(?:of\\s+)?([a-z]+)"
            if let regex = try? NSRegularExpression(pattern: valueFirstPattern2, options: .caseInsensitive) {
                let nsString = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
                
                for match in matches {
                    let item = nsString.substring(with: match.range(at: 1)).lowercased()
                    
                    if isValidItem(item, excludeNames: excludeNames) {
                        let price = prices.first
                        results.append((name: item, quantity: "1", unit: nil, price: price, costPrice: nil))
                    }
                }
            }
        }
        
        // Pattern 3: Just Qty + Item (no unit specified)
        if results.isEmpty {
            let pattern = "(\\d+)\\s+([a-z][a-z'-]*)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsString = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
                
                for match in matches {
                    let qty = nsString.substring(with: match.range(at: 1))
                    let firstWord = nsString.substring(with: match.range(at: 2)).lowercased()
                    
                    guard !unitSet.contains(firstWord) else { continue }
                    guard isValidItem(firstWord, excludeNames: excludeNames) else { continue }
                    
                    let afterMatch = match.range(at: 2).location + match.range(at: 2).length
                    let item = expandItemName(firstWord, in: text, startingAfter: afterMatch, excludeNames: excludeNames)
                    let price = prices.first
                    results.append((name: item, quantity: qty, unit: "pcs", price: price, costPrice: nil))
                }
            }
        }
        
        // Pattern 4: Item + Qty
        if results.isEmpty {
             let pattern = "([\\p{L}][\\p{L}'-]*)\\s+(\\d+)"
             if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                 let nsString = text as NSString
                 let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
                 
                 for match in matches {
                     let firstWord = nsString.substring(with: match.range(at: 1)).lowercased()
                     let qty = nsString.substring(with: match.range(at: 2))
                     
                     guard !unitSet.contains(firstWord) else { continue }
                     guard isValidItem(firstWord, excludeNames: excludeNames) else { continue }
                     
                     let item = expandItemNameBackward(firstWord, in: text, endingBefore: match.range(at: 1).location, excludeNames: excludeNames)
                     if !results.contains(where: { $0.name == item }) {
                         let price = prices.first
                         results.append((name: item, quantity: qty, unit: "pcs", price: price, costPrice: nil))
                     }
                 }
             }
        }
        
        return results
    }
    
     func extractVariantProducts(from text: String, prices: [String], excludeNames: [String] = []) -> [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] {
        var results: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = []
        
        let unitsPattern = allUnits.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let countUnits = "pcs|pc|piece|pieces|nos|pack|packs|packet|packets|box|boxes|bottle|bottles"
        
        // Pattern A: [Item] [Measure] [Count]
        
        let patternA = "([\\p{L}0-9][\\p{L}0-9'-]*)\\s+(\\d+(?:\\.\\d+)?)\\s*(\(unitsPattern))\\s+(\\d+)\\s*(?:(\(countUnits)))?"
        
        if let regex = try? NSRegularExpression(pattern: patternA, options: .caseInsensitive) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let itemBase = nsString.substring(with: match.range(at: 1)).lowercased()
                let measureQty = nsString.substring(with: match.range(at: 2))
                let measureUnit = normalizeUnit(nsString.substring(with: match.range(at: 3)).lowercased())
                let countQty = nsString.substring(with: match.range(at: 4))
                
                // Count unit is optional in capture group 5
                var countUnit = "pcs"
                if match.numberOfRanges > 5 && match.range(at: 5).location != NSNotFound {
                     countUnit = normalizeUnit(nsString.substring(with: match.range(at: 5)).lowercased())
                }
                
                if isValidItem(itemBase, excludeNames: excludeNames) {
                    let fullName = "\(itemBase) \(measureQty)\(measureUnit)"
                    let price = findPriceForItem(item: itemBase, in: text, globalPrices: prices)
                    results.append((name: fullName, quantity: countQty, unit: countUnit, price: price, costPrice: nil))
                }
            }
        }
        
      
        // Pattern B: [Count] [CountUnit] [Item] [Measure]
        let patternB = "(\\d+)\\s*(?:(\(countUnits)))?\\s+([\\p{L}0-9][\\p{L}0-9'-]*)\\s+(\\d+(?:\\.\\d+)?)\\s*(\(unitsPattern))"
        
        if let regex = try? NSRegularExpression(pattern: patternB, options: .caseInsensitive) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let countQty = nsString.substring(with: match.range(at: 1))
                
                // Count unit is optional in capture group 2
                var countUnit = "pcs"
                if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound {
                     countUnit = normalizeUnit(nsString.substring(with: match.range(at: 2)).lowercased())
                }
                
                let itemBase = nsString.substring(with: match.range(at: 3)).lowercased()
                let measureQty = nsString.substring(with: match.range(at: 4))
                let measureUnit = normalizeUnit(nsString.substring(with: match.range(at: 5)).lowercased())
                
                if isValidItem(itemBase, excludeNames: excludeNames) {
                    let fullName = "\(itemBase) \(measureQty)\(measureUnit)"
                    if !results.contains(where: { $0.name == fullName }) {
                        let price = findPriceForItem(item: itemBase, in: text, globalPrices: prices)
                        results.append((name: fullName, quantity: countQty, unit: countUnit, price: price, costPrice: nil))
                    }
                }
            }
        }
        
        return results
    }

    // MARK: - Helpers
    
     func matchGroup(pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsString = text as NSString
        if let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsString.length)) {
            if result.numberOfRanges > group {
                let range = result.range(at: group)
                if range.location != NSNotFound {
                    return nsString.substring(with: range)
                }
            }
        }
        return nil
    }
    
    // Cached invalid words set (built once)
     lazy var invalidWords: Set<String> = Set([
        "sold", "to", "at", "the", "rate", "rupees", "rs", "for", "and", "or",
        "aur", "price", "total", "add", "mr", "mrs", "ms", "ko", "ka", "ki", "ke",
        "of", "liye", "naam", "bill", "wala", "wali", "kul", "bhav",
        "per", "give", "gave", "dena", "dedo", "diya", "lena", "lelo", "liya",
        "customer", "buyer", "client", "sir", "madam", "ji",
        "rupiya", "paisa", "amount", "cost", "value",
        "worth", "kgs", "each", "from", "with", "that", "this", "was", "were",
        "piece", "pieces", "thing", "things", "stuff", "item", "items",
        "mein", "hai", "tha", "thi", "hain", "ho", "gaya", "gaye", "gayi",
        "good", "bad", "yes", "no", "ok", "okay", "is", "are", "his", "her",
        "have", "taken", "i", "thank", "you", "me", "we", "my", "our",
        "been", "got", "put", "also", "some", "then", "than", "just",
        "razors", "razor",
        "will", "can", "may", "should", "would", "could",
        "not", "but", "if", "so", "up", "out", "on", "off",
        "do", "did", "does", "done", "has", "had", "be", "am",
        "please", "bhai", "yaar", "bhaiya", "uncle", "aunty",
    ])
    
    func isValidItem(_ word: String, excludeNames: [String] = []) -> Bool {
        let word = word.lowercased()
        
       
        if word == "5star" || word == "7up" { return true }
        
     
        if word.count < 2 { return false }
        
        if excludeNames.contains(where: { word.contains($0) || $0.contains(word) }) {
            return false
        }
        
        // Check validity using cached sets
        let isUnit = unitSet.contains(word)
        let isInvalid = invalidWords.contains(word)
        let isNumberWord = hindiNumbers[word] != nil || englishNumbers[word] != nil
        let isKnownItem = commonItems.contains(word)
        
        // Accept if it's a known item
        if isKnownItem { return true }
        
        // Basic validation: letters only, min length 3, not a unit/invalid/number
        let isLettersOnly = word.allSatisfy { $0.isLetter || $0 == "'" || $0 == "-" }
        return isLettersOnly && word.count >= 3 && !isUnit && !isInvalid && !isNumberWord
    }
    
     func normalizeUnit(_ unit: String) -> String {
        return unitMappings[unit.lowercased()] ?? unit.lowercased()
    }
    
     func findPriceForItem(item: String, in text: String, globalPrices: [String]) -> String? {
        guard !globalPrices.isEmpty else { return nil }
        if globalPrices.count == 1 { return globalPrices[0] }
        
        let lowerText = text.lowercased()
        let lowerItem = item.lowercased()
        
        guard let itemRange = lowerText.range(of: lowerItem) else { return globalPrices.first }
        
        let textAfterItem = lowerText[itemRange.upperBound...]
        
        var bestPrice: String? = nil
        var bestDistance = Int.max
        
        for price in globalPrices {
            if let priceRange = textAfterItem.range(of: price) {
                let distance = textAfterItem.distance(from: textAfterItem.startIndex, to: priceRange.lowerBound)
                if distance < bestDistance {
                    bestDistance = distance
                    bestPrice = price
                }
            }
        }
        
        return bestPrice ?? globalPrices.first
    }
}
