import Foundation
import AppIntents

public struct AskShopIntent: AppIntent {
    public static var title: LocalizedStringResource = "Ask Beasy"
    public static var description = IntentDescription("Ask anything about today's sales, udhaar, low stock, expiry, or recent bills in Hindi, Hinglish, or English.")
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(
        title: "Question",
        description: "What would you like to know?",
        requestValueDialog: IntentDialog("What would you like to know about your shop?")
    )
    public var query: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Ask Beasy \(\.$query)")
    }

    public init() {}

    public init(query: String) {
        self.query = query
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let match = ShopContextualEmbeddingMatcher.shared.match(query: query)
        do {
            switch match {
            case .todaySummary:
                let snapshot = try await LedgerQueryService.shared.todaySummary()
                return .result(dialog: ShopIntentDialogs.todaySummary(snapshot))

            case .udhaarSummary:
                let snapshot = try await LedgerQueryService.shared.udhaar()
                return .result(dialog: ShopIntentDialogs.udhaar(snapshot))

            case .lowStock:
                let snapshot = try await LedgerQueryService.shared.lowStock()
                return .result(dialog: ShopIntentDialogs.lowStock(snapshot))

            case .expiry:
                let snapshot = try await LedgerQueryService.shared.expiry()
                return .result(dialog: ShopIntentDialogs.expiry(snapshot))

            case .recentTransactions:
                let snapshot = try await LedgerQueryService.shared.recentTransactions()
                return .result(dialog: ShopIntentDialogs.recentTransactions(snapshot))

            case .partyBalance(let partyName):
                if let name = partyName, !name.isEmpty {
                    let parties = try await LedgerQueryService.shared.parties(matching: name)
                    if let first = parties.first {
                        let snapshot = try await LedgerQueryService.shared.partyBalance(id: first.id)
                        return .result(dialog: ShopIntentDialogs.partyBalance(snapshot))
                    } else {
                        return .result(dialog: IntentDialog("I couldn't find a party named \(name)."))
                    }
                } else {
                    let snapshot = try await LedgerQueryService.shared.udhaar()
                    return .result(dialog: ShopIntentDialogs.udhaar(snapshot))
                }

            case .unknown:
                return .result(dialog: ShopIntentDialogs.queryNotUnderstood)
            }
        } catch {
            return .result(dialog: ShopIntentDialogs.databaseError)
        }
    }
}
