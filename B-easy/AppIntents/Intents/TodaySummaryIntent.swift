import Foundation
import AppIntents

public struct TodaySummaryIntent: AppIntent {
    public static var title: LocalizedStringResource = "Today's summary"
    public static var description = IntentDescription("Shows today's sales, profit, bills, and pending udhaar.")
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let snapshot = try await LedgerQueryService.shared.todaySummary()
            return .result(dialog: ShopIntentDialogs.todaySummary(snapshot))
        } catch {
            return .result(dialog: ShopIntentDialogs.databaseError)
        }
    }
}
