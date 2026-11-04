import Foundation
import AppIntents

public struct ExpiryIntent: AppIntent {
    public static var title: LocalizedStringResource = "Expiry alerts"
    public static var description = IntentDescription("Shows items that have expired or are expiring soon.")
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let snapshot = try await LedgerQueryService.shared.expiry()
            return .result(dialog: ShopIntentDialogs.expiry(snapshot))
        } catch {
            return .result(dialog: ShopIntentDialogs.databaseError)
        }
    }
}
