import Foundation

nonisolated enum ShopLedgerLookup {
    private static var dm: DataModel { AppDataModel.shared.dataModel }
    private static let rupee: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()

    static func money(_ value: Double) -> String {
        rupee.string(from: NSNumber(value: value)) ?? String(format: "₹%.2f", value)
    }

    static func parseDay(_ raw: String?) -> Date {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "today"
        let cal = Calendar.current
        if text == "today" || text.isEmpty { return cal.startOfDay(for: Date()) }
        if text == "yesterday" { return cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) ?? Date() }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_IN")
        if let d = df.date(from: text) { return cal.startOfDay(for: d) }
        return cal.startOfDay(for: Date())
    }

    static func shopSnapshot() -> String {
        let settings = try? dm.db.getSettings()
        let today = dm.getTodayStats()
        var lines: [String] = []
        lines.append("shop=\(settings?.businessName ?? "Shop")")
        if let owner = settings?.ownerName, !owner.isEmpty { lines.append("owner=\(owner)") }
        lines.append("todayRevenue=\(money(today.revenue))")
        lines.append("todayProfit=\(money(today.profit))")
        lines.append("todayPurchases=\(money(today.purchaseTotal))")
        lines.append("todaySaleCount=\(today.saleCount)")
        lines.append("fyRevenue=\(money(dm.getFinancialYearRevenue()))")
        lines.append("allTimeSales=\(money(dm.getAllTimeRevenue()))")
        lines.append("fyPurchases=\(money(dm.getFinancialYearInvestment()))")
        lines.append("stockValue=\(money(dm.getTotalInvestment()))")
        lines.append("receivable=\(money(CreditStore.shared.getTotalReceivable()))")
        lines.append("payable=\(money(CreditStore.shared.getTotalPayable()))")
        let low = (try? dm.getLowStockAlerts()) ?? []
        lines.append("lowStockItems=\(low.count)")
        let expiry = (try? dm.getExpiryAlerts()) ?? []
        lines.append("expiryAlerts=\(expiry.count)")
        return lines.joined(separator: "\n")
    }

    static func friendlyShopSummary() -> String {
        let today = dm.getTodayStats()
        let items = (try? dm.getAllItems()) ?? []
        if today.saleCount == 0 && items.isEmpty {
            return emptyBooksMessage
        }
        let receivable = CreditStore.shared.getTotalReceivable()
        return "Today’s sales \(money(today.revenue)), profit \(money(today.profit)). Pending udhaar \(money(receivable))."
    }

    static let emptyBooksMessage =
        "This shop has no sales or stock yet. Add items in Stock and record a sale, then I can answer from your books."

    static func hasAnyBooks() -> Bool {
        let items = (try? dm.getAllItems()) ?? []
        if !items.isEmpty { return true }
        let txs = (try? dm.db.getTransactions()) ?? []
        return !txs.isEmpty
    }

    static func topSellingProducts(limit: Int = 5) -> String {
        let sales = dm.getRecentTransactions(limit: 500, type: .sale)
        if sales.isEmpty {
            return "No sales recorded yet, so there is no best-selling product."
        }
        var qtyByName: [String: Double] = [:]
        var rupeesByName: [String: Double] = [:]
        for row in sales {
            let lines = (try? dm.db.getTransactionItems(for: row.transaction.id)) ?? []
            for line in lines {
                let name = line.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                qtyByName[name, default: 0] += line.quantity
                rupeesByName[name, default: 0] += line.totalRevenue
            }
        }
        let ranked = qtyByName.sorted { $0.value > $1.value }.prefix(max(1, limit))
        guard let top = ranked.first else {
            return "No sales recorded yet, so there is no best-selling product."
        }
        if ranked.count == 1 {
            return "Best seller: \(top.key) (\(Self.trimQty(top.value)) sold, \(money(rupeesByName[top.key] ?? 0)))."
        }
        let list = ranked.enumerated().map { index, row in
            "\(index + 1). \(row.key) — \(Self.trimQty(row.value)) sold (\(money(rupeesByName[row.key] ?? 0)))"
        }.joined(separator: "\n")
        return "Top selling products:\n\(list)"
    }

    private static func trimQty(_ value: Double) -> String {
        if value == value.rounded() { return String(format: "%.0f", value) }
        return String(format: "%.2f", value)
    }

    static func searchItems(query: String, limit: Int) -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cap = min(max(limit, 1), 25)
        let items = (try? dm.getAllItems()) ?? []
        let matched = items.filter { item in
            q.isEmpty || item.name.localizedStandardContains(q) || (item.barcode?.localizedStandardContains(q) == true)
        }.prefix(cap)
        if matched.isEmpty { return "No matching items." }
        return matched.map { item in
            var row = "\(item.name) | stock=\(item.currentStock) \(item.unit) | sell=\(money(item.defaultSellingPrice)) | cost=\(money(item.defaultCostPrice))"
            if let barcode = item.barcode, !barcode.isEmpty { row += " | barcode=\(barcode)" }
            if let gst = item.gstRate { row += " | gst=\(gst)%" }
            return row
        }.joined(separator: "\n")
    }

    static func itemDetail(name: String) -> String {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = (try? dm.getAllItems()) ?? []
        guard let item = items.first(where: { $0.name.localizedCaseInsensitiveCompare(q) == .orderedSame })
                ?? items.first(where: { $0.name.localizedStandardContains(q) }) else {
            return "Item not found: \(q)"
        }
        let batches = (try? dm.db.getBatches(for: item.id)) ?? []
        let live = batches.filter { $0.quantityRemaining > 0 }
        var lines = [
            "name=\(item.name)",
            "stock=\(item.currentStock) \(item.unit)",
            "lowStockAt=\(item.lowStockThreshold)",
            "sell=\(money(item.defaultSellingPrice))",
            "cost=\(money(item.defaultCostPrice))"
        ]
        if let barcode = item.barcode, !barcode.isEmpty { lines.append("barcode=\(barcode)") }
        lines.append("openBatches=\(live.count)")
        for batch in live.prefix(8) {
            let exp = batch.expiryDate.map { ISO8601DateFormatter().string(from: $0) } ?? "none"
            lines.append("batch qty=\(batch.quantityRemaining) cost=\(money(batch.costPrice)) expiry=\(exp)")
        }
        return lines.joined(separator: "\n")
    }

    static func creditParty(name: String, kind: String) -> String {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind.lowercased().contains("sup") {
            let all = CreditStore.shared.getAllSuppliers()
            guard let party = all.first(where: { $0.name.localizedCaseInsensitiveCompare(q) == .orderedSame })
                    ?? all.first(where: { $0.name.localizedStandardContains(q) }) else {
                return "Supplier not found: \(q)"
            }
            let bal = CreditStore.shared.getNetBalance(forSupplier: party.id)
            return "supplier=\(party.name) balanceYouOwe=\(money(max(0, bal))) raw=\(money(bal))"
        }
        let all = CreditStore.shared.getAllCustomers()
        guard let party = all.first(where: { $0.name.localizedCaseInsensitiveCompare(q) == .orderedSame })
                ?? all.first(where: { $0.name.localizedStandardContains(q) }) else {
            return "Customer not found: \(q)"
        }
        let bal = CreditStore.shared.getNetBalance(forCustomer: party.id)
        return "customer=\(party.name) theyOweYou=\(money(max(0, bal))) raw=\(money(bal))"
    }

    static func creditOverview(kind: String) -> String {
        if kind.lowercased().contains("sup") {
            let rows = CreditStore.shared.getAllSuppliers()
                .map { ($0.name, CreditStore.shared.getNetBalance(forSupplier: $0.id)) }
                .filter { $0.1 > 0.5 }
                .sorted { $0.1 > $1.1 }
                .prefix(20)
            if rows.isEmpty { return "No supplier payables." }
            return rows.map { "\($0.0) \(money($0.1))" }.joined(separator: "\n")
        }
        let rows = CreditStore.shared.getAllCustomers()
            .map { ($0.name, CreditStore.shared.getNetBalance(forCustomer: $0.id)) }
            .filter { $0.1 > 0.5 }
            .sorted { $0.1 > $1.1 }
            .prefix(20)
        if rows.isEmpty { return "No customer receivables." }
        return rows.map { "\($0.0) \(money($0.1))" }.joined(separator: "\n")
    }

    static func recentBills(kind: String, limit: Int, day: String?) -> String {
        let cap = min(max(limit, 1), 20)
        let type: TransactionType? = {
            let k = kind.lowercased()
            if k.contains("sale") { return .sale }
            if k.contains("purch") { return .purchase }
            return nil
        }()
        var rows = dm.getRecentTransactions(limit: 80, type: type)
        if let day, !day.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let start = parseDay(day)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
            rows = rows.filter { $0.transaction.date >= start && $0.transaction.date < end }
        }
        let slice = Array(rows.prefix(cap))
        if slice.isEmpty { return "No bills found." }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return slice.map { row in
            let tx = row.transaction
            let who = tx.customerName ?? tx.supplierName ?? "—"
            return "\(df.string(from: tx.date)) \(tx.type.rawValue) \(tx.invoiceNumber) \(who) \(money(tx.totalAmount)) | \(row.itemsSummary)"
        }.joined(separator: "\n")
    }

    static func lowStock() -> String {
        let alerts = (try? dm.getLowStockAlerts()) ?? []
        if alerts.isEmpty { return "No low-stock items." }
        return alerts.prefix(25).map {
            "\($0.itemName) stock=\($0.currentStock) \($0.unit) threshold=\($0.threshold)"
        }.joined(separator: "\n")
    }

    static func expiry() -> String {
        let alerts = (try? dm.getExpiryAlerts()) ?? []
        if alerts.isEmpty { return "No expiry alerts." }
        return alerts.prefix(25).map {
            "\($0.itemName) qty=\($0.quantityRemaining) days=\($0.daysUntilExpiry)"
        }.joined(separator: "\n")
    }

    static func daySummary(_ day: String) -> String {
        let date = parseDay(day)
        if let summary = try? dm.db.getDailySummary(for: date) {
            return "date=\(day) revenue=\(money(summary.totalRevenue)) purchases=\(money(summary.totalPurchaseAmount)) profit=\(money(summary.totalProfit))"
        }
        return "No daily summary stored for that date. Use recent bills for that day."
    }

    static func partyLedger(name: String, months: Int) -> String {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let window = max(1, min(months, 24))
        let start = Calendar.current.date(byAdding: .month, value: -window, to: Date()) ?? Date()
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        let customers = CreditStore.shared.getAllCustomers()
        let customer = customers.first(where: { $0.name.localizedCaseInsensitiveCompare(q) == .orderedSame })
            ?? customers.first(where: { $0.name.localizedStandardContains(q) })

        let suppliers = CreditStore.shared.getAllSuppliers()
        let supplier = suppliers.first(where: { $0.name.localizedCaseInsensitiveCompare(q) == .orderedSame })
            ?? suppliers.first(where: { $0.name.localizedStandardContains(q) })

        if customer == nil && supplier == nil {
            let hints = (customers.map(\.name) + suppliers.map(\.name))
                .filter { $0.localizedStandardContains(q.prefix(3).description) }
                .prefix(8)
            return "No party named \(q). Close names: \(hints.joined(separator: ", "))"
        }

        var blocks: [String] = []
        if let customer {
            let bal = CreditStore.shared.getNetBalance(forCustomer: customer.id)
            blocks.append("CUSTOMER \(customer.name) outstandingUdhaar(theyOweYou)=\(money(max(0, bal))) raw=\(money(bal))")
            let pays = CreditStore.shared.getPayments(forCustomer: customer.id)
                .filter { $0.date >= start }
                .sorted { $0.date > $1.date }
            if pays.isEmpty {
                blocks.append("No udhaar entries in last \(window) months.")
            } else {
                let creditGiven = pays.filter { $0.type == .paid }.reduce(0.0) { $0 + $1.amount }
                let collected = pays.filter { $0.type == .received }.reduce(0.0) { $0 + $1.amount }
                blocks.append("last\(window)Months creditSales=\(money(creditGiven)) collections=\(money(collected))")
                blocks.append(pays.prefix(40).map { p in
                    "\(df.string(from: p.date)) \(p.type.rawValue) \(money(p.amount)) \(p.note ?? "")"
                }.joined(separator: "\n"))
            }
            let bills = dm.getRecentTransactions(limit: 400, type: .sale)
                .filter { ($0.transaction.customerName ?? "").localizedStandardContains(customer.name) && $0.transaction.date >= start }
            if !bills.isEmpty {
                let total = bills.reduce(0.0) { $0 + $1.transaction.totalAmount }
                blocks.append("SALE_BILLS last\(window)Months count=\(bills.count) total=\(money(total))")
                blocks.append(bills.prefix(40).map { row in
                    "\(df.string(from: row.transaction.date)) \(row.transaction.invoiceNumber) \(money(row.transaction.totalAmount)) | \(row.itemsSummary)"
                }.joined(separator: "\n"))
            }
        }
        if let supplier {
            let bal = CreditStore.shared.getNetBalance(forSupplier: supplier.id)
            blocks.append("SUPPLIER \(supplier.name) youOwe=\(money(max(0, bal))) raw=\(money(bal))")
            let bills = dm.getRecentTransactions(limit: 400, type: .purchase)
                .filter { ($0.transaction.supplierName ?? "").localizedStandardContains(supplier.name) && $0.transaction.date >= start }
            if !bills.isEmpty {
                let total = bills.reduce(0.0) { $0 + $1.transaction.totalAmount }
                blocks.append("PURCHASE_BILLS last\(window)Months count=\(bills.count) total=\(money(total))")
                blocks.append(bills.prefix(30).map { row in
                    "\(df.string(from: row.transaction.date)) \(row.transaction.invoiceNumber) \(money(row.transaction.totalAmount)) | \(row.itemsSummary)"
                }.joined(separator: "\n"))
            }
        }
        return blocks.joined(separator: "\n")
    }
}
