// GSTReturnExporter.swift
// Generate GSTR-1 and GSTR-3B JSON files for GST portal upload

import Foundation

final class GSTReturnExporter {

    private let db: Database

    init(database: Database) {
        self.db = database
    }

    // MARK: - GSTR-1 Export

   
    func generateGSTR1(from startDate: Date, to endDate: Date) throws -> Data {
        let settings = try db.getSettings()
        guard settings.isGSTRegistered, settings.gstScheme != "composition" else {
            throw GSTExportError.notRegularScheme
        }

        let allTransactions = try db.getTransactions()
        let salesInPeriod = allTransactions.filter { tx in
            tx.type == .sale && tx.date >= startDate && tx.date <= endDate
        }

        // Separate B2B (with buyer GSTIN) and B2CS (without)
        let b2bTransactions = salesInPeriod.filter { $0.buyerGSTIN != nil && !($0.buyerGSTIN?.isEmpty ?? true) }
        let b2csTransactions = salesInPeriod.filter { $0.buyerGSTIN == nil || $0.buyerGSTIN?.isEmpty == true }

        
        var b2bInvoices: [[String: Any]] = []
        for tx in b2bTransactions {
            let items = (try? db.getTransactionItems(for: tx.id)) ?? []
            var invoice: [String: Any] = [
                "inum": tx.invoiceNumber,
                "idt": formatDate(tx.date),
                "val": tx.totalAmount,
                "pos": tx.placeOfSupplyCode ?? "",
                "rchrg": (tx.isReverseCharge ?? false) ? "Y" : "N",
                "inv_typ": "R",   // Regular
                "ctin": tx.buyerGSTIN ?? ""
            ]

            var itemEntries: [[String: Any]] = []
            for item in items {
                var entry: [String: Any] = [
                    "num": 0,
                    "itm_det": [
                        "txval": item.taxableValue ?? 0,
                        "rt": item.gstRate ?? 0,
                        "camt": item.cgstAmount ?? 0,
                        "samt": item.sgstAmount ?? 0,
                        "iamt": item.igstAmount ?? 0,
                        "csamt": item.cessAmount ?? 0
                    ] as [String : Any]
                ]
                if let hsn = item.hsnCode {
                    entry["hsn_sc"] = hsn
                }
                itemEntries.append(entry)
            }
            invoice["itms"] = itemEntries
            b2bInvoices.append(invoice)
        }

       
        var b2csSummary: [[String: Any]] = []
        var b2csGrouped: [String: (taxable: Double, cgst: Double, sgst: Double, igst: Double, cess: Double)] = [:]

        for tx in b2csTransactions {
            let items = (try? db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let rate = item.gstRate ?? 0
                let pos = tx.placeOfSupplyCode ?? settings.businessStateCode ?? ""
                let key = "\(rate)-\(pos)"
                var entry = b2csGrouped[key] ?? (0, 0, 0, 0, 0)
                entry.taxable += item.taxableValue ?? 0
                entry.cgst += item.cgstAmount ?? 0
                entry.sgst += item.sgstAmount ?? 0
                entry.igst += item.igstAmount ?? 0
                entry.cess += item.cessAmount ?? 0
                b2csGrouped[key] = entry
            }
        }

        for (key, values) in b2csGrouped {
            let parts = key.split(separator: "-")
            b2csSummary.append([
                "rt": Double(parts[0]) ?? 0,
                "pos": String(parts.count > 1 ? parts[1] : ""),
                "typ": "OE",  // Outward taxable (excluding reverse charge)
                "txval": round2(values.taxable),
                "camt": round2(values.cgst),
                "samt": round2(values.sgst),
                "iamt": round2(values.igst),
                "csamt": round2(values.cess)
            ] as [String : Any])
        }

        
        let hsnSummary = try buildHSNSummary(transactions: salesInPeriod)

        
        let gstr1: [String: Any] = [
            "gstin": settings.gstNumber ?? "",
            "fp": formatPeriod(startDate),
            "b2b": b2bInvoices,
            "b2cs": b2csSummary,
            "hsn": ["data": hsnSummary]
        ]

        return try JSONSerialization.data(withJSONObject: gstr1, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - GSTR-3B Summary

  
    func generateGSTR3B(from startDate: Date, to endDate: Date) throws -> Data {
        let settings = try db.getSettings()
        guard settings.isGSTRegistered, settings.gstScheme != "composition" else {
            throw GSTExportError.notRegularScheme
        }

        let allTransactions = try db.getTransactions()

        // Output tax (sales)
        let sales = allTransactions.filter { $0.type == .sale && $0.date >= startDate && $0.date <= endDate }
        var outputTaxable: Double = 0, outputCGST: Double = 0, outputSGST: Double = 0
        var outputIGST: Double = 0, outputCess: Double = 0

        for tx in sales {
            outputTaxable += tx.totalTaxableValue ?? 0
            outputCGST += tx.totalCGST ?? 0
            outputSGST += tx.totalSGST ?? 0
            outputIGST += tx.totalIGST ?? 0
            outputCess += tx.totalCess ?? 0
        }

        // Input tax credit (purchases)
        let purchases = allTransactions.filter { $0.type == .purchase && $0.date >= startDate && $0.date <= endDate }
        var inputCGST: Double = 0, inputSGST: Double = 0
        var inputIGST: Double = 0, inputCess: Double = 0

        for tx in purchases {
            inputCGST += tx.totalCGST ?? 0
            inputSGST += tx.totalSGST ?? 0
            inputIGST += tx.totalIGST ?? 0
            inputCess += tx.totalCess ?? 0
        }

        let net = gstCashAfterITC(
            outputIGST: outputIGST, outputCGST: outputCGST, outputSGST: outputSGST, outputCess: outputCess,
            itcIGST: inputIGST, itcCGST: inputCGST, itcSGST: inputSGST, itcCess: inputCess
        )

        let gstr3b: [String: Any] = [
            "gstin": settings.gstNumber ?? "",
            "ret_period": formatPeriod(startDate),
            "_note": "Working papers for 3.1 / 4 / 6.1. Not a GSTN filing JSON. Review before upload.",
            "sup_details": [
                "osup_det": [
                    "txval": round2(outputTaxable),
                    "camt": round2(outputCGST),
                    "samt": round2(outputSGST),
                    "iamt": round2(outputIGST),
                    "csamt": round2(outputCess)
                ],
                "osup_zero": emptyTax(),
                "osup_nil_exmp": emptyTax(),
                "osup_nongst": emptyTax(),
                "isup_rev": emptyTax()
            ],
            "itc_elg": [
                "itc_avl": [
                    taxRow("IMPG"),
                    taxRow("IMPS"),
                    taxRow("ISRC"),
                    taxRow("ISD"),
                    [
                        "ty": "OTH",
                        "iamt": round2(inputIGST),
                        "camt": round2(inputCGST),
                        "samt": round2(inputSGST),
                        "csamt": round2(inputCess)
                    ]
                ],
                "itc_rev": [taxRow("RUL"), taxRow("OTH")],
                "itc_net": [
                    "iamt": round2(inputIGST),
                    "camt": round2(inputCGST),
                    "samt": round2(inputSGST),
                    "csamt": round2(inputCess)
                ],
                "itc_inelg": [taxRow("RUL"), taxRow("OTH")]
            ],
            "tx_pmt": [
                "pditc": [
                    "iamt": round2(net.itcUsedIGST),
                    "camt": round2(net.itcUsedCGST),
                    "samt": round2(net.itcUsedSGST),
                    "csamt": round2(net.itcUsedCess)
                ],
                "tx_py": [
                    [
                        "trans_typ": "Cash",
                        "igst": ["tx": round2(net.cashIGST)],
                        "cgst": ["tx": round2(net.cashCGST)],
                        "sgst": ["tx": round2(net.cashSGST)],
                        "cess": ["tx": round2(net.cashCess)]
                    ]
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: gstr3b, options: [.prettyPrinted, .sortedKeys])
    }

    private func emptyTax() -> [String: Double] {
        ["txval": 0, "iamt": 0, "camt": 0, "samt": 0, "csamt": 0]
    }

    private func taxRow(_ ty: String) -> [String: Any] {
        ["ty": ty, "iamt": 0, "camt": 0, "samt": 0, "csamt": 0]
    }

    private func gstCashAfterITC(
        outputIGST: Double, outputCGST: Double, outputSGST: Double, outputCess: Double,
        itcIGST: Double, itcCGST: Double, itcSGST: Double, itcCess: Double
    ) -> (cashIGST: Double, cashCGST: Double, cashSGST: Double, cashCess: Double,
          itcUsedIGST: Double, itcUsedCGST: Double, itcUsedSGST: Double, itcUsedCess: Double) {
        var igstITC = itcIGST, cgstITC = itcCGST, sgstITC = itcSGST, cessITC = itcCess
        var igstLiab = outputIGST, cgstLiab = outputCGST, sgstLiab = outputSGST, cessLiab = outputCess

        let igstFromIGST = min(igstLiab, igstITC)
        igstLiab -= igstFromIGST
        igstITC -= igstFromIGST
        let igstFromCGST = min(igstLiab, cgstITC)
        igstLiab -= igstFromCGST
        cgstITC -= igstFromCGST
        let igstFromSGST = min(igstLiab, sgstITC)
        igstLiab -= igstFromSGST
        sgstITC -= igstFromSGST

        let cgstFromCGST = min(cgstLiab, cgstITC)
        cgstLiab -= cgstFromCGST
        cgstITC -= cgstFromCGST
        let cgstFromIGST = min(cgstLiab, igstITC)
        cgstLiab -= cgstFromIGST
        igstITC -= cgstFromIGST

        let sgstFromSGST = min(sgstLiab, sgstITC)
        sgstLiab -= sgstFromSGST
        sgstITC -= sgstFromSGST
        let sgstFromIGST = min(sgstLiab, igstITC)
        sgstLiab -= sgstFromIGST
        igstITC -= sgstFromIGST

        let cessFromCess = min(cessLiab, cessITC)
        cessLiab -= cessFromCess
        cessITC -= cessFromCess

        return (
            cashIGST: igstLiab, cashCGST: cgstLiab, cashSGST: sgstLiab, cashCess: cessLiab,
            itcUsedIGST: itcIGST - igstITC,
            itcUsedCGST: itcCGST - cgstITC,
            itcUsedSGST: itcSGST - sgstITC,
            itcUsedCess: itcCess - cessITC
        )
    }

    // MARK: - HSN Summary

    private func buildHSNSummary(transactions: [Transaction]) throws -> [[String: Any]] {
        var hsnMap: [String: (qty: Double, taxable: Double, cgst: Double, sgst: Double, igst: Double, cess: Double)] = [:]

        for tx in transactions {
            let items = (try? db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let hsn = item.hsnCode ?? "Others"
                var entry = hsnMap[hsn] ?? (0, 0, 0, 0, 0, 0)
                entry.qty += item.quantity
                entry.taxable += item.taxableValue ?? 0
                entry.cgst += item.cgstAmount ?? 0
                entry.sgst += item.sgstAmount ?? 0
                entry.igst += item.igstAmount ?? 0
                entry.cess += item.cessAmount ?? 0
                hsnMap[hsn] = entry
            }
        }

        return hsnMap.map { (hsn, values) in
            [
                "hsn_sc": hsn,
                "qty": values.qty,
                "txval": round2(values.taxable),
                "camt": round2(values.cgst),
                "samt": round2(values.sgst),
                "iamt": round2(values.igst),
                "csamt": round2(values.cess)
            ] as [String : Any]
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "dd-MM-yyyy"
        return df.string(from: date)
    }

    private func formatPeriod(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMyyyy"
        return df.string(from: date)
    }

    private func round2(_ value: Double) -> Double {
        Money.round2(value)
    }
}

// MARK: - Errors

enum GSTExportError: Error, LocalizedError {
    case notRegularScheme
    case noDataInPeriod

    var errorDescription: String? {
        switch self {
        case .notRegularScheme: return "GSTR export is only available for Regular scheme GST registration."
        case .noDataInPeriod: return "No transactions found in the selected period."
        }
    }
}
