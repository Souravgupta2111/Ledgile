import Foundation
import AppIntents

public struct LowStockIntent: AppIntent {
    public static var title: LocalizedStringResource = "Low stock"
    public static var description = IntentDescription("Shows items running low on stock.")
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let snapshot = try await LedgerQueryService.shared.lowStock()
            return .result(dialog: ShopIntentDialogs.lowStock(snapshot))
        } catch {
            return .result(dialog: ShopIntentDialogs.databaseError)
        }
    }
}
