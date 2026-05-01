import Foundation

final class UnitConversionService {
    
    static let shared = UnitConversionService()
    
    private init() {}
    
    private let massGramUnits = ["g", "gm", "gram", "grams", "Gram"]
    private let massKiloUnits = ["kg", "kilo", "kilogram", "kilograms", "Kilogram"]
    
    private let volMilliUnits = ["ml", "milliliter", "milliliters", "millilitre"]
    private let volLiterUnits = ["l", "ltr", "liter", "liters", "litre", "litres"]

    private let countPieceUnits = ["pcs", "pc", "piece", "pieces"]
    private let countDozenUnits = ["dozen", "doz", "dzn"]
    private let countPairUnits  = ["pair", "pairs"]

    private let massLbUnits = ["lb", "lbs", "pound", "pounds"]
    private let massOzUnits = ["oz", "ounce", "ounces"]

    private let lengthCmUnits   = ["cm", "centimeter", "centimeters"]
    private let lengthMeterUnits = ["meter", "meters", "metre", "mtr"]
    private let lengthInchUnits = ["inch", "inches", "in"]
    private let lengthFootUnits = ["foot", "feet", "ft"]
    private let lengthYardUnits = ["yard", "yards", "yd"]
    
    static let standardUnits: [String] = [
        "pcs",
        "dozen",
        "g",
        "kg",
        "mg",
        "ml",
        "l",
        "lb",
        "oz",
        "bottle",
        "can",
        "pair",
        "pack",
        "box",
        "bag",
        "meter",
        "cm",
        "inch",
        "foot",
        "yard",
        "sq ft",
        "sq m"
    ]
    
    static func displayName(for unit: String) -> String {
        let u = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch u {
        case "pcs", "piece", "pieces": return "pcs"
        case "g", "gm", "gram", "grams": return "g"
        case "kg", "kilo", "kilogram", "kilograms": return "kg"
        case "mg", "milligram", "milligrams": return "mg"
        case "ml", "milliliter", "milliliters", "millilitre": return "ml"
        case "l", "liter", "liters", "litre", "litres": return "l"
        case "lb", "pound", "pounds": return "lb"
        case "oz", "ounce", "ounces": return "oz"
        case "dozen": return "dozen"
        case "bottle": return "bottle"
        case "can": return "can"
        case "pair": return "pair"
        case "pack": return "pack"
        case "box": return "box"
        case "bag": return "bag"
        case "meter", "meters", "metre": return "meter"
        case "cm", "centimeter", "centimeters": return "cm"
        case "inch", "inches": return "inch"
        case "foot", "feet": return "foot"
        case "yard", "yards": return "yard"
        case "sq ft", "square foot", "square feet": return "sq ft"
        case "sq m", "square meter", "square meters": return "sq m"
        default: return u
        }
    }
    
    struct ConversionResult {
        let quantity: Int
        let unit: String
        let proratedPrice: Double
    }
    
    func normalizeUnit(_ unit: String) -> String {
        let u = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if massGramUnits.contains(u) { return "g" }
        if massKiloUnits.contains(u) { return "kg" }
        if ["mg", "milligram", "milligrams"].contains(u) { return "mg" }
        if massLbUnits.contains(u) { return "lb" }
        if massOzUnits.contains(u) { return "oz" }
        if volMilliUnits.contains(u) { return "ml" }
        if volLiterUnits.contains(u) { return "l" }
        if countPieceUnits.contains(u) { return "pcs" }
        if countDozenUnits.contains(u) { return "dozen" }
        if countPairUnits.contains(u) { return "pair" }
        if lengthCmUnits.contains(u) { return "cm" }
        if lengthMeterUnits.contains(u) { return "meter" }
        if lengthInchUnits.contains(u) { return "inch" }
        if lengthFootUnits.contains(u) { return "foot" }
        if lengthYardUnits.contains(u) { return "yard" }
        if ["sq ft", "square foot", "square feet", "sqft"].contains(u) { return "sq ft" }
        if ["sq m", "square meter", "square meters", "sqm"].contains(u) { return "sq m" }
        return u
    }
    
    func convertPrice(from fromUnit: String, to toUnit: String, price: Double) -> Double? {
        let f = normalizeUnit(fromUnit)
        let t = normalizeUnit(toUnit)
        
        if f == t { return price }
        
        guard let fromBase = toBaseUnit(f), let toBase = toBaseUnit(t) else { return nil }
        guard fromBase.family == toBase.family else { return nil }
        
        return price * (toBase.factor / fromBase.factor)
    }
    
    
    private enum UnitFamily: String {
        case mass, volume, count, length, area
    }
    
    private struct BaseConversion {
        let family: UnitFamily
        let factor: Double
    }
    
    private func toBaseUnit(_ unit: String) -> BaseConversion? {
        switch unit {
        case "mg":    return BaseConversion(family: .mass, factor: 0.001)
        case "g":     return BaseConversion(family: .mass, factor: 1.0)
        case "kg":    return BaseConversion(family: .mass, factor: 1000.0)
        case "lb":    return BaseConversion(family: .mass, factor: 453.592)
        case "oz":    return BaseConversion(family: .mass, factor: 28.3495)
        case "ml":    return BaseConversion(family: .volume, factor: 1.0)
        case "l":     return BaseConversion(family: .volume, factor: 1000.0)
        case "pcs":   return BaseConversion(family: .count, factor: 1.0)
        case "dozen": return BaseConversion(family: .count, factor: 12.0)
        case "pair":  return BaseConversion(family: .count, factor: 2.0)
        case "cm":    return BaseConversion(family: .length, factor: 1.0)
        case "meter": return BaseConversion(family: .length, factor: 100.0)
        case "inch":  return BaseConversion(family: .length, factor: 2.54)
        case "foot":  return BaseConversion(family: .length, factor: 30.48)
        case "yard":  return BaseConversion(family: .length, factor: 91.44)
        case "sq ft": return BaseConversion(family: .area, factor: 929.03)
        case "sq m":  return BaseConversion(family: .area, factor: 10000.0)
        default:      return nil
        }
    }
    
    func calculateProrated(
        requestedQty: Double,
        requestedUnit: String,
        inventoryPrice: Double,
        inventoryUnit: String
    ) -> ConversionResult? {
        
        let req = normalizeUnit(requestedUnit)
        let inv = normalizeUnit(inventoryUnit)
        
        if req == inv { return nil }
        
        guard let reqBase = toBaseUnit(req), let invBase = toBaseUnit(inv) else {
            return nil
        }
        guard reqBase.family == invBase.family else {
            return nil
        }
        
        let requestedInBase = requestedQty * reqBase.factor
        let multiplier = requestedInBase / invBase.factor
        
        let newPrice = inventoryPrice * multiplier
        
        let displayQty = requestedQty == requestedQty.rounded() ? "\(Int(requestedQty))" : String(format: "%.1f", requestedQty)
        let displayUnit = "\(displayQty)\(req)"
        
        return ConversionResult(
            quantity: 1,
            unit: displayUnit,
            proratedPrice: newPrice
        )
    }
}
