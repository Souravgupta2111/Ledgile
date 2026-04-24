import UIKit
import QuickLook

// MARK: - Report Type Enum

enum ReportType: String, CaseIterable {
    case profitAndLoss       = "Profit & Loss"
    case salesRegister       = "Sales Register"
    case purchaseRegister    = "Purchase Register"
    case stockSummary        = "Stock Summary"
    case expiryAlert         = "Expiry Alert"
    case fastMovingItems     = "Fast Moving Items"
    case slowDeadStock       = "Slow / Dead Stock"
    case itemProfitability   = "Item Profitability"
    case customerLedger      = "Customer Ledger"
    case supplierLedger      = "Supplier Ledger"
    case outstandingReceivables = "Outstanding Receivables"
    case outstandingPayables = "Outstanding Payables"
    case gstr1               = "GSTR-1 JSON Export"
    case gstr3b              = "GSTR-3B JSON Export"
    case hsnSummary          = "HSN-wise Summary"
    case inputTaxRegister    = "Input Tax Register (ITC)"
    case outputTaxRegister   = "Output Tax Register"

    var icon: String {
        switch self {
        case .profitAndLoss:        return "chart.bar.doc.horizontal.fill"
        case .salesRegister:        return "doc.text.fill"
        case .purchaseRegister:     return "doc.text.fill"
        case .stockSummary:         return "cube.box.fill"
        case .expiryAlert:          return "exclamationmark.triangle.fill"
        case .fastMovingItems:      return "hare.fill"
        case .slowDeadStock:        return "tortoise.fill"
        case .itemProfitability:    return "indianrupeesign.circle.fill"
        case .customerLedger:       return "person.text.rectangle.fill"
        case .supplierLedger:       return "shippingbox.fill"
        case .outstandingReceivables: return "arrow.down.circle.fill"
        case .outstandingPayables:  return "arrow.up.circle.fill"
        case .gstr1, .gstr3b:       return "doc.badge.gearshape.fill"
        case .hsnSummary:           return "list.bullet.rectangle.fill"
        case .inputTaxRegister:     return "arrow.down.doc.fill"
        case .outputTaxRegister:    return "arrow.up.doc.fill"
        }
    }

    var needsDateRange: Bool {
        switch self {
        case .stockSummary, .expiryAlert, .customerLedger, .supplierLedger,
             .outstandingReceivables, .outstandingPayables:
            return false
        default:
            return true
        }
    }
}

// MARK: - PDF Report Generator

final class ReportGenerator {

    static let shared = ReportGenerator()
    private init() {}

    private var dm: DataModel { AppDataModel.shared.dataModel }

    // MARK: - Public Entry Point

    func generateReport(type: ReportType, from startDate: Date, to endDate: Date) -> URL? {
        if type == .gstr1 || type == .gstr3b {
            return generateJSONReport(type: type, from: startDate, to: endDate)
        }

        let pageWidth: CGFloat = 595.28   // A4 width in points
        let pageHeight: CGFloat = 841.89  // A4 height in points
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2

        let pdfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(type.rawValue.replacingOccurrences(of: " ", with: "_"))_\(dateTag()).pdf")

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )

        let settings = try? dm.db.getSettings()

        let data = renderer.pdfData { context in
            var ctx = PDFContext(
                pdfContext: context,
                pageWidth: pageWidth,
                pageHeight: pageHeight,
                margin: margin,
                contentWidth: contentWidth,
                cursorY: margin,
                settings: settings
            )

            // Begin first page
            context.beginPage()

            // Header
            drawHeader(&ctx, title: type.rawValue, from: startDate, to: endDate)

            // Content
            switch type {
            case .profitAndLoss:
                drawProfitAndLoss(&ctx, from: startDate, to: endDate)
            case .salesRegister:
                drawSalesRegister(&ctx, from: startDate, to: endDate)
            case .purchaseRegister:
                drawPurchaseRegister(&ctx, from: startDate, to: endDate)
            case .stockSummary:
                drawStockSummary(&ctx)
            case .expiryAlert:
                drawExpiryAlert(&ctx)
            case .fastMovingItems:
                drawFastMovingItems(&ctx, from: startDate, to: endDate)
            case .slowDeadStock:
                drawSlowDeadStock(&ctx, from: startDate, to: endDate)
            case .itemProfitability:
                drawItemProfitability(&ctx, from: startDate, to: endDate)
            case .customerLedger:
                drawCustomerLedger(&ctx)
            case .supplierLedger:
                drawSupplierLedger(&ctx)
            case .outstandingReceivables:
                drawOutstandingReceivables(&ctx)
            case .outstandingPayables:
                drawOutstandingPayables(&ctx)
            case .gstr1, .gstr3b:
                break // handled by generateJSONReport before reaching here
            case .hsnSummary:
                drawHSNSummary(&ctx, from: startDate, to: endDate)
            case .inputTaxRegister:
                drawInputTaxRegister(&ctx, from: startDate, to: endDate)
            case .outputTaxRegister:
                drawOutputTaxRegister(&ctx, from: startDate, to: endDate)
            }

            // Footer on last page
            drawFooter(&ctx)
        }

        try? data.write(to: pdfURL)
        return pdfURL
    }

    // MARK: - Drawing Context

    private struct PDFContext {
        let pdfContext: UIGraphicsPDFRendererContext
        let pageWidth: CGFloat
        let pageHeight: CGFloat
        let margin: CGFloat
        let contentWidth: CGFloat
        var cursorY: CGFloat
        let settings: AppSettings?

        mutating func checkPageBreak(needed: CGFloat) {
            if cursorY + needed > pageHeight - margin - 30 {
                pdfContext.beginPage()
                cursorY = margin
            }
        }
    }

    // MARK: - Header & Footer

    private func drawHeader(_ ctx: inout PDFContext, title: String, from: Date, to: Date) {
        let businessName = ctx.settings?.businessName ?? "My Business"
        let gst = ctx.settings?.gstNumber
        let phone = ctx.settings?.businessPhone
        let address = ctx.settings?.businessAddress

        // Business name
        let nameFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: UIColor.black]
        let nameStr = NSAttributedString(string: businessName, attributes: nameAttrs)
        nameStr.draw(at: CGPoint(x: ctx.margin, y: ctx.cursorY))
        ctx.cursorY += 24

        // Contact line
        var contactParts: [String] = []
        if let phone, !phone.isEmpty { contactParts.append(phone) }
        if let gst, !gst.isEmpty { contactParts.append("GST: \(gst)") }
        if let address, !address.isEmpty { 
            contactParts.append(address) 
        } else if let state = ctx.settings?.businessState, !state.isEmpty { 
            contactParts.append(state) 
        }

        if !contactParts.isEmpty {
            let contactFont = UIFont.systemFont(ofSize: 9, weight: .regular)
            let contactAttrs: [NSAttributedString.Key: Any] = [.font: contactFont, .foregroundColor: UIColor.darkGray]
            let contactStr = NSAttributedString(string: contactParts.joined(separator: " • "), attributes: contactAttrs)
            contactStr.draw(at: CGPoint(x: ctx.margin, y: ctx.cursorY))
            ctx.cursorY += 16
        }

        // Divider
        drawLine(&ctx)

        // Report title
        let titleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let onyx = UIColor(named: "Onyx") ?? .black
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: onyx]
        let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
        titleStr.draw(at: CGPoint(x: ctx.margin, y: ctx.cursorY))

        // Date range (right-aligned)
        let df = DateFormatter()
        df.dateStyle = .medium
        let dateStr = "\(df.string(from: from)) — \(df.string(from: to))"
        let dateFont = UIFont.systemFont(ofSize: 9, weight: .regular)
        let dateAttrs: [NSAttributedString.Key: Any] = [.font: dateFont, .foregroundColor: UIColor.gray]
        let dateNS = NSAttributedString(string: dateStr, attributes: dateAttrs)
        let dateSize = dateNS.size()
        dateNS.draw(at: CGPoint(x: ctx.margin + ctx.contentWidth - dateSize.width, y: ctx.cursorY + 3))

        ctx.cursorY += 22
        drawLine(&ctx)
        ctx.cursorY += 8
    }

    private func drawFooter(_ ctx: inout PDFContext) {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        
        let footerText = NSMutableAttributedString(
            string: "Generated by ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: UIColor.lightGray
            ]
        )
        
        let ledgileText = NSAttributedString(
            string: "Ledgile",
            attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: UIColor(named: "Lime Moss") ?? UIColor.systemGreen
            ]
        )
        
        let dateText = NSAttributedString(
            string: " on \(df.string(from: Date()))",
            attributes: [
                .font: UIFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: UIColor.lightGray
            ]
        )
        
        footerText.append(ledgileText)
        footerText.append(dateText)
        
        let size = footerText.size()
        footerText.draw(at: CGPoint(
            x: ctx.margin + (ctx.contentWidth - size.width) / 2,
            y: ctx.pageHeight - ctx.margin
        ))
    }

    // MARK: - Reusable Drawing Helpers

    private func drawLine(_ ctx: inout PDFContext) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: ctx.margin, y: ctx.cursorY))
        path.addLine(to: CGPoint(x: ctx.margin + ctx.contentWidth, y: ctx.cursorY))
        UIColor.lightGray.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        ctx.cursorY += 6
    }

    private func drawSectionTitle(_ ctx: inout PDFContext, _ text: String) {
        ctx.checkPageBreak(needed: 30)
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        NSAttributedString(string: text, attributes: attrs).draw(at: CGPoint(x: ctx.margin, y: ctx.cursorY))
        ctx.cursorY += 20
    }

    private func drawKeyValue(_ ctx: inout PDFContext, key: String, value: String, bold: Bool = false) {
        ctx.checkPageBreak(needed: 18)
        let keyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
        let valFont = UIFont.systemFont(ofSize: 10, weight: bold ? .bold : .medium)

        let keyAttrs: [NSAttributedString.Key: Any] = [.font: keyFont, .foregroundColor: UIColor.darkGray]
        let valAttrs: [NSAttributedString.Key: Any] = [.font: valFont, .foregroundColor: UIColor.black]

        NSAttributedString(string: key, attributes: keyAttrs).draw(at: CGPoint(x: ctx.margin + 8, y: ctx.cursorY))

        let valNS = NSAttributedString(string: value, attributes: valAttrs)
        let valSize = valNS.size()
        valNS.draw(at: CGPoint(x: ctx.margin + ctx.contentWidth - valSize.width, y: ctx.cursorY))

        ctx.cursorY += 18
    }

    /// Draws a table header row
    private func drawTableHeader(_ ctx: inout PDFContext, columns: [(String, CGFloat)]) {
        ctx.checkPageBreak(needed: 24)
        let font = UIFont.systemFont(ofSize: 9, weight: .bold)
        let onyx = UIColor(named: "Onyx") ?? .black
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: onyx]

        // Background
        let rect = CGRect(x: ctx.margin, y: ctx.cursorY, width: ctx.contentWidth, height: 18)
        let beige = UIColor(named: "Beige") ?? .systemGray5
        beige.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 3).fill()

        var x = ctx.margin + 4
        for (title, width) in columns {
            NSAttributedString(string: title, attributes: attrs)
                .draw(in: CGRect(x: x, y: ctx.cursorY + 3, width: width - 4, height: 14))
            x += width
        }

        ctx.cursorY += 20
    }

    /// Draws a table data row
    private func drawTableRow(_ ctx: inout PDFContext, values: [String], columns: [(String, CGFloat)], highlight: Bool = false) {
        ctx.checkPageBreak(needed: 18)
        let font = UIFont.systemFont(ofSize: 9, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]

        if highlight {
            let rect = CGRect(x: ctx.margin, y: ctx.cursorY, width: ctx.contentWidth, height: 16)
            let beige = UIColor(named: "Beige") ?? .systemGray5
            beige.withAlphaComponent(0.4).setFill()
            UIBezierPath(rect: rect).fill()
        }

        var x = ctx.margin + 4
        for (i, (_, width)) in columns.enumerated() {
            let val = i < values.count ? values[i] : ""
            NSAttributedString(string: val, attributes: attrs)
                .draw(in: CGRect(x: x, y: ctx.cursorY + 2, width: width - 4, height: 14))
            x += width
        }

        ctx.cursorY += 16
    }

    /// Draws a "totals" row at the bottom of a table
    private func drawTotalsRow(_ ctx: inout PDFContext, values: [String], columns: [(String, CGFloat)]) {
        ctx.checkPageBreak(needed: 22)
        drawLine(&ctx)
        let font = UIFont.systemFont(ofSize: 9, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]

        var x = ctx.margin + 4
        for (i, (_, width)) in columns.enumerated() {
            let val = i < values.count ? values[i] : ""
            NSAttributedString(string: val, attributes: attrs)
                .draw(in: CGRect(x: x, y: ctx.cursorY + 2, width: width - 4, height: 14))
            x += width
        }
        ctx.cursorY += 20
    }

    private func drawEmptyMessage(_ ctx: inout PDFContext, _ message: String) {
        let font = UIFont.systemFont(ofSize: 11, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.gray]
        NSAttributedString(string: message, attributes: attrs)
            .draw(at: CGPoint(x: ctx.margin + 8, y: ctx.cursorY))
        ctx.cursorY += 20
    }

    // MARK: - Report Content Generators

    // ─────────────────────────────────────────────
    // 1. PROFIT & LOSS
    // ─────────────────────────────────────────────
    private func drawProfitAndLoss(_ ctx: inout PDFContext, from: Date, to: Date) {
        let allTx = (try? dm.db.getTransactions()) ?? []
        let filtered = allTx.filter { $0.date >= from && $0.date <= to }

        let sales = filtered.filter { $0.type == .sale }
        let purchases = filtered.filter { $0.type == .purchase }

        var totalRevenue: Double = 0
        var totalCOGS: Double = 0

        for tx in sales {
            totalRevenue += tx.totalAmount
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                totalCOGS += Double(item.quantity) * (item.costPricePerUnit ?? 0)
            }
        }

        let totalPurchases = purchases.reduce(0.0) { $0 + $1.totalAmount }
        let grossProfit = totalRevenue - totalCOGS
        let marginPct = totalRevenue > 0 ? (grossProfit / totalRevenue) * 100 : 0

        let receivable = CreditStore.shared.getTotalReceivable()
        let payable = CreditStore.shared.getTotalPayable()

        drawSectionTitle(&ctx, "Revenue")
        drawKeyValue(&ctx, key: "Total Sales (\(sales.count) transactions)", value: formatCurrency(totalRevenue))
        ctx.cursorY += 6

        drawSectionTitle(&ctx, "Expenses")
        drawKeyValue(&ctx, key: "Cost of Goods Sold", value: formatCurrency(totalCOGS))
        drawKeyValue(&ctx, key: "Total Purchases (\(purchases.count) transactions)", value: formatCurrency(totalPurchases))
        ctx.cursorY += 6

        drawLine(&ctx)
        drawSectionTitle(&ctx, "Summary")
        drawKeyValue(&ctx, key: "Gross Profit", value: formatCurrency(grossProfit), bold: true)
        drawKeyValue(&ctx, key: "Gross Margin", value: String(format: "%.1f%%", marginPct), bold: true)
        ctx.cursorY += 6

        drawSectionTitle(&ctx, "Credit Position")
        drawKeyValue(&ctx, key: "Total Receivable (You'll Get)", value: formatCurrency(receivable))
        drawKeyValue(&ctx, key: "Total Payable (You'll Pay)", value: formatCurrency(payable))
        drawKeyValue(&ctx, key: "Net Credit Position", value: formatCurrency(receivable - payable), bold: true)

        // Investment
        let investment = dm.getTotalInvestment()
        ctx.cursorY += 6
        drawSectionTitle(&ctx, "Inventory")
        drawKeyValue(&ctx, key: "Current Inventory Value (at cost)", value: formatCurrency(investment))
    }

    // ─────────────────────────────────────────────
    // 2. SALES REGISTER
    // ─────────────────────────────────────────────
    private func drawSalesRegister(_ ctx: inout PDFContext, from: Date, to: Date) {
        let allTx = (try? dm.db.getTransactions()) ?? []
        let sales = allTx.filter { $0.type == .sale && $0.date >= from && $0.date <= to }
            .sorted { $0.date > $1.date }

        let columns: [(String, CGFloat)] = [
            ("Invoice", 70), ("Date", 65), ("Customer", 90), ("Items", 140),
            ("Amount", 60), ("Profit", 60)
        ]

        guard !sales.isEmpty else {
            drawEmptyMessage(&ctx, "No sales found for this period.")
            return
        }

        drawTableHeader(&ctx, columns: columns)

        let df = DateFormatter()
        df.dateFormat = "dd/MM/yy"

        var totalAmount: Double = 0
        var totalProfit: Double = 0

        for (i, tx) in sales.enumerated() {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            let itemSummary = items.prefix(2).map { "\($0.itemName)×\($0.quantity)" }.joined(separator: ", ")
                + (items.count > 2 ? " +\(items.count - 2)" : "")
            let profit = items.reduce(0.0) { $0 + $1.profit }

            totalAmount += tx.totalAmount
            totalProfit += profit

            drawTableRow(&ctx, values: [
                tx.invoiceNumber,
                df.string(from: tx.date),
                tx.customerName ?? "Cash",
                itemSummary,
                formatCurrency(tx.totalAmount),
                formatCurrency(profit)
            ], columns: columns, highlight: i % 2 == 0)
        }

        drawTotalsRow(&ctx, values: [
            "TOTAL", "", "\(sales.count) sales", "",
            formatCurrency(totalAmount), formatCurrency(totalProfit)
        ], columns: columns)
    }

    // ─────────────────────────────────────────────
    // 3. PURCHASE REGISTER
    // ─────────────────────────────────────────────
    private func drawPurchaseRegister(_ ctx: inout PDFContext, from: Date, to: Date) {
        let allTx = (try? dm.db.getTransactions()) ?? []
        let purchases = allTx.filter { $0.type == .purchase && $0.date >= from && $0.date <= to }
            .sorted { $0.date > $1.date }

        let columns: [(String, CGFloat)] = [
            ("Invoice", 70), ("Date", 65), ("Supplier", 120), ("Items", 160), ("Amount", 70)
        ]

        guard !purchases.isEmpty else {
            drawEmptyMessage(&ctx, "No purchases found for this period.")
            return
        }

        drawTableHeader(&ctx, columns: columns)

        let df = DateFormatter()
        df.dateFormat = "dd/MM/yy"

        var totalAmount: Double = 0

        for (i, tx) in purchases.enumerated() {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            let itemSummary = items.prefix(2).map { "\($0.itemName)×\($0.quantity)" }.joined(separator: ", ")
                + (items.count > 2 ? " +\(items.count - 2)" : "")

            totalAmount += tx.totalAmount

            drawTableRow(&ctx, values: [
                tx.invoiceNumber,
                df.string(from: tx.date),
                tx.supplierName ?? "Unknown",
                itemSummary,
                formatCurrency(tx.totalAmount)
            ], columns: columns, highlight: i % 2 == 0)
        }

        drawTotalsRow(&ctx, values: [
            "TOTAL", "", "\(purchases.count) purchases", "",
            formatCurrency(totalAmount)
        ], columns: columns)
    }

    // ─────────────────────────────────────────────
    // 4. STOCK SUMMARY
    // ─────────────────────────────────────────────
    private func drawStockSummary(_ ctx: inout PDFContext) {
        let items = (try? dm.db.getAllItems()) ?? []

        let columns: [(String, CGFloat)] = [
            ("Item", 130), ("Unit", 40), ("Stock", 50), ("Cost ₹", 60),
            ("Sell ₹", 60), ("Value (Cost)", 80), ("Status", 65)
        ]

        guard !items.isEmpty else {
            drawEmptyMessage(&ctx, "No items in inventory.")
            return
        }

        drawTableHeader(&ctx, columns: columns)

        var totalValue: Double = 0

        for (i, item) in items.sorted(by: { $0.name < $1.name }).enumerated() {
            let batches = (try? dm.db.getBatches(for: item.id)) ?? []
            let stockValue = batches.reduce(0.0) { $0 + Double($1.quantityRemaining) * $1.costPrice }
            totalValue += stockValue

            let status: String
            if item.currentStock <= 0 { status = "OUT" }
            else if item.isLowStock { status = "LOW" }
            else { status = "OK" }

            drawTableRow(&ctx, values: [
                item.name,
                item.unit,
                "\(item.currentStock)",
                formatCurrency(item.defaultCostPrice),
                formatCurrency(item.defaultSellingPrice),
                formatCurrency(stockValue),
                status
            ], columns: columns, highlight: i % 2 == 0)
        }

        drawTotalsRow(&ctx, values: [
            "TOTAL", "", "\(items.count) items", "", "", formatCurrency(totalValue), ""
        ], columns: columns)
    }

    // ─────────────────────────────────────────────
    // 5. EXPIRY ALERT
    // ─────────────────────────────────────────────
    private func drawExpiryAlert(_ ctx: inout PDFContext) {
        let alerts = (try? dm.getLowStockAlerts()) ?? []
        let expiryAlerts = (try? dm.getExpiryAlerts()) ?? []

        let columns: [(String, CGFloat)] = [
            ("Item", 130), ("Batch Qty", 65), ("Expiry Date", 80),
            ("Days Left", 70), ("Value (Cost)", 80), ("Severity", 60)
        ]

        guard !expiryAlerts.isEmpty else {
            drawEmptyMessage(&ctx, "No expiry alerts at this time. All items are safe!")
            return
        }

        drawTableHeader(&ctx, columns: columns)

        let df = DateFormatter()
        df.dateFormat = "dd/MM/yy"

        for (i, alert) in expiryAlerts.enumerated() {
            let severityStr: String
            switch alert.severity {
            case .expired:  severityStr = "EXPIRED"
            case .critical: severityStr = "CRITICAL"
            case .warning:  severityStr = "WARNING"
            case .notice:   severityStr = "NOTICE"
            }

            drawTableRow(&ctx, values: [
                alert.itemName,
                "\(alert.quantityRemaining)",
                df.string(from: alert.expiryDate),
                "\(alert.daysUntilExpiry) days",
                "",
                severityStr
            ], columns: columns, highlight: i % 2 == 0)
        }
    }

    // ─────────────────────────────────────────────
    // 6. FAST MOVING ITEMS
    // ─────────────────────────────────────────────
    private func drawFastMovingItems(_ ctx: inout PDFContext, from: Date, to: Date) {
        let allTx = (try? dm.db.getTransactions()) ?? []
        let sales = allTx.filter { $0.type == .sale && $0.date >= from && $0.date <= to }

        var itemStats: [UUID: (name: String, qty: Int, revenue: Double)] = [:]
        for tx in sales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let existing = itemStats[item.itemID] ?? (name: item.itemName, qty: 0, revenue: 0)
                itemStats[item.itemID] = (
                    name: existing.name,
                    qty: existing.qty + item.quantity,
                    revenue: existing.revenue + item.totalRevenue
                )
            }
        }

        let sorted = itemStats.sorted { $0.value.qty > $1.value.qty }
        let top = Array(sorted.prefix(20))

        let columns: [(String, CGFloat)] = [
            ("Rank", 35), ("Item", 160), ("Units Sold", 70), ("Revenue", 80),
            ("Avg/Day", 70), ("Stock Left", 70)
        ]

        guard !top.isEmpty else {
            drawEmptyMessage(&ctx, "No sales data for this period.")
            return
        }

        let dayCount = max(1, Calendar.current.dateComponents([.day], from: from, to: to).day ?? 1)

        drawTableHeader(&ctx, columns: columns)

        for (i, entry) in top.enumerated() {
            let avgPerDay = Double(entry.value.qty) / Double(dayCount)
            let currentItem = try? dm.db.getItem(id: entry.key)
            let stock = currentItem?.currentStock ?? 0

            drawTableRow(&ctx, values: [
                "#\(i + 1)",
                entry.value.name,
                "\(entry.value.qty)",
                formatCurrency(entry.value.revenue),
                String(format: "%.1f", avgPerDay),
                "\(stock)"
            ], columns: columns, highlight: i % 2 == 0)
        }
    }

    // ─────────────────────────────────────────────
    // 7. SLOW / DEAD STOCK
    // ─────────────────────────────────────────────
    private func drawSlowDeadStock(_ ctx: inout PDFContext, from: Date, to: Date) {
        let allItems = (try? dm.db.getAllItems()) ?? []
        let allTx = (try? dm.db.getTransactions()) ?? []
        let sales = allTx.filter { $0.type == .sale && $0.date >= from && $0.date <= to }

        var soldItemIDs = Set<UUID>()
        for tx in sales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items { soldItemIDs.insert(item.itemID) }
        }

        let deadStock = allItems.filter { !soldItemIDs.contains($0.id) && $0.currentStock > 0 }
            .sorted { $0.currentStock > $1.currentStock }

        let columns: [(String, CGFloat)] = [
            ("Item", 160), ("Stock", 60), ("Value (Cost)", 80),
            ("Created", 80), ("Status", 105)
        ]

        guard !deadStock.isEmpty else {
            drawEmptyMessage(&ctx, "Great news! All items with stock had sales in this period. ")
            return
        }

        let df = DateFormatter()
        df.dateFormat = "dd/MM/yy"

        drawTableHeader(&ctx, columns: columns)

        var totalDeadValue: Double = 0
        for (i, item) in deadStock.enumerated() {
            let value = Double(item.currentStock) * item.defaultCostPrice
            totalDeadValue += value

            drawTableRow(&ctx, values: [
                item.name,
                "\(item.currentStock) \(item.unit)",
                formatCurrency(value),
                df.string(from: item.createdDate),
                "No sales in period"
            ], columns: columns, highlight: i % 2 == 0)
        }

        drawTotalsRow(&ctx, values: [
            "\(deadStock.count) dead items", "", formatCurrency(totalDeadValue), "", ""
        ], columns: columns)
    }

    // ─────────────────────────────────────────────
    // 8. ITEM PROFITABILITY
    // ─────────────────────────────────────────────
    private func drawItemProfitability(_ ctx: inout PDFContext, from: Date, to: Date) {
        let allTx = (try? dm.db.getTransactions()) ?? []
        let sales = allTx.filter { $0.type == .sale && $0.date >= from && $0.date <= to }

        var itemStats: [UUID: (name: String, qty: Int, revenue: Double, cogs: Double)] = [:]
        for tx in sales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let existing = itemStats[item.itemID] ?? (name: item.itemName, qty: 0, revenue: 0, cogs: 0)
                itemStats[item.itemID] = (
                    name: existing.name,
                    qty: existing.qty + item.quantity,
                    revenue: existing.revenue + item.totalRevenue,
                    cogs: existing.cogs + item.totalCost
                )
            }
        }

        let sorted = itemStats.sorted { ($0.value.revenue - $0.value.cogs) > ($1.value.revenue - $1.value.cogs) }
        let totalProfit = sorted.reduce(0.0) { $0 + ($1.value.revenue - $1.value.cogs) }

        let columns: [(String, CGFloat)] = [
            ("Item", 120), ("Qty", 40), ("Revenue", 70), ("COGS", 65),
            ("Profit", 65), ("Margin%", 55), ("Contrib%", 60)
        ]

        guard !sorted.isEmpty else {
            drawEmptyMessage(&ctx, "No sales data for this period.")
            return
        }

        drawTableHeader(&ctx, columns: columns)

        var totalRev: Double = 0
        var totalCogs: Double = 0

        for (i, entry) in sorted.enumerated() {
            let profit = entry.value.revenue - entry.value.cogs
            let margin = entry.value.revenue > 0 ? (profit / entry.value.revenue) * 100 : 0
            let contrib = totalProfit > 0 ? (profit / totalProfit) * 100 : 0

            totalRev += entry.value.revenue
            totalCogs += entry.value.cogs

            drawTableRow(&ctx, values: [
                entry.value.name,
                "\(entry.value.qty)",
                formatCurrency(entry.value.revenue),
                formatCurrency(entry.value.cogs),
                formatCurrency(profit),
                String(format: "%.1f%%", margin),
                String(format: "%.1f%%", contrib)
            ], columns: columns, highlight: i % 2 == 0)
        }

        drawTotalsRow(&ctx, values: [
            "TOTAL", "", formatCurrency(totalRev), formatCurrency(totalCogs),
            formatCurrency(totalProfit),
            totalRev > 0 ? String(format: "%.1f%%", (totalProfit / totalRev) * 100) : "0%",
            "100%"
        ], columns: columns)
    }

    // ─────────────────────────────────────────────
    // 9. CUSTOMER LEDGER
    // ─────────────────────────────────────────────
    private func drawCustomerLedger(_ ctx: inout PDFContext) {
        let customers = CreditStore.shared.getAllCustomers()

        guard !customers.isEmpty else {
            drawEmptyMessage(&ctx, "No customers found.")
            return
        }

        let df = DateFormatter()
        df.dateFormat = "dd/MM/yy"

        for customer in customers {
            ctx.checkPageBreak(needed: 60)
            drawSectionTitle(&ctx, "\(customer.name)")
            if let phone = customer.phone { drawKeyValue(&ctx, key: "Phone", value: phone) }

            let payments = CreditStore.shared.getPayments(forCustomer: customer.id)
                .sorted { $0.date < $1.date }

            let columns: [(String, CGFloat)] = [
                ("Date", 70), ("Note", 170), ("Debit (Given)", 85),
                ("Credit (Received)", 90), ("Balance", 70)
            ]

            if payments.isEmpty {
                drawKeyValue(&ctx, key: "No transactions", value: "")
            } else {
                drawTableHeader(&ctx, columns: columns)
                var running: Double = 0
                for (i, p) in payments.enumerated() {
                    let debit: String
                    let credit: String
                    if p.type == .paid {
                        running += p.amount
                        debit = formatCurrency(p.amount)
                        credit = ""
                    } else {
                        running -= p.amount
                        debit = ""
                        credit = formatCurrency(p.amount)
                    }

                    drawTableRow(&ctx, values: [
                        df.string(from: p.date),
                        p.note ?? "-",
                        debit, credit,
                        formatCurrency(running)
                    ], columns: columns, highlight: i % 2 == 0)
                }

                drawTotalsRow(&ctx, values: [
                    "", "Net Balance", "", "",
                    formatCurrency(CreditStore.shared.getNetBalance(forCustomer: customer.id))
                ], columns: columns)
            }

            ctx.cursorY += 10
        }
    }

    // ─────────────────────────────────────────────
    // 10. SUPPLIER LEDGER
    // ─────────────────────────────────────────────
    private func drawSupplierLedger(_ ctx: inout PDFContext) {
        let suppliers = CreditStore.shared.getAllSuppliers()

        guard !suppliers.isEmpty else {
            drawEmptyMessage(&ctx, "No suppliers found.")
            return
        }

        let df = DateFormatter()
        df.dateFormat = "dd/MM/yy"

        for supplier in suppliers {
            ctx.checkPageBreak(needed: 60)
            drawSectionTitle(&ctx, "\(supplier.name)")
            if let phone = supplier.phone { drawKeyValue(&ctx, key: "Phone", value: phone) }

            let payments = CreditStore.shared.getPayments(forSupplier: supplier.id)
                .sorted { $0.date < $1.date }

            let columns: [(String, CGFloat)] = [
                ("Date", 70), ("Note", 170), ("Received", 85),
                ("Paid", 90), ("Balance", 70)
            ]

            if payments.isEmpty {
                drawKeyValue(&ctx, key: "No transactions", value: "")
            } else {
                drawTableHeader(&ctx, columns: columns)
                var running: Double = 0
                for (i, p) in payments.enumerated() {
                    let recv: String
                    let paid: String
                    if p.type == .received {
                        running += p.amount
                        recv = formatCurrency(p.amount)
                        paid = ""
                    } else {
                        running -= p.amount
                        recv = ""
                        paid = formatCurrency(p.amount)
                    }

                    drawTableRow(&ctx, values: [
                        df.string(from: p.date),
                        p.note ?? "-",
                        recv, paid,
                        formatCurrency(running)
                    ], columns: columns, highlight: i % 2 == 0)
                }

                drawTotalsRow(&ctx, values: [
                    "", "Net Balance", "", "",
                    formatCurrency(CreditStore.shared.getNetBalance(forSupplier: supplier.id))
                ], columns: columns)
            }

            ctx.cursorY += 10
        }
    }

    // ─────────────────────────────────────────────
    // 11. OUTSTANDING RECEIVABLES
    // ─────────────────────────────────────────────
    private func drawOutstandingReceivables(_ ctx: inout PDFContext) {
        let customers = CreditStore.shared.getAllCustomers()
        let withBalance = customers.filter { $0.netBalance > 0.01 }
            .sorted { $0.netBalance > $1.netBalance }

        let columns: [(String, CGFloat)] = [
            ("Customer", 160), ("Phone", 110), ("Outstanding", 100), ("Status", 115)
        ]

        guard !withBalance.isEmpty else {
            drawEmptyMessage(&ctx, "No outstanding receivables. All accounts are clear!")
            return
        }

        drawTableHeader(&ctx, columns: columns)

        var total: Double = 0
        for (i, c) in withBalance.enumerated() {
            total += c.netBalance
            let status = c.netBalance > 5000 ? "HIGH" : "NORMAL"

            drawTableRow(&ctx, values: [
                c.name,
                c.phone ?? "-",
                formatCurrency(c.netBalance),
                status
            ], columns: columns, highlight: i % 2 == 0)
        }

        drawTotalsRow(&ctx, values: [
            "\(withBalance.count) customers", "", formatCurrency(total), ""
        ], columns: columns)
    }

    // ─────────────────────────────────────────────
    // 12. OUTSTANDING PAYABLES
    // ─────────────────────────────────────────────
    private func drawOutstandingPayables(_ ctx: inout PDFContext) {
        let suppliers = CreditStore.shared.getAllSuppliers()
        let withBalance = suppliers.filter { $0.netBalance > 0.01 }
            .sorted { $0.netBalance > $1.netBalance }

        let columns: [(String, CGFloat)] = [
            ("Supplier", 160), ("Phone", 110), ("Outstanding", 100), ("Status", 115)
        ]

        guard !withBalance.isEmpty else {
            drawEmptyMessage(&ctx, "No outstanding payables. All supplier accounts are clear!")
            return
        }

        drawTableHeader(&ctx, columns: columns)

        var total: Double = 0
        for (i, s) in withBalance.enumerated() {
            total += s.netBalance
            let status = s.netBalance > 10000 ? "HIGH" : "NORMAL"

            drawTableRow(&ctx, values: [
                s.name,
                s.phone ?? "-",
                formatCurrency(s.netBalance),
                status
            ], columns: columns, highlight: i % 2 == 0)
        }

        drawTotalsRow(&ctx, values: [
            "\(withBalance.count) suppliers", "", formatCurrency(total), ""
        ], columns: columns)
    }

    // ─────────────────────────────────────────────
    // GST REPORTS
    // ─────────────────────────────────────────────
    
    private func drawHSNSummary(_ ctx: inout PDFContext, from: Date, to: Date) {
        let allTx = (try? dm.db.getTransactions()) ?? []
        // Usually HSN summary is required for Outward Supplies (Sales)
        let sales = allTx.filter { $0.type == .sale && $0.date >= from && $0.date <= to }
        
        // Group by HSN and Rate
        struct HSNGroup {
            var hsnCode: String
            var rate: Double
            var taxableValue: Double = 0
            var cgst: Double = 0
            var sgst: Double = 0
            var igst: Double = 0
            var cess: Double = 0
        }
        
        var groups: [String: HSNGroup] = [:]
        
        for tx in sales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let hsn = item.hsnCode ?? "Unknown"
                let rate = item.gstRate ?? 0.0
                let key = "\(hsn)_\(rate)"
                
                var group = groups[key] ?? HSNGroup(hsnCode: hsn, rate: rate)
                group.taxableValue += item.taxableValue ?? 0
                group.cgst += item.cgstAmount ?? 0
                group.sgst += item.sgstAmount ?? 0
                group.igst += item.igstAmount ?? 0
                group.cess += item.cessAmount ?? 0
                groups[key] = group
            }
        }
        
        let sortedGroups = groups.values.sorted { $0.hsnCode < $1.hsnCode }
        
        let columns: [(String, CGFloat)] = [
            ("HSN Code", 80), ("Rate %", 50), ("Taxable Val", 75),
            ("CGST", 60), ("SGST", 60), ("IGST", 60), ("Total Tax", 75)
        ]
        
        guard !sortedGroups.isEmpty else {
            drawEmptyMessage(&ctx, "No HSN data found for sales in this period.")
            return
        }
        
        drawTableHeader(&ctx, columns: columns)
        
        var totTaxable: Double = 0
        var totCGST: Double = 0
        var totSGST: Double = 0
        var totIGST: Double = 0
        var totAllTax: Double = 0
        
        for (i, g) in sortedGroups.enumerated() {
            totTaxable += g.taxableValue
            totCGST += g.cgst
            totSGST += g.sgst
            totIGST += g.igst
            let itemTax = g.cgst + g.sgst + g.igst + g.cess
            totAllTax += itemTax
            
            drawTableRow(&ctx, values: [
                g.hsnCode,
                String(format: "%.1f%%", g.rate),
                formatCurrency(g.taxableValue),
                formatCurrency(g.cgst),
                formatCurrency(g.sgst),
                formatCurrency(g.igst),
                formatCurrency(itemTax)
            ], columns: columns, highlight: i % 2 == 0)
        }
        
        drawTotalsRow(&ctx, values: [
            "TOTAL", "",
            formatCurrency(totTaxable),
            formatCurrency(totCGST),
            formatCurrency(totSGST),
            formatCurrency(totIGST),
            formatCurrency(totAllTax)
        ], columns: columns)
    }

    private func drawInputTaxRegister(_ ctx: inout PDFContext, from: Date, to: Date) {
        let allTx = (try? dm.db.getTransactions()) ?? []
        // Purchases (Input Tax)
        let purchases = allTx.filter { $0.type == .purchase && $0.date >= from && $0.date <= to }
            .sorted { $0.date > $1.date }
        
        let columns: [(String, CGFloat)] = [
            ("Date", 60), ("Invoice", 70), ("Supplier & GSTIN", 100),
            ("Taxable", 65), ("CGST", 50), ("SGST", 50), ("IGST", 50), ("Total", 65)
        ]
        
        guard !purchases.isEmpty else {
            drawEmptyMessage(&ctx, "No purchases found for this period.")
            return
        }
        
        drawTableHeader(&ctx, columns: columns)
        
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yy"
        
        var totTaxable: Double = 0
        var totCGST: Double = 0
        var totSGST: Double = 0
        var totIGST: Double = 0
        var grandTotal: Double = 0
        
        for (i, tx) in purchases.enumerated() {
            let supplierStr = [tx.supplierName ?? "Cash", tx.buyerGSTIN].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            
            let taxable = tx.totalTaxableValue ?? 0
            let cgst = tx.totalCGST ?? 0
            let sgst = tx.totalSGST ?? 0
            let igst = tx.totalIGST ?? 0
            
            totTaxable += taxable
            totCGST += cgst
            totSGST += sgst
            totIGST += igst
            grandTotal += tx.totalAmount
            
            drawTableRow(&ctx, values: [
                df.string(from: tx.date),
                tx.invoiceNumber,
                supplierStr,
                formatCurrency(taxable),
                formatCurrency(cgst),
                formatCurrency(sgst),
                formatCurrency(igst),
                formatCurrency(tx.totalAmount)
            ], columns: columns, highlight: i % 2 == 0)
        }
        
        drawTotalsRow(&ctx, values: [
            "TOTAL", "", "",
            formatCurrency(totTaxable),
            formatCurrency(totCGST),
            formatCurrency(totSGST),
            formatCurrency(totIGST),
            formatCurrency(grandTotal)
        ], columns: columns)
    }

    private func drawOutputTaxRegister(_ ctx: inout PDFContext, from: Date, to: Date) {
        let allTx = (try? dm.db.getTransactions()) ?? []
        // Sales (Output Tax)
        let sales = allTx.filter { $0.type == .sale && $0.date >= from && $0.date <= to }
            .sorted { $0.date > $1.date }
        
        let columns: [(String, CGFloat)] = [
            ("Date", 60), ("Invoice", 70), ("Customer & GSTIN", 100),
            ("Taxable", 65), ("CGST", 50), ("SGST", 50), ("IGST", 50), ("Total", 65)
        ]
        
        guard !sales.isEmpty else {
            drawEmptyMessage(&ctx, "No sales found for this period.")
            return
        }
        
        drawTableHeader(&ctx, columns: columns)
        
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yy"
        
        var totTaxable: Double = 0
        var totCGST: Double = 0
        var totSGST: Double = 0
        var totIGST: Double = 0
        var grandTotal: Double = 0
        
        for (i, tx) in sales.enumerated() {
            let customerStr = [tx.customerName ?? "Cash", tx.buyerGSTIN].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            
            let taxable = tx.totalTaxableValue ?? 0
            let cgst = tx.totalCGST ?? 0
            let sgst = tx.totalSGST ?? 0
            let igst = tx.totalIGST ?? 0
            
            totTaxable += taxable
            totCGST += cgst
            totSGST += sgst
            totIGST += igst
            grandTotal += tx.totalAmount
            
            drawTableRow(&ctx, values: [
                df.string(from: tx.date),
                tx.invoiceNumber,
                customerStr,
                formatCurrency(taxable),
                formatCurrency(cgst),
                formatCurrency(sgst),
                formatCurrency(igst),
                formatCurrency(tx.totalAmount)
            ], columns: columns, highlight: i % 2 == 0)
        }
        
        drawTotalsRow(&ctx, values: [
            "TOTAL", "", "",
            formatCurrency(totTaxable),
            formatCurrency(totCGST),
            formatCurrency(totSGST),
            formatCurrency(totIGST),
            formatCurrency(grandTotal)
        ], columns: columns)
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "₹\(Int(amount))"
    }

    private func dateTag() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmm"
        return df.string(from: Date())
    }

    private func generateJSONReport(type: ReportType, from startDate: Date, to endDate: Date) -> URL? {
        let exporter = GSTReturnExporter(database: dm.db)
        let data: Data

        do {
            switch type {
            case .gstr1:
                data = try exporter.generateGSTR1(from: startDate, to: endDate)
            case .gstr3b:
                data = try exporter.generateGSTR3B(from: startDate, to: endDate)
            default:
                return nil
            }
        } catch {
            print("Failed to generate \(type.rawValue): \(error)")
            return nil
        }

        let fileName = "\(type == .gstr1 ? "GSTR1" : "GSTR3B")_\(dateTag()).json"
        let jsonURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: jsonURL)
            return jsonURL
        } catch {
            print("Failed to write JSON: \(error)")
            return nil
        }
    }
}

// MARK: - QLPreviewController Helper

/// A small helper so any ViewController can preview a PDF
class PDFPreviewItem: NSObject, QLPreviewItem {
    let url: URL
    let name: String

    init(url: URL, name: String) {
        self.url = url
        self.name = name
    }

    var previewItemURL: URL? { url }
    var previewItemTitle: String? { name }
}

class PDFPreviewDataSource: NSObject, QLPreviewControllerDataSource {
    let item: PDFPreviewItem

    init(item: PDFPreviewItem) {
        self.item = item
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { item }
}
