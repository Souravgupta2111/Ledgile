import Foundation
import AppIntents

public struct PartyBalanceIntent: AppIntent {
    public static var title: LocalizedStringResource = "Party balance"
    public static var description = IntentDescription("Shows how much a customer owes you or how much you owe a supplier.")
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
    public static var parameterSummary: some ParameterSummary {
        Summary("Get balance for \(\.$party)")
    }

    @Parameter(title: "Party", description: "Customer or supplier name")
    public var party: PartyEntity

    public init() {}

    public init(party: PartyEntity) {
        self.party = party
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let snapshot = try await LedgerQueryService.shared.partyBalance(id: party.id)
            return .result(dialog: ShopIntentDialogs.partyBalance(snapshot))
        } catch LedgerQueryError.partyNotFound {
            return .result(dialog: ShopIntentDialogs.partyNotFound)
        } catch {
            return .result(dialog: ShopIntentDialogs.databaseError)
        }
    }
}
