import Foundation
import AppIntents

public struct RecentTransactionsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Recent bills"
    public static var description = IntentDescription("Shows your latest sales bills and transactions.")
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let snapshot = try await LedgerQueryService.shared.recentTransactions()
            return .result(dialog: ShopIntentDialogs.recentTransactions(snapshot))
        } catch {
            return .result(dialog: ShopIntentDialogs.databaseError)
        }
    }
}
