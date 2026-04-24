//  ManualSalesEntry

import Foundation

enum PurchaseSection: Int, CaseIterable {

    case supplier      // Supplier name, phone, invoice ref
    case items          // Item selection, unit
    case pricing       // Quantity, cost price, selling price

    var title: String {
        switch self {
        case .supplier:
            return "Supplier Details"
        case .items:
            return "Item Details"
        case .pricing:
            return "Pricing"
        }
    }
}
