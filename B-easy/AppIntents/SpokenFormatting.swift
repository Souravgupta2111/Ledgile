import Foundation

nonisolated enum SpokenFormatting {
    static var locale: Locale {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale(identifier: code == "hi" ? "hi_IN" : "en_IN")
    }

    static var isHindi: Bool {
        locale.language.languageCode?.identifier == "hi"
    }

    static func amount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func money(_ value: Double) -> String {
        "₹\(amount(value))"
    }

    static func unit(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isHindi else { return raw }
        let units: [String: String] = [
            "kg": "किलो",
            "kgs": "किलो",
            "kilogram": "किलो",
            "kilograms": "किलो",
            "g": "ग्राम",
            "gm": "ग्राम",
            "gram": "ग्राम",
            "grams": "ग्राम",
            "l": "लीटर",
            "lt": "लीटर",
            "litre": "लीटर",
            "liter": "लीटर",
            "litres": "लीटर",
            "liters": "लीटर",
            "ml": "मिलीलीटर",
            "packet": "पैकेट",
            "packets": "पैकेट",
            "pcs": "पीस",
            "pc": "पीस",
            "piece": "पीस",
            "pieces": "पीस",
            "dozen": "दर्जन",
            "box": "बॉक्स",
            "boxes": "बॉक्स",
            "bottle": "बोतल",
            "bottles": "बोतल",
            "bag": "बैग",
            "bags": "बैग"
        ]
        return units[key] ?? raw
    }
}
