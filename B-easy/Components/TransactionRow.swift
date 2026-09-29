import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction

    let itemsSummary: String

    var amountColor: Color = .brand

    var action: (() -> Void)? = nil

    private var title: String {
        if transaction.type == .sale {
            if let name = transaction.customerName, !name.isEmpty {
                return name
            }
            return "Cash Sale"
        }
        return "Purchase"
    }

    private var subtitle: String {
        itemsSummary.isEmpty ? "Unknown" : itemsSummary
    }

    private var icon: String {
        transaction.type == .sale ? "cart" : "shippingbox"
    }

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        ItemRow(
            title: title,
            subtitle: subtitle,
            amount: Money.compact(transaction.totalAmount),
            systemImage: icon,
            amountColor: amountColor,
            showsChevron: action != nil
        )
    }
}
