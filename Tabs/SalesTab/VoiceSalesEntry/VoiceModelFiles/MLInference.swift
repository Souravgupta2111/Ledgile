
import CoreML
import NaturalLanguage

// Entity types for NER — extended for RetailBetter model
enum EntityType: String, CaseIterable {
    case quantity = "QTY"
    case item = "ITEM"
    case customer = "CUST"
    case supplier = "SUPPLIER"
    case action = "ACTION"
    case price = "PRICE"
    case sellingPrice = "SELLING_PRICE"
    case costPrice = "COST_PRICE"
    case unit = "UNIT"
    case discount = "DISCOUNT"
    case expiry = "EXPIRY"
    case reference = "REF"
    case negation = "NEG"
    case other = "O"
}

// Parsed entity with text and type
struct ParsedEntity {
    let text: String
    let type: EntityType
    let isBeginning: Bool
}

// Result of parsing containing all extracted entities
struct ParsedResult {
    let entities: [ParsedEntity]
    let products: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)]
    let customerName: String?
    let isNegation: Bool
    let isReference: Bool
    let productItemIDs: [UUID]?
    let productConfidences: [String]?
    
    var formattedText: String {
        var result = ""
        for entity in entities {
            result += entity.text + " "
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

final class MLInference {
    
    static let shared = MLInference()
    
     var nlModel: NLModel?
     let tagger = NLTagger(tagSchemes: [.nameType])
     let bioLabelMap: [String: (type: EntityType, isBeginning: Bool)] = [
        "O": (.other, true),
        "B-ITEM": (.item, true), "I-ITEM": (.item, false),
        "B-QTY": (.quantity, true), "I-QTY": (.quantity, false),
        "B-UNIT": (.unit, true), "I-UNIT": (.unit, false),
        "B-PRICE": (.price, true), "I-PRICE": (.price, false),
        "B-SELLING_PRICE": (.sellingPrice, true), "I-SELLING_PRICE": (.sellingPrice, false),
        "B-COST_PRICE": (.costPrice, true), "I-COST_PRICE": (.costPrice, false),
        // Model outputs B-CUST/I-CUST — match both variants
        "B-CUST": (.customer, true), "I-CUST": (.customer, false),
        "B-CUSTOMER": (.customer, true), "I-CUSTOMER": (.customer, false),
        "B-SUPPLIER": (.supplier, true), "I-SUPPLIER": (.supplier, false),
        "B-DISCOUNT": (.discount, true), "I-DISCOUNT": (.discount, false),
        "B-EXPIRY": (.expiry, true), "I-EXPIRY": (.expiry, false),
        "B-NEG": (.negation, true), "I-NEG": (.negation, false),
        "B-REF": (.reference, true), "I-REF": (.reference, false),
        "B-ACTION": (.action, true), "I-ACTION": (.action, false),
    ]
    
    init() {
        if let modelURL = Bundle.main.url(forResource: "RetailBetter", withExtension: "mlmodelc") {
            do {
                self.nlModel = try NLModel(contentsOf: modelURL)
            } catch {
                loadModelFallback()
            }
        } else {
            loadModelFallback()
        }
    }
    
     func loadModelFallback() {
        guard let modelURL = Bundle.main.url(forResource: "RetailBetter", withExtension: "mlmodel") else {
            return
        }
        do {
            let compiledURL = try MLModel.compileModel(at: modelURL)
            self.nlModel = try NLModel(contentsOf: compiledURL)
        } catch {
        }
    }
    
    func run(text: String) -> ParsedResult {
        let pipelineStart = CFAbsoluteTimeGetCurrent()
        
        let regexStart = CFAbsoluteTimeGetCurrent()
        let regexResult = RegexParser.shared.parse(text: text)
        
        var mlResult: ParsedResult? = nil
        
        if let model = nlModel {
            let mlStart = CFAbsoluteTimeGetCurrent()
            mlResult = runNLModel(model: model, text: text)
        } else {
        }
        
        var finalProducts: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = regexResult.products
        var finalCustomer = regexResult.customerName
        
        if let mlProducts = mlResult?.products {
            for mlP in mlProducts {
                var isDuplicate = false
                
                for i in 0..<finalProducts.count {
                    let existing = finalProducts[i]
                    let existingLower = existing.name.lowercased()
                    let mlLower = mlP.name.lowercased()
                    
                    if existingLower.contains(mlLower) || mlLower.contains(existingLower) {
                        // ML Model wins for price because Regex naively applies the first found price to all
                        if let mlPrice = mlP.price { finalProducts[i].price = mlPrice }
                        if let mlCostPrice = mlP.costPrice { finalProducts[i].costPrice = mlCostPrice }
                        if existing.unit == nil { finalProducts[i].unit = mlP.unit }
                        
                        // If ML detected a longer (more specific) name, use it
                        if mlLower.count > existingLower.count {
                            finalProducts[i].name = mlP.name
                        }
                        
                        isDuplicate = true
                        break
                    }
                }
                
                let isValid = RegexParser.shared.isValidItem(mlP.name)
                
                if !isDuplicate && isValid {
                    finalProducts.append(mlP)
                }
            }
        }
        
        if finalCustomer == nil && mlResult?.customerName != nil {
            finalCustomer = mlResult!.customerName
        }
        
        
        return ParsedResult(
            entities: mlResult?.entities ?? [],
            products: finalProducts,
            customerName: finalCustomer,
            isNegation: mlResult?.isNegation ?? false,
            isReference: mlResult?.isReference ?? false,
            productItemIDs: nil,
            productConfidences: nil
        )
    }
    
    // MARK: - NLModel Word Tagger Inference
    
     func runNLModel(model: NLModel, text: String) -> ParsedResult {
        // NLTagger with custom NLModel
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.setModels([model], forTagScheme: .nameType)
        
        var entities: [ParsedEntity] = []
        var products: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = []
        
        var currentItem = ""
        var currentQty = ""
        var currentUnit: String? = nil
        var currentPrice: String? = nil
        var currentCostPrice: String? = nil
        var customerName: String? = nil
        var hasNegation = false
        var hasReference = false
        
        // Enumerate tags word by word
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            let word = String(text[tokenRange])
            let label = tag?.rawValue ?? "O"
            
            guard let labelInfo = bioLabelMap[label] else {
                // Unknown label — treat as O
                return true
            }
            
            let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanWord.isEmpty else { return true }
            
            // Conflict detection: if B-tag for an already-set attribute, save current item
            if labelInfo.isBeginning && labelInfo.type != .other {
                var shouldSave = false
                switch labelInfo.type {
                case .quantity: if !currentQty.isEmpty { shouldSave = true }
                case .unit: if currentUnit != nil { shouldSave = true }
                case .price: if currentPrice != nil { shouldSave = true }
                default: break
                }
                
                if shouldSave && !currentItem.isEmpty {
                    products.append((name: currentItem,
                                     quantity: currentQty.isEmpty ? "1" : currentQty,
                                     unit: currentUnit, price: currentPrice, costPrice: currentCostPrice))
                    currentItem = ""; currentQty = ""; currentUnit = nil; currentPrice = nil; currentCostPrice = nil
                }
            }
            
            // Accumulate entities
            switch labelInfo.type {
            case .item:
                if labelInfo.isBeginning {
                    if !currentItem.isEmpty {
                        products.append((name: currentItem,
                                         quantity: currentQty.isEmpty ? "1" : currentQty,
                                         unit: currentUnit, price: currentPrice, costPrice: currentCostPrice))
                        currentQty = ""; currentUnit = nil; currentPrice = nil; currentCostPrice = nil
                    }
                    currentItem = cleanWord
                } else {
                    currentItem += (currentItem.isEmpty ? "" : " ") + cleanWord
                }
                
            case .quantity:
                currentQty = labelInfo.isBeginning ? cleanWord : currentQty + " " + cleanWord
                
            case .unit:
                currentUnit = labelInfo.isBeginning ? cleanWord : (currentUnit ?? "") + " " + cleanWord
                
            case .price, .sellingPrice:
                let priceVal = cleanWord.replacingOccurrences(of: "₹", with: "")
                if labelInfo.isBeginning {
                    currentPrice = priceVal
                } else {
                    currentPrice = (currentPrice ?? "") + priceVal
                }
                
            case .customer:
                if labelInfo.isBeginning {
                    customerName = cleanWord
                } else {
                    customerName = (customerName ?? "") + " " + cleanWord
                }
                
            case .supplier:
                // For now supplier is informational; store in customer slot if no customer
                if customerName == nil {
                    customerName = labelInfo.isBeginning ? cleanWord : (customerName ?? "") + " " + cleanWord
                }
                
            case .negation: hasNegation = true
            case .reference: hasReference = true
            case .costPrice:
                let cpVal = cleanWord.replacingOccurrences(of: "₹", with: "")
                if labelInfo.isBeginning {
                    currentCostPrice = cpVal
                } else {
                    currentCostPrice = (currentCostPrice ?? "") + cpVal
                }
            case .discount, .expiry, .action, .other: break
            }
            
            if labelInfo.type != .other {
                entities.append(ParsedEntity(text: cleanWord, type: labelInfo.type, isBeginning: labelInfo.isBeginning))
            }
            
            return true
        }
        
        if !currentItem.isEmpty {
            products.append((name: currentItem,
                             quantity: currentQty.isEmpty ? "1" : currentQty,
                             unit: currentUnit, price: currentPrice, costPrice: currentCostPrice))
        }
        
        return ParsedResult(
            entities: entities,
            products: products,
            customerName: customerName,
            isNegation: hasNegation,
            isReference: hasReference,
            productItemIDs: nil,
            productConfidences: nil
        )
    }
}
