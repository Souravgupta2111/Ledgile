//  ManualSalesEntry
import Foundation

enum SalesSection: Int, CaseIterable {
    case customer
    case items
    case summary
    case transactionTypeSlider
    case invoice
    var title: String {
        switch self {
        case .customer: return "Customer Details"
        case .items: return "Item Details"
        case .summary: return "Summary"
        case .transactionTypeSlider: return "Payment Type"
        case .invoice: return "Invoice Details"
        }
    }
}
