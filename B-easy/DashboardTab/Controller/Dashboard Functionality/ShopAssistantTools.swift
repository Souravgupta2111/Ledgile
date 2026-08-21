#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, *)
@Generable
enum ShopIntentKind {
    case partyLedger
    case inventory
    case shopSnapshot
    case topSellers
    case writeRefused
    case smallTalk
    case offTopic
}

@available(iOS 26.0, *)
@Generable
struct ShopQuestion {
    var kind: ShopIntentKind
    @Guide(description: "Customer or supplier name if the question is about udhaar or their bills")
    var partyName: String?
    @Guide(description: "How many months back. pichle 3 mahine = 3. Default 3 when a period is implied.")
    var months: Int?
    @Guide(description: "Product name if the question is about stock")
    var productQuery: String?
}
#endif
