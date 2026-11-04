import Foundation
import AppIntents

public struct UdhaarSummaryIntent: AppIntent {
    public static var title: LocalizedStringResource = "Udhaar summary"
    public static var description = IntentDescription("Shows total customer receivables and supplier payables.")
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let snapshot = try await LedgerQueryService.shared.udhaar()
            return .result(dialog: ShopIntentDialogs.udhaar(snapshot))
        } catch {
            return .result(dialog: ShopIntentDialogs.databaseError)
        }
    }
}
