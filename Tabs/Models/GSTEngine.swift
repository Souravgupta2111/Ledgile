// GSTEngine.swift
// Core GST tax calculation engine for Ledgile

import Foundation

enum GSTEngine {

    // MARK: - Tax Calculation

    /// Calculate tax for a single item
    /// - Parameters:
    ///   - price: The price per unit (MRP or exclusive depending on `pricesIncludeGST`)
    ///   - quantity: Number of units
    ///   - gstRate: GST rate as percentage (e.g. 18.0 for 18%)
    ///   - cessRate: Additional cess rate as percentage (e.g. 12.0)
    ///   - isInterState: If true → IGST; if false → CGST+SGST
    ///   - pricesIncludeGST: If true, price is MRP (tax-inclusive), reverse calculate
    static func calculateTax(
        price: Double,
        quantity: Int,
        gstRate: Double,
        cessRate: Double = 0,
        isInterState: Bool,
        pricesIncludeGST: Bool = true
    ) -> ItemTaxResult {

        let totalPrice = price * Double(quantity)
        let effectiveGSTRate = gstRate / 100.0
        let effectiveCessRate = cessRate / 100.0

        let taxableValue: Double
        if pricesIncludeGST {
            // Reverse calculation: MRP ÷ (1 + rate) = taxable
            taxableValue = totalPrice / (1.0 + effectiveGSTRate + effectiveCessRate)
        } else {
            taxableValue = totalPrice
        }

        let gstAmount = taxableValue * effectiveGSTRate
        let cessAmount = taxableValue * effectiveCessRate

        let cgst: Double
        let sgst: Double
        let igst: Double

        if isInterState {
            cgst = 0
            sgst = 0
            igst = gstAmount
        } else {
            cgst = gstAmount / 2.0
            sgst = gstAmount / 2.0
            igst = 0
        }

        let totalTax = gstAmount + cessAmount
        let totalWithTax = taxableValue + totalTax

        return ItemTaxResult(
            taxableValue: round2(taxableValue),
            cgst: round2(cgst),
            sgst: round2(sgst),
            igst: round2(igst),
            cess: round2(cessAmount),
            totalTax: round2(totalTax),
            totalWithTax: round2(totalWithTax)
        )
    }

    // MARK: - Bill-Level Breakup

    /// Generate a complete GST breakup from an array of per-item tax results with their rates
    static func generateBreakup(
        itemResults: [(gstRate: Double, result: ItemTaxResult)]
    ) -> GSTBreakup {

        // Group by GST rate
        var grouped: [Double: (taxable: Double, cgst: Double, sgst: Double, igst: Double, cess: Double)] = [:]

        for (rate, result) in itemResults {
            var entry = grouped[rate] ?? (0, 0, 0, 0, 0)
            entry.taxable += result.taxableValue
            entry.cgst += result.cgst
            entry.sgst += result.sgst
            entry.igst += result.igst
            entry.cess += result.cess
            grouped[rate] = entry
        }

        let rateWise = grouped.map { (rate, entry) in
            RateWiseEntry(
                gstRate: rate,
                taxableValue: round2(entry.taxable),
                cgst: round2(entry.cgst),
                sgst: round2(entry.sgst),
                igst: round2(entry.igst),
                cess: round2(entry.cess)
            )
        }.sorted { $0.gstRate < $1.gstRate }

        let totalTaxable = rateWise.reduce(0) { $0 + $1.taxableValue }
        let totalCGST = rateWise.reduce(0) { $0 + $1.cgst }
        let totalSGST = rateWise.reduce(0) { $0 + $1.sgst }
        let totalIGST = rateWise.reduce(0) { $0 + $1.igst }
        let totalCess = rateWise.reduce(0) { $0 + $1.cess }

        return GSTBreakup(
            totalTaxableValue: round2(totalTaxable),
            totalCGST: round2(totalCGST),
            totalSGST: round2(totalSGST),
            totalIGST: round2(totalIGST),
            totalCess: round2(totalCess),
            rateWiseSummary: rateWise
        )
    }

    // MARK: - Inter-State Detection

    /// Determine if a transaction is inter-state
    static func isInterStateSupply(sellerStateCode: String?, buyerStateCode: String?) -> Bool {
        guard let seller = sellerStateCode, let buyer = buyerStateCode,
              !seller.isEmpty, !buyer.isEmpty else {
            return false    // Default to intra-state when unknown
        }
        return seller != buyer
    }

    // MARK: - Composition Scheme

    /// Calculate composition scheme tax (flat rate on total turnover)
    /// This is NOT charged per-invoice; it's for quarterly filing calculation
    static func compositionTax(totalTurnover: Double, compositionRate: Double) -> Double {
        return round2(totalTurnover * (compositionRate / 100.0))
    }

    // MARK: - GSTIN Validation

    /// Basic GSTIN format validation (15 characters, alphanumeric pattern)
    static func isValidGSTIN(_ gstin: String) -> Bool {
        let trimmed = gstin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == 15 else { return false }

        // Pattern: 2 digits (state code) + 10 chars (PAN) + 1 digit (entity) + 1 char (Z default) + 1 check digit
        let pattern = "^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Taxable Value from MRP

    /// Reverse calculate taxable value from MRP (inclusive price)
    static func taxableValueFromMRP(mrp: Double, gstRate: Double, cessRate: Double = 0) -> Double {
        let totalRate = (gstRate + cessRate) / 100.0
        return round2(mrp / (1.0 + totalRate))
    }

    // MARK: - Helpers

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
