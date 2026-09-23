import Foundation

// MARK: - Tally backward import (Tally DayBook XML -> mirror tables, file-based)
//
// Backward import: a Tally Day Book XML export is picked from Files/WhatsApp
// and saved into mirror tables (tally_vouchers/items/parties/imports).
// The app ledger is never modified. Duplicate files are skipped.

struct TallyParsedVoucher {
    var date: String  // yyyy-MM-dd
    var no: String
    var type: String  // sale | purchase | receipt | payment | ...
    var party: String
    var amount: Double
    var items: [(name: String, qty: Double, rate: Double)]
}

final class TallyImporter: NSObject {

    static func parseDayBookXML(data: Data) throws -> [TallyParsedVoucher] {
        let parser = TallyDayBookParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.shouldResolveExternalEntities = false
        guard xml.parse() else {
            throw NSError(domain: "TallyImport", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't read this file. Please choose a Tally Day Book XML export."
            ])
        }
        return parser.vouchers
    }

    static func importFile(url: URL, db: Database) throws -> (vouchers: Int, fileName: String) {
        guard let sdb = db as? SQLiteDatabase else {
            throw NSError(domain: "TallyImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Database not ready."])
        }
        let fileName = url.lastPathComponent
        if sdb.hasTallyImport(fileName: fileName) {
            throw NSError(domain: "TallyImport", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "This file was already imported (\(fileName))."
            ])
        }
        let data = try Data(contentsOf: url)
        let vouchers = try parseDayBookXML(data: data)
        guard !vouchers.isEmpty else {
            throw NSError(domain: "TallyImport", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "No vouchers found in this file."
            ])
        }
        let mapped = vouchers.map { v in
            (date: v.date, no: v.no, type: v.type, party: v.party, amount: v.amount,
             items: v.items)
        }
        let inserted = try sdb.insertTallyMirror(vouchers: mapped, fileName: fileName)
        return (inserted, fileName)
    }
}

// MARK: - XML parser (Tally DayBook export shape)

private final class TallyDayBookParser: NSObject, XMLParserDelegate {
    var vouchers: [TallyParsedVoucher] = []

    private var inVoucher = false
    private var current: TallyParsedVoucher?
    private var text = ""
    private var inLedgerEntry = false
    private var inInventoryEntry = false
    private var entryAmount = 0.0
    private var maxAmount = 0.0
    private var itemName = ""
    private var itemQty = 0.0
    private var itemRate = 0.0
    private var elementStack: [String] = []

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attrs: [String: String] = [:]) {
        elementStack.append(name)
        text = ""
        if name == "VOUCHER" {
            inVoucher = true
            let vt = (attrs["VCHTYPE"] ?? "").lowercased()
            current = TallyParsedVoucher(date: "", no: "", type: vt, party: "", amount: 0, items: [])
            maxAmount = 0
        } else if inVoucher && name == "ALLLEDGERENTRIES.LIST" {
            inLedgerEntry = true
            entryAmount = 0
        } else if inVoucher && (name == "INVENTORYENTRIES.LIST" || name == "INVENTORYENTRIESIN.LIST" || name == "INVENTORYENTRIESOUT.LIST") {
            inInventoryEntry = true
            itemName = ""; itemQty = 0; itemRate = 0
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inVoucher {
            switch name {
            case "DATE", "DSPVCHDATE":
                if current?.date.isEmpty == true { current?.date = Self.normDate(value) }
            case "VOUCHERNUMBER":
                if current?.no.isEmpty == true { current?.no = value }
            case "VOUCHERTYPENAME":
                if current?.type.isEmpty == true { current?.type = Self.normType(value) }
            case "PARTYLEDGERNAME":
                if !inLedgerEntry && current?.party.isEmpty == true { current?.party = value }
            case "AMOUNT":
                if inLedgerEntry, let a = Double(value.replacingOccurrences(of: ",", with: "")) {
                    entryAmount = a
                }
            case "STOCKITEMNAME":
                if inInventoryEntry { itemName = value }
            case "ACTUALQTY":
                if inInventoryEntry { itemQty = Self.parseQty(value) }
            case "RATE":
                if inInventoryEntry, let r = Double(value.replacingOccurrences(of: ",", with: "").split(separator: "/").first.map(String.init) ?? "") {
                    itemRate = r
                }
            case "ALLLEDGERENTRIES.LIST":
                maxAmount = max(maxAmount, abs(entryAmount))
                inLedgerEntry = false
            case "INVENTORYENTRIES.LIST", "INVENTORYENTRIESIN.LIST", "INVENTORYENTRIESOUT.LIST":
                if !itemName.isEmpty {
                    current?.items.append((name: itemName, qty: itemQty, rate: itemRate))
                }
                inInventoryEntry = false
            case "VOUCHER":
                if var v = current, !v.no.isEmpty || maxAmount > 0 {
                    if v.no.isEmpty { v.no = "TLY-\(vouchers.count + 1)" }
                    if v.date.isEmpty { v.date = "1970-01-01" }
                    v.amount = maxAmount
                    if v.type.isEmpty { v.type = "journal" }
                    vouchers.append(v)
                }
                current = nil
                inVoucher = false
            default:
                break
            }
        }
        elementStack.removeLast()
        text = ""
    }

    static func normType(_ s: String) -> String {
        let l = s.lowercased()
        if l.contains("sales") { return "sale" }
        if l.contains("purch") { return "purchase" }
        if l.contains("receipt") { return "receipt" }
        if l.contains("payment") { return "payment" }
        if l.contains("contra") { return "contra" }
        if l.contains("journal") { return "journal" }
        if l.contains("credit") { return "credit-note" }
        if l.contains("debit") { return "debit-note" }
        return l.isEmpty ? "journal" : l
    }

    static func normDate(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count == 8, let y = Int(t.prefix(4)) {
            // YYYYMMDD
            let m = t.dropFirst(4).prefix(2), d = t.dropFirst(6).prefix(2)
            return String(format: "%04d-%@-%@", y, String(m), String(d))
        }
        for fmt in ["dd-MM-yyyy", "dd/MM/yyyy", "yyyy-MM-dd", "dd-MMM-yyyy"] {
            let df = DateFormatter()
            df.dateFormat = fmt
            df.locale = Locale(identifier: "en_IN")
            if let dt = df.date(from: t) {
                let out = DateFormatter()
                out.dateFormat = "yyyy-MM-dd"
                return out.string(from: dt)
            }
        }
        return t
    }

    static func parseQty(_ s: String) -> Double {
        // "10 kg" / "5.5" / "2 PCS"
        let num = s.split(separator: " ").first.map(String.init) ?? s
        return Double(num.replacingOccurrences(of: ",", with: "")) ?? 0
    }
}
