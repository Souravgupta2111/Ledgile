// NumberToWords.swift
// Convert numeric amounts to Indian English words for invoices

import Foundation

enum NumberToWords {

    private static let ones = [
        "", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
        "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen",
        "Seventeen", "Eighteen", "Nineteen"
    ]

    private static let tens = [
        "", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"
    ]

    /// Convert a rupee amount to Indian English words
    /// e.g. 380.50 → "Three Hundred Eighty Rupees and Fifty Paise Only"
    /// e.g. 380.00 → "Three Hundred Eighty Rupees Only"
    /// e.g. 0.00   → "Zero Rupees Only"
    static func convert(_ amount: Double) -> String {
        let rounded = (amount * 100).rounded() / 100
        let rupees = Int(rounded)
        let paise = Int((rounded - Double(rupees)) * 100 + 0.5)

        if rupees == 0 && paise == 0 {
            return "Zero Rupees Only"
        }

        var result = ""

        if rupees > 0 {
            result = indianNumberToWords(rupees) + " Rupees"
        }

        if paise > 0 {
            if !result.isEmpty {
                result += " and "
            }
            result += indianNumberToWords(paise) + " Paise"
        }

        result += " Only"
        return result
    }

    /// Convert an integer to Indian English words using Indian numbering system
    /// (Lakhs, Crores instead of Millions, Billions)
    private static func indianNumberToWords(_ n: Int) -> String {
        guard n > 0 else { return "Zero" }
        guard n < 1_00_00_00_000 else { return "\(n)" } // 100 crore limit

        var number = n
        var parts: [String] = []

        // Extract Crores (1,00,00,000)
        let crores = number / 1_00_00_000
        if crores > 0 {
            parts.append(twoDigitToWords(crores) + " Crore")
            number %= 1_00_00_000
        }

        // Extract Lakhs (1,00,000)
        let lakhs = number / 1_00_000
        if lakhs > 0 {
            parts.append(twoDigitToWords(lakhs) + " Lakh")
            number %= 1_00_000
        }

        // Extract Thousands (1,000)
        let thousands = number / 1_000
        if thousands > 0 {
            parts.append(twoDigitToWords(thousands) + " Thousand")
            number %= 1_000
        }

        // Extract Hundreds
        let hundreds = number / 100
        if hundreds > 0 {
            parts.append(ones[hundreds] + " Hundred")
            number %= 100
        }

        // Remaining two digits
        if number > 0 {
            if !parts.isEmpty {
                parts.append("and")
            }
            parts.append(twoDigitToWords(number))
        }

        return parts.joined(separator: " ")
    }

    private static func twoDigitToWords(_ n: Int) -> String {
        if n < 20 {
            return ones[n]
        }
        let tenPart = tens[n / 10]
        let onePart = ones[n % 10]
        return onePart.isEmpty ? tenPart : "\(tenPart) \(onePart)"
    }
}
