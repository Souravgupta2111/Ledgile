// GSTEngine.swift
// Core GST tax calculation engine for Ledgile

import Foundation

enum GSTEngine {


    static func paise(_ value: Double) -> Int64 {
        Int64((value * 100.0).rounded())
    }

    static func rupees(_ paise: Int64) -> Double {
        Double(paise) / 100.0
    }

    static func calculateTax(
        price: Double,
        quantity: Double,
        gstRate: Double,
        cessRate: Double = 0,
        isInterState: Bool,
        pricesIncludeGST: Bool = true
    ) -> ItemTaxResult {

        let totalPaise = paise(price * quantity)
        let gstRateFrac = gstRate / 100.0
        let cessRateFrac = cessRate / 100.0
        let combined = 1.0 + gstRateFrac + cessRateFrac

        let taxablePaise: Int64
        var gstPaise: Int64
        var cessPaise: Int64
        if pricesIncludeGST {
            taxablePaise = Int64((Double(totalPaise) / combined).rounded())
            let remainder = max(Int64(0), totalPaise - taxablePaise)
            cessPaise = Int64((Double(taxablePaise) * cessRateFrac).rounded())
            if cessPaise > remainder { cessPaise = remainder }
            gstPaise = remainder - cessPaise
        } else {
            taxablePaise = totalPaise
            gstPaise = Int64((Double(taxablePaise) * gstRateFrac).rounded())
            cessPaise = Int64((Double(taxablePaise) * cessRateFrac).rounded())
        }

        let cgstPaise: Int64
        let sgstPaise: Int64
        let igstPaise: Int64
        if isInterState {
            cgstPaise = 0
            sgstPaise = 0
            igstPaise = gstPaise
        } else {
            cgstPaise = gstPaise / 2
            sgstPaise = gstPaise - cgstPaise
            igstPaise = 0
        }

        let totalTaxPaise = cgstPaise + sgstPaise + igstPaise + cessPaise
        let totalWithTaxPaise = pricesIncludeGST ? totalPaise : (taxablePaise + totalTaxPaise)

        return ItemTaxResult(
            taxableValue: rupees(taxablePaise),
            cgst: rupees(cgstPaise),
            sgst: rupees(sgstPaise),
            igst: rupees(igstPaise),
            cess: rupees(cessPaise),
            totalTax: rupees(totalTaxPaise),
            totalWithTax: rupees(totalWithTaxPaise)
        )
    }

    static func identityHolds(_ result: ItemTaxResult) -> Bool {
        paise(result.taxableValue) + paise(result.totalTax) == paise(result.totalWithTax)
            && paise(result.cgst) + paise(result.sgst) + paise(result.igst) + paise(result.cess) == paise(result.totalTax)
    }

    // MARK: - Bill-Level Breakup

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
                taxableValue: rupees(paise(entry.taxable)),
                cgst: rupees(paise(entry.cgst)),
                sgst: rupees(paise(entry.sgst)),
                igst: rupees(paise(entry.igst)),
                cess: rupees(paise(entry.cess))
            )
        }.sorted { $0.gstRate < $1.gstRate }

        let totalTaxable = rateWise.reduce(Int64(0)) { $0 + paise($1.taxableValue) }
        let totalCGST = rateWise.reduce(Int64(0)) { $0 + paise($1.cgst) }
        let totalSGST = rateWise.reduce(Int64(0)) { $0 + paise($1.sgst) }
        let totalIGST = rateWise.reduce(Int64(0)) { $0 + paise($1.igst) }
        let totalCess = rateWise.reduce(Int64(0)) { $0 + paise($1.cess) }

        return GSTBreakup(
            totalTaxableValue: rupees(totalTaxable),
            totalCGST: rupees(totalCGST),
            totalSGST: rupees(totalSGST),
            totalIGST: rupees(totalIGST),
            totalCess: rupees(totalCess),
            rateWiseSummary: rateWise
        )
    }

    // MARK: - Inter-State Detection

    static func discountedUnitPrice(
        lineRevenue: Double,
        subtotal: Double,
        discount: Double,
        quantity: Double
    ) -> Double {
        guard quantity > 0 else { return 0 }
        let share = subtotal > 0 ? lineRevenue / subtotal : 0
        let net = max(0, lineRevenue - discount * share)
        return net / quantity
    }

    static func buyerStateCode(explicit: String?, gstin: String?, shopStateCode: String?) -> String? {
        if let explicit, !explicit.isEmpty { return explicit }
        if let gstin {
            let prefix = String(gstin.prefix(2))
            if prefix.count == 2, prefix.allSatisfy(\.isNumber) { return prefix }
        }
        _ = shopStateCode
        return nil
    }

    /// `nil` when seller or buyer state is missing. Never treat unknown POS as intra-state.
    static func isInterStateSupply(sellerStateCode: String?, buyerStateCode: String?) -> Bool? {
        let seller = sellerStateCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let buyer = buyerStateCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard seller.count >= 2, buyer.count >= 2 else { return nil }
        return seller != buyer
    }

    static func compositionTax(totalTurnover: Double, compositionRate: Double) -> Double {
        return round2(totalTurnover * (compositionRate / 100.0))
    }

    // MARK: - GSTIN Validation

   
    static func isValidGSTIN(_ gstin: String) -> Bool {
        let trimmed = gstin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == 15 else { return false }
        let pattern = "^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$"
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else { return false }
        return gstinCheckCharacter(trimmed) == trimmed.last
    }

    private static func gstinCheckCharacter(_ gstin: String) -> Character? {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var hash = 0
        for (i, ch) in gstin.prefix(14).enumerated() {
            guard let code = charset.firstIndex(of: ch) else { return nil }
            let product = code * (1 + i % 2)
            hash += product / 36 + product % 36
        }
        let check = (36 - (hash % 36)) % 36
        return charset[check]
    }

   
    /// Reverse calculate taxable value from MRP (inclusive price)
    static func taxableValueFromMRP(mrp: Double, gstRate: Double, cessRate: Double = 0) -> Double {
        let totalRate = (gstRate + cessRate) / 100.0
        return round2(mrp / (1.0 + totalRate))
    }

   

    private static func round2(_ value: Double) -> Double {
        Money.round2(value)
    }

    static func roundRupees(_ value: Double) -> Double {
        Money.round2(value)
    }
}
