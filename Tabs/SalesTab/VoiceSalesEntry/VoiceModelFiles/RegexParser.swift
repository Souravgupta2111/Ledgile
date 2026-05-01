
import Foundation

class RegexParser {
    
    static let shared = RegexParser()
    
     var cachedNumberRegex: [(NSRegularExpression, String)] = []
     var _unitSet: Set<String>?
     var _cachedProductRegexes: [String: NSRegularExpression] = [:]
    
    
     let hindiNumbers: [String: String] = [
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
        
        "tees": "30", "tis": "30", "तीस": "30",
        "chalis": "40", "challis": "40", "चालीस": "40",
        "pachas": "50", "pachpan": "55", "पचास": "50",
        "saath": "60", "साठ": "60",
        "sattar": "70", "सत्तर": "70",
        "assi": "80", "अस्सी": "80",
        "nabbe": "90", "नब्बे": "90",
        "sau": "100", "सौ": "100",
        
        "aadha": "0.5", "adha": "0.5", "आधा": "0.5", "aada": "0.5", "ada": "0.5", "aadhi": "0.5", "adhi": "0.5",
        "paav": "0.25", "pav": "0.25", "pao": "0.25", "पाव": "0.25", "pau": "0.25",
        "sawa": "1.25", "sava": "1.25", "सवा": "1.25",
        "dedh": "1.5", "dhadh": "1.5", "डेढ़": "1.5", "derh": "1.5", "ded": "1.5", "dad": "1.5",
        "dhai": "2.5", "dhaai": "2.5", "ढाई": "2.5", "dai": "2.5",
        "saadhe": "0.5", "sadhe": "0.5",
        
        "darjan": "12", "darzan": "12", "दर्जन": "12",
        "hazaar": "1000", "hazar": "1000", "हज़ार": "1000"
    ]
    
     let englishNumbers: [String: String] = [
        "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
        "eleven": "11", "twelve": "12", "thirteen": "13", "fourteen": "14", "fifteen": "15",
        "sixteen": "16", "seventeen": "17", "eighteen": "18", "nineteen": "19", "twenty": "20",
        "thirty": "30", "forty": "40", "fifty": "50", "sixty": "60",
        "seventy": "70", "eighty": "80", "ninety": "90", "hundred": "100",
        "dozen": "12", "half": "0.5", "quarter": "0.25"
    ]
    
    
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

         "cashew", "cashews", "kaju", "काजू",
         "almond", "almonds", "badam", "बादाम",
         "raisin", "raisins", "kishmish", "किशमिश",
         "peanut", "peanuts", "moongfali", "मूंगफली",
         "walnut", "walnuts", "akhrot", "अखरोट",
         "pistachio", "pistachios", "pista", "पिस्ता",
         "nuts"
    ])
    
    
    func parse(text: String) -> ParsedResult {
        
        let processed = preprocessText(text)
        
        let customerName = extractCustomer(from: text)
        if let cust = customerName {
        }
        
        let prices = extractPrices(from: processed)
        
        let variantProducts = extractVariantProducts(from: processed, prices: prices, excludeNames: [customerName?.lowercased()].compactMap { $0 })
        var products = variantProducts
        
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
    
    
     func preprocessText(_ text: String) -> String {
        var result = text.lowercased()
        
        let corrections: [String: String] = [
            "penton": "pencil", "pentatonic": "pencil",
            "chalo": "char",
            "aaloo": "aloo", "alloo": "aloo",
            "piyas": "pyaaz", "piyaz": "pyaaz",
            "killo": "kilo", "keelo": "kilo",
            "rupay": "rupees", "rupaye": "rupees", "rupiyaa": "rupees",
            "of400": "of 400", "of40": "of 40", "of100": "of 100",
        ]
        
        for (wrong, correct) in corrections {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }
        
        result = result.replacingOccurrences(of: "₹", with: " ₹")
        
        
        result = result.replacingOccurrences(of: ",", with: " ")
        
        result = result.replacingOccurrences(of: "?", with: " ")
        result = result.replacingOccurrences(of: "!", with: " ")
        result = result.replacingOccurrences(
            of: "(?<!\\d)\\.(?!\\d)",
            with: " ",
            options: .regularExpression
        )
        
        let unitWords = allUnits.sorted { $0.count > $1.count }
        for unit in unitWords {
            let escapedUnit = NSRegularExpression.escapedPattern(for: unit)
            let splitPattern = "(\\d+(?:\\.\\d+)?)(\(escapedUnit))\\b"
            result = result.replacingOccurrences(
                of: splitPattern,
                with: "$1 $2",
                options: .regularExpression
            )
        }
        
        result = convertNumbersToDigits(result)
        
        
        result = result.replacingOccurrences(of: "\\b5 star\\b", with: "5star", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\bfive star\\b", with: "5star", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\b7 up\\b", with: "7up", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\bseven up\\b", with: "7up", options: .regularExpression)
        
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
    
    
     func extractCustomer(from text: String) -> String? {
        let patterns = [
            "([a-z]+(?:\\s+[a-z]+)*)\\s+ko\\b",
            "([a-z]+(?:\\s+[a-z]+)*)\\s+ke\\s+liye\\b",
            "([a-z]+(?:\\s+[a-z]+)*)\\s+ka\\s+bill\\b",
            "([a-z]+(?:\\s+[a-z]+)*)\\s+ke\\s+naam\\b",
            
            "sold\\s+to\\s+(?:mr\\.?\\s+|mrs\\.?\\s+|ms\\.?\\s+)?([a-z]+(?:\\s+[a-z]+)*)",
            "\\bto\\s+([a-z]+(?:\\s+[a-z]+)*)\\s+at\\b",
            "\\bto\\s+(?:mr\\.?\\s+)?([a-z]+(?:\\s+[a-z]+)?)(?:\\s+at|\\s*$)",
            "\\bfor\\s+(?:mr\\.?\\s+)?([a-z]+(?:\\s+[a-z]+)?)\\b",
            "customer\\s+(?:is\\s+)?(?:mr\\.?\\s+)?([a-z]+(?:\\s+[a-z]+)?)",
            "\\bmr\\.?\\s+([a-z]+(?:\\s+[a-z]+)?)\\b",
            "\\bgive\\s+(?:mr\\.?\\s+)?([a-z]+(?:\\s+[a-z]+)?)\\s+\\d",
        ]
        
        for pattern in patterns {
            if let name = matchGroup(pattern: pattern, in: text, group: 1) {
                var filtered = name.trimmingCharacters(in: .whitespaces)
                let invalidNames = Set(["the", "a", "an", "this", "that", "total", "rate", "price",
                                       "char", "ek", "do", "teen", "four", "five", "give", "sold",
                                       "kg", "kilo", "piece", "pieces"])
                let nameWords = filtered.lowercased().split(separator: " ").map { String($0) }
                let validWords = nameWords.filter { !invalidNames.contains($0) }
                
                if !validWords.isEmpty {
                    filtered = validWords.joined(separator: " ")
                    if filtered.count > 2 {
                        return filtered.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
                    }
                }
            }
        }
        return nil
    }
    
    
     func extractPrices(from text: String) -> [String] {
        var prices: [String] = []
        
        let patterns = [
            "₹\\s*(\\d+(?:\\.\\d+)?)",
            "(\\d+(?:\\.\\d+)?)\\s*(?:₹|rupees?|rs\\.?)",
            "(?:rate|bhav|bhaw)\\s+(?:of\\s+)?(\\d+(?:\\.\\d+)?)",
            "(?:total|kul)\\s+(?:of\\s+)?(\\d+(?:\\.\\d+)?)",
            "@\\s*(\\d+(?:\\.\\d+)?)",
            "(?:per|prति)\\s+(?:kg|kilo|piece)?\\s*(\\d+(?:\\.\\d+)?)",
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
        
        var consumedRanges: [NSRange] = []
        
       
        let pattern1 = "(\\d+(?:\\.\\d+)?)\\s*(\(unitsPattern))\\s+(?:of\\s+)?([\\p{L}0-9][\\p{L}0-9'-]*)"
        
        if let regex = cachedRegex(pattern1) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let qty = nsString.substring(with: match.range(at: 1))
                let unitRaw = nsString.substring(with: match.range(at: 2)).lowercased()
                let firstWord = nsString.substring(with: match.range(at: 3)).lowercased()
                
                guard isValidItem(firstWord, excludeNames: excludeNames) else { continue }
                
                let afterMatch = match.range(at: 3).location + match.range(at: 3).length
                let item = expandItemName(firstWord, in: text, startingAfter: afterMatch, excludeNames: excludeNames)
                
                let unit = normalizeUnit(unitRaw)
                let price = findPriceForItem(item: item, in: text, globalPrices: prices)
                results.append((name: item, quantity: qty, unit: unit, price: price, costPrice: nil))
                consumedRanges.append(match.range)
            }
        }
        
        
        let pattern2 = "([\\p{L}0-9][\\p{L}0-9'-]*)\\s+(\\d+(?:\\.\\d+)?)\\s*(\(unitsPattern))"
        
        if let regex = cachedRegex(pattern2) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let qtyUnitRange = NSUnionRange(match.range(at: 2), match.range(at: 3))
                let isConsumed = consumedRanges.contains { NSIntersectionRange($0, qtyUnitRange).length > 0 }
                if isConsumed { continue }
                
                let firstWord = nsString.substring(with: match.range(at: 1)).lowercased()
                let qty = nsString.substring(with: match.range(at: 2))
                let unitRaw = nsString.substring(with: match.range(at: 3)).lowercased()
                
                guard isValidItem(firstWord, excludeNames: excludeNames) else { continue }
                guard !unitSet.contains(firstWord) else { continue }
                
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
                if ch == 32 || ch == 44 { break }
                wordEnd += 1
            }
            if wordEnd == currentPos { break }
            
            let nextWord = nsString.substring(with: NSRange(location: currentPos, length: wordEnd - currentPos)).lowercased()
            
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
            
            var wordStart = currentPos
            while wordStart > 0 {
                let ch = nsString.character(at: wordStart - 1)
                if ch == 32 || ch == 44 { break }
                wordStart -= 1
            }
            
            let prevWord = nsString.substring(with: NSRange(location: wordStart, length: currentPos - wordStart + 1)).lowercased()
            
            if prevWord.first?.isNumber == true { break }
            if unitSet.contains(prevWord) { break }
            if !isValidItem(prevWord, excludeNames: excludeNames) { break }
            
            name = prevWord + " " + name
            currentPos = wordStart
            wordsAdded += 1
        }
        return name
    }
    
   
     func extractProductsWithoutUnit(from text: String, prices: [String], excludeNames: [String] = []) -> [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] {
        var results: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = []
        
    
        let patternA = "(\\d+(?:\\.\\d+)?)\\s+([\\p{L}0-9][\\p{L}0-9'-]*)"
        
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
        
       
        let patternB = "([\\p{L}0-9][\\p{L}0-9'-]*)\\s+(\\d+(?:\\.\\d+)?)(?!\\s*\\d)"
        
        if let regex = try? NSRegularExpression(pattern: patternB, options: .caseInsensitive) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let firstWord = nsString.substring(with: match.range(at: 1)).lowercased()
                let qty = nsString.substring(with: match.range(at: 2))
                
                let afterQty = match.range(at: 2).location + match.range(at: 2).length
                if afterQty < nsString.length {
                    let remaining = nsString.substring(from: afterQty).trimmingCharacters(in: .whitespaces)
                    let nextWord = remaining.components(separatedBy: .whitespaces).first?.lowercased() ?? ""
                    if unitSet.contains(nextWord) { continue }
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
        
        if results.isEmpty {
            let pattern = "(\\d+(?:\\.\\d+)?)\\s+([a-z][a-z'-]*)"
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
        
        if results.isEmpty {
             let pattern = "([\\p{L}][\\p{L}'-]*)\\s+(\\d+(?:\\.\\d+)?)"
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
        
        
        let patternA = "([\\p{L}0-9][\\p{L}0-9'-]*)\\s+(\\d+(?:\\.\\d+)?)\\s*(\(unitsPattern))\\s+(\\d+)\\s*(?:(\(countUnits)))?"
        
        if let regex = try? NSRegularExpression(pattern: patternA, options: .caseInsensitive) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let itemBase = nsString.substring(with: match.range(at: 1)).lowercased()
                let measureQty = nsString.substring(with: match.range(at: 2))
                let measureUnit = normalizeUnit(nsString.substring(with: match.range(at: 3)).lowercased())
                let countQty = nsString.substring(with: match.range(at: 4))
                
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
        
      
        let patternB = "(\\d+)\\s*(?:(\(countUnits)))?\\s+([\\p{L}0-9][\\p{L}0-9'-]*)\\s+(\\d+(?:\\.\\d+)?)\\s*(\(unitsPattern))"
        
        if let regex = try? NSRegularExpression(pattern: patternB, options: .caseInsensitive) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let countQty = nsString.substring(with: match.range(at: 1))
                
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
        
        let isUnit = unitSet.contains(word)
        let isInvalid = invalidWords.contains(word)
        let isNumberWord = hindiNumbers[word] != nil || englishNumbers[word] != nil
        let isKnownItem = commonItems.contains(word)
        
        if isKnownItem { return true }
        
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
        
        let itemMidOffset = lowerText.distance(from: lowerText.startIndex, to: itemRange.lowerBound)
            + lowerText.distance(from: itemRange.lowerBound, to: itemRange.upperBound) / 2
        
        var bestPrice: String? = nil
        var bestDistance = Int.max
        
        for price in globalPrices {
            var searchRange = lowerText.startIndex..<lowerText.endIndex
            while let priceRange = lowerText.range(of: price, range: searchRange) {
                let priceOffset = lowerText.distance(from: lowerText.startIndex, to: priceRange.lowerBound)
                let distance = abs(priceOffset - itemMidOffset)
                if distance < bestDistance {
                    bestDistance = distance
                    bestPrice = price
                }
                searchRange = priceRange.upperBound..<lowerText.endIndex
            }
        }
        
        return bestPrice ?? globalPrices.first
    }
}
