import Foundation

struct BillingDetails: Codable {
    var customerName: String
    var items: [TransactionItem]
    var discount: Double
    var adjustment: Double
    var descriptionText: String?
    var invoiceDate: Date
    var invoiceNumber: String
    var transactionType: TransactionType?
    var isCreditSale: Bool = false

    // GST fields
    var sellerGSTIN: String? = nil
    var sellerState: String? = nil
    var buyerGSTIN: String? = nil
    var buyerState: String? = nil
    var placeOfSupply: String? = nil
    var isInterState: Bool = false
    var isCompositionScheme: Bool = false
    var taxBreakup: GSTBreakup? = nil       // nil if GST not registered
}
