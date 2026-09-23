import Foundation

// MARK: - Tally one-tap export (B-easy -> Tally, file share, no bridge)
//
// Only bills NEVER exported before (tally_exports table) go into ONE xml file.
// Tally me company khol ke: Gateway -> Import Data -> Vouchers.
// invoiceNumber hi Tally voucher number jata hai (duplicate-safe).

struct TallyPendingCounts {
    var sales = 0
    var purchases = 0
    var saleAmount = 0.0
    var purchaseAmount = 0.0
    var oldest: Date?
    var total: Int { sales + purchases }
    var totalAmount: Double { saleAmount + purchaseAmount }
}

struct TallyExportResult {
    var url: URL
    var fileName: String
    var sales: Int
    var purchases: Int
}

final class TallyExporter {

    static func pendingCounts(db: Database) -> TallyPendingCounts {
        var out = TallyPendingCounts()
        guard let sdb = db as? SQLiteDatabase,
              let txs = try? db.getTransactions() else { return out }
        let done = sdb.getTallyExportedIDs()
        let pending = txs.filter { !done.contains($0.id.uuidString) }
            .sorted { $0.date < $1.date }
        for tx in pending {
            if tx.type == .sale {
                out.sales += 1
                out.saleAmount += tx.totalAmount
            } else {
                out.purchases += 1
                out.purchaseAmount += tx.totalAmount
            }
            if out.oldest == nil || tx.date < out.oldest! { out.oldest = tx.date }
        }
        return out
    }

    static func pendingTransactions(db: Database) -> [Transaction] {
        guard let sdb = db as? SQLiteDatabase,
              let txs = try? db.getTransactions() else { return [] }
        let done = sdb.getTallyExportedIDs()
        return txs.filter { !done.contains($0.id.uuidString) }
            .sorted { $0.date < $1.date }
    }

    /// Build + write xml, mark rows exported. Returns file to Share.
    static func exportPending(db: Database) throws -> TallyExportResult {
        guard let sdb = db as? SQLiteDatabase else {
            throw NSError(domain: "Tally", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not ready."])
        }
        let pending = pendingTransactions(db: db)
        guard !pending.isEmpty else {
            throw NSError(domain: "Tally", code: 2, userInfo: [NSLocalizedDescriptionKey: "No pending bills. Everything is already exported."])
        }
        var itemsByTx: [UUID: [TransactionItem]] = [:]
        for tx in pending {
            itemsByTx[tx.id] = (try? db.getTransactionItems(for: tx.id)) ?? []
        }
        let xml = buildXML(transactions: pending, itemsByTx: itemsByTx)
        let df = DateFormatter()
        df.dateFormat = "ddMMMyy"
        let fileName = "Tally_Pending_\(df.string(from: Date()))_\(pending.count).xml"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try xml.write(to: url, atomically: true, encoding: .utf8)
        try sdb.markTallyExported(
            transactionIDs: pending.map { $0.id.uuidString },
            invoiceNumbers: pending.map { $0.invoiceNumber },
            fileName: fileName
        )
        return TallyExportResult(
            url: url,
            fileName: fileName,
            sales: pending.filter { $0.type == .sale }.count,
            purchases: pending.filter { $0.type == .purchase }.count
        )
    }

    // MARK: - XML

    static func buildXML(transactions: [Transaction], itemsByTx: [UUID: [TransactionItem]]) -> String {
        var masters: [String: String] = [:] // ledger name -> parent
        masters["Cash"] = "Cash-in-Hand"
        masters["Sales"] = "Sales Accounts"
        masters["Purchase"] = "Purchase Accounts"
        masters["CGST"] = "Duties & Taxes"
        masters["SGST"] = "Duties & Taxes"
        masters["IGST"] = "Duties & Taxes"

        var voucherXML = ""
        for tx in transactions {
            let party: String
            if tx.type == .sale {
                party = sanitizeLedger(tx.customerName?.isEmpty == false ? tx.customerName! : "Cash Sale")
                masters[party] = (party == "Cash Sale" || party == "Cash") ? "Cash-in-Hand" : "Sundry Debtors"
            } else {
                party = sanitizeLedger(tx.supplierName?.isEmpty == false ? tx.supplierName! : "Supplier")
                masters[party] = "Sundry Creditors"
            }
            voucherXML += voucherXMLFor(tx: tx, party: party, items: itemsByTx[tx.id] ?? [])
        }

        var masterXML = ""
        for (name, parent) in masters.sorted(by: { $0.key < $1.key }) {
            masterXML += """
                <TALLYMESSAGE xmlns:UDF="TallyUDF">
                 <LEDGER NAME="\(esc(name))" ACTION="Create">
                  <NAME>\(esc(name))</NAME>
                  <PARENT>\(esc(parent))</PARENT>
                 </LEDGER>
                </TALLYMESSAGE>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <ENVELOPE>
         <HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER>
         <BODY>
          <IMPORTDATA>
           <REQUESTDESC><REPORTNAME>Vouchers</REPORTNAME></REQUESTDESC>
           <REQUESTDATA>
        \(masterXML)
        \(voucherXML)
           </REQUESTDATA>
          </IMPORTDATA>
         </BODY>
        </ENVELOPE>
        """
    }

    private static func voucherXMLFor(tx: Transaction, party: String, items: [TransactionItem]) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        let date = df.string(from: tx.date)
        let vtype = tx.type == .sale ? "Sales" : "Purchase"
        let total = round2(tx.totalAmount)
        let taxable = round2(tx.totalTaxableValue ?? items.reduce(0) { $0 + ($1.taxableValue ?? 0) })
        let cgst = round2(tx.totalCGST ?? items.reduce(0) { $0 + ($1.cgstAmount ?? 0) })
        let sgst = round2(tx.totalSGST ?? items.reduce(0) { $0 + ($1.sgstAmount ?? 0) })
        let igst = round2(tx.totalIGST ?? items.reduce(0) { $0 + ($1.igstAmount ?? 0) })
        let hasTax = (taxable > 0) && (cgst + sgst + igst > 0)
        let narration = esc("B-easy \(tx.invoiceNumber)" + (tx.notes.map { " \($0)" } ?? ""))

        func entry(ledger: String, amount: Double, deemedPositive: Bool) -> String {
            """
            <ALLLEDGERENTRIES.LIST>
             <LEDGERNAME>\(esc(ledger))</LEDGERNAME>
             <ISDEEMEDPOSITIVE>\(deemedPositive ? "Yes" : "No")</ISDEEMEDPOSITIVE>
             <AMOUNT>\(deemedPositive ? "" : "-")\(String(format: "%.2f", abs(amount)))</AMOUNT>
            </ALLLEDGERENTRIES.LIST>
            """
        }

        let entries: String
        if tx.type == .sale {
            if hasTax {
                entries = entry(ledger: party, amount: total, deemedPositive: true)
                    + entry(ledger: "Sales", amount: taxable, deemedPositive: false)
                    + (cgst > 0 ? entry(ledger: "CGST", amount: cgst, deemedPositive: false) : "")
                    + (sgst > 0 ? entry(ledger: "SGST", amount: sgst, deemedPositive: false) : "")
                    + (igst > 0 ? entry(ledger: "IGST", amount: igst, deemedPositive: false) : "")
            } else {
                entries = entry(ledger: party, amount: total, deemedPositive: true)
                    + entry(ledger: "Sales", amount: total, deemedPositive: false)
            }
        } else {
            if hasTax {
                entries = entry(ledger: "Purchase", amount: taxable, deemedPositive: true)
                    + (cgst > 0 ? entry(ledger: "CGST", amount: cgst, deemedPositive: true) : "")
                    + (sgst > 0 ? entry(ledger: "SGST", amount: sgst, deemedPositive: true) : "")
                    + (igst > 0 ? entry(ledger: "IGST", amount: igst, deemedPositive: true) : "")
                    + entry(ledger: party, amount: total, deemedPositive: false)
            } else {
                entries = entry(ledger: "Purchase", amount: total, deemedPositive: true)
                    + entry(ledger: party, amount: total, deemedPositive: false)
            }
        }

        return """
            <TALLYMESSAGE xmlns:UDF="TallyUDF">
             <VOUCHER VCHTYPE="\(vtype)" ACTION="Create">
              <DATE>\(date)</DATE>
              <VOUCHERTYPENAME>\(vtype)</VOUCHERTYPENAME>
              <VOUCHERNUMBER>\(esc(tx.invoiceNumber))</VOUCHERNUMBER>
              <PARTYLEDGERNAME>\(esc(party))</PARTYLEDGERNAME>
              <NARRATION>\(narration)</NARRATION>
        \(entries)
             </VOUCHER>
            </TALLYMESSAGE>
        """
    }

    // MARK: - helpers

    static func sanitizeLedger(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "Cash Sale" }
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_&()."))
        let filtered = t.unicodeScalars.filter { allowed.contains($0) }.map { String($0) }.joined()
        let clean = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(60)).isEmpty ? "Cash Sale" : String(clean.prefix(60))
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}
