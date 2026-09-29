import Foundation

enum Money {

    static func amount(_ value: Double, grouped: Bool = true) -> String {
        symbol + decimal(value, fractionDigits: 2, grouped: grouped)
    }

    static func rounded(_ value: Double, grouped: Bool = true) -> String {
        symbol + decimal(value, fractionDigits: 0, grouped: grouped)
    }

    static func compact(_ value: Double, grouped: Bool = true) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? rounded(value, grouped: grouped)
            : amount(value, grouped: grouped)
    }

    static func signed(_ value: Double, grouped: Bool = true) -> String {
        (value < 0 ? "-" : "+") + compact(abs(value), grouped: grouped)
    }

    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    static func line(quantity: Double, rate: Double) -> Double {
        round2(quantity * rate)
    }

    static let symbol = "₹"

    private static let formatterCache = FormatterCache()

    private static func decimal(_ value: Double, fractionDigits: Int, grouped: Bool) -> String {
        let formatter = formatterCache.formatter(fractionDigits: fractionDigits, grouped: grouped)
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.\\(fractionDigits)f", value)
    }

    private final class FormatterCache: @unchecked Sendable {
        private let lock = NSLock()
        private var cache: [String: NumberFormatter] = [:]

        func formatter(fractionDigits: Int, grouped: Bool) -> NumberFormatter {
            let key = "\(fractionDigits)-\(grouped)"
            lock.lock()
            defer { lock.unlock() }
            if let existing = cache[key] { return existing }

            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = fractionDigits
            formatter.maximumFractionDigits = fractionDigits
            formatter.usesGroupingSeparator = grouped

            formatter.locale = Locale(identifier: "en_IN")
            cache[key] = formatter
            return formatter
        }
    }
}

enum Quantity {

    static func plain(_ value: Double) -> String {
        value.cleanString
    }

    static func withUnit(_ value: Double, _ unit: String) -> String {
        unit.isEmpty ? value.cleanString : "\(value.cleanString) \(unit)"
    }

    static func timesRate(_ value: Double, rate: Double) -> String {
        "\(value.cleanString) × \(Money.amount(rate))"
    }
}
