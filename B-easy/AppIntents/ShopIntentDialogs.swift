import Foundation
import AppIntents

nonisolated enum ShopIntentDialogs {
    static var databaseError: IntentDialog {
        IntentDialog("I couldn't read your books. Open Beasy once and try again.")
    }

    static var noRecentTransactions: IntentDialog {
        IntentDialog("No recent bills recorded.")
    }

    static var queryNotUnderstood: IntentDialog {
        IntentDialog("You can ask Beasy about today's sales, credit summary, low stock, expiry alerts, or recent bills.")
    }

    static var partyNotFound: IntentDialog {
        IntentDialog("I couldn't find that party.")
    }

    static var noLowStock: IntentDialog {
        IntentDialog("No low-stock items right now.")
    }

    static var noExpiry: IntentDialog {
        IntentDialog("No expiry alerts right now.")
    }

    static func todaySummary(_ snapshot: TodaySummarySnapshot) -> IntentDialog {
        guard snapshot.saleCount > 0 else {
            return IntentDialog(stringLiteral: String(
                localized: "intent.today.no_sales",
                    defaultValue: "No sales recorded today yet. Pending credit is \(SpokenFormatting.amount(snapshot.receivable)) rupees.",
                    locale: SpokenFormatting.locale
                )
            )
        }

        return IntentDialog(stringLiteral: String(
                localized: "intent.today.summary",
                defaultValue: "Today: \(SpokenFormatting.amount(snapshot.revenue)) rupees sales, \(SpokenFormatting.amount(snapshot.profit)) rupees profit, \(SpokenFormatting.count(snapshot.saleCount)) bills, \(SpokenFormatting.amount(snapshot.itemsSold)) items sold, and \(SpokenFormatting.amount(snapshot.receivable)) rupees credit pending.",
                locale: SpokenFormatting.locale
            )
        )
    }

    static func lowStock(_ snapshot: LowStockSnapshot) -> IntentDialog {
        guard !snapshot.items.isEmpty else { return noLowStock }

        let header = String(
            localized: "intent.low_stock.header",
            defaultValue: "Low stock:",
            locale: SpokenFormatting.locale
        )
        let lines = snapshot.items.prefix(5).map { item in
            String(
                localized: "intent.low_stock.line",
                defaultValue: "\(item.name): \(SpokenFormatting.amount(item.stock)) \(SpokenFormatting.unit(item.unit)) left, threshold \(SpokenFormatting.amount(item.threshold)).",
                locale: SpokenFormatting.locale
            )
        }
        var text = ([header] + lines).joined(separator: "\n")
        if snapshot.totalCount > snapshot.items.prefix(5).count {
            let remaining = snapshot.totalCount - snapshot.items.prefix(5).count
            text += "\n" + String(
                localized: "intent.low_stock.more",
                defaultValue: "and \(SpokenFormatting.count(remaining)) more.",
                locale: SpokenFormatting.locale
            )
        }
        return IntentDialog(stringLiteral: text)
    }

    static func udhaar(_ snapshot: UdhaarSnapshot) -> IntentDialog {
        var blocks: [String] = []

        if !snapshot.topCustomers.isEmpty {
            let header = String(
                localized: "intent.udhaar.receivables_header",
                defaultValue: "Top credit:",
                locale: SpokenFormatting.locale
            )
            let lines = snapshot.topCustomers.map { party in
                String(
                    localized: "intent.udhaar.line",
                    defaultValue: "\(party.name): \(SpokenFormatting.amount(party.balance)) rupees",
                    locale: SpokenFormatting.locale
                )
            }
            blocks.append(([header] + lines).joined(separator: "\n"))
        }

        if !snapshot.topSuppliers.isEmpty {
            let header = String(
                localized: "intent.udhaar.payables_header",
                defaultValue: "Top payables:",
                locale: SpokenFormatting.locale
            )
            let lines = snapshot.topSuppliers.map { party in
                String(
                    localized: "intent.udhaar.line",
                    defaultValue: "\(party.name): \(SpokenFormatting.amount(party.balance)) rupees",
                    locale: SpokenFormatting.locale
                )
            }
            blocks.append(([header] + lines).joined(separator: "\n"))
        }

        let summary = String(
            localized: "intent.udhaar.summary",
            defaultValue: "Customers owe you \(SpokenFormatting.amount(snapshot.receivable)) rupees. You owe suppliers \(SpokenFormatting.amount(snapshot.payable)) rupees.",
            locale: SpokenFormatting.locale
        )
        return IntentDialog(stringLiteral: ([summary] + blocks).joined(separator: "\n\n"))
    }

    static func partyBalance(_ snapshot: PartyBalanceSnapshot) -> IntentDialog {
        let name = snapshot.party.name
        let amount = SpokenFormatting.amount(abs(snapshot.balance))

        switch (snapshot.party.kind, snapshot.balance) {
        case (.customer, let balance) where balance > 0.5:
            return IntentDialog(stringLiteral: String(
                    localized: "intent.party.customer_owes",
                    defaultValue: "\(name) owes you \(amount) rupees.",
                    locale: SpokenFormatting.locale
                )
            )
        case (.customer, let balance) where balance < -0.5:
            return IntentDialog(stringLiteral: String(
                    localized: "intent.party.customer_advance",
                    defaultValue: "\(name) has an advance of \(amount) rupees.",
                    locale: SpokenFormatting.locale
                )
            )
        case (.supplier, let balance) where balance > 0.5:
            return IntentDialog(stringLiteral: String(
                    localized: "intent.party.supplier_owes",
                    defaultValue: "You owe \(name) \(amount) rupees.",
                    locale: SpokenFormatting.locale
                )
            )
        case (.supplier, let balance) where balance < -0.5:
            return IntentDialog(stringLiteral: String(
                    localized: "intent.party.supplier_advance",
                    defaultValue: "\(name) has an advance of \(amount) rupees with you.",
                    locale: SpokenFormatting.locale
                )
            )
        default:
            return IntentDialog(stringLiteral: String(
                    localized: "intent.party.settled",
                    defaultValue: "\(name)'s account is settled.",
                    locale: SpokenFormatting.locale
                )
            )
        }
    }

    static func recentTransactions(_ snapshot: RecentTransactionsSnapshot) -> IntentDialog {
        guard !snapshot.transactions.isEmpty else { return noRecentTransactions }

        let count = snapshot.transactions.count
        let header = String(
            localized: "intent.recent_transactions.header",
            defaultValue: "Last \(SpokenFormatting.count(count)) bills:",
            locale: SpokenFormatting.locale
        )

        let lines = snapshot.transactions.map { tx -> String in
            let amount = SpokenFormatting.amount(tx.amount)
            if let party = tx.partyName, !party.isEmpty {
                return String(
                    localized: "intent.recent_transactions.line_with_party",
                    defaultValue: "Bill \(tx.invoiceNumber) for \(amount) rupees to \(party) (\(tx.summary)).",
                    locale: SpokenFormatting.locale
                )
            } else {
                return String(
                    localized: "intent.recent_transactions.line",
                    defaultValue: "Bill \(tx.invoiceNumber) for \(amount) rupees (\(tx.summary)).",
                    locale: SpokenFormatting.locale
                )
            }
        }

        let text = ([header] + lines).joined(separator: "\n")
        return IntentDialog(stringLiteral: text)
    }

    static func expiry(_ snapshot: ExpirySnapshot) -> IntentDialog {
        guard !snapshot.items.isEmpty else { return noExpiry }

        let header = String(
            localized: "intent.expiry.header",
            defaultValue: "Expiry alerts:",
            locale: SpokenFormatting.locale
        )
        let lines = snapshot.items.prefix(5).map { item -> String in
            let quantity = "\(SpokenFormatting.amount(item.quantity)) \(SpokenFormatting.unit(item.unit))"
            if item.daysUntilExpiry < 0 {
                return String(
                    localized: "intent.expiry.expired_line",
                    defaultValue: "\(item.name): \(quantity) expired.",
                    locale: SpokenFormatting.locale
                )
            }
            if item.daysUntilExpiry == 0 {
                return String(
                    localized: "intent.expiry.today_line",
                    defaultValue: "\(item.name): \(quantity) expires today.",
                    locale: SpokenFormatting.locale
                )
            }
            return String(
                localized: "intent.expiry.days_line",
                defaultValue: "\(item.name): \(quantity) expires in \(SpokenFormatting.count(item.daysUntilExpiry)) days.",
                locale: SpokenFormatting.locale
            )
        }

        var text = ([header] + lines).joined(separator: "\n")
        if snapshot.totalCount > snapshot.items.prefix(5).count {
            let remaining = snapshot.totalCount - snapshot.items.prefix(5).count
            text += "\n" + String(
                localized: "intent.expiry.more",
                defaultValue: "and \(SpokenFormatting.count(remaining)) more.",
                locale: SpokenFormatting.locale
            )
        }
        return IntentDialog(stringLiteral: text)
    }
}
