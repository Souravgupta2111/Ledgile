import Foundation
import AppIntents

public struct PartyEntity: AppEntity, Sendable {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Party"
    public static var defaultQuery = PartyEntityQuery()

    public let id: String
    public let name: String
    public let kind: PartyKind

    public init(id: String, name: String, kind: PartyKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    public init(snapshot: PartySnapshot) {
        self.id = snapshot.id
        self.name = snapshot.name
        self.kind = snapshot.kind
    }

    public var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource = kind == .customer ? "Customer" : "Supplier"
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: subtitle
        )
    }
}

public struct PartyEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [PartyEntity] {
        try await LedgerQueryService.shared.parties(for: identifiers).map(PartyEntity.init(snapshot:))
    }

    public func entities(matching string: String) async throws -> [PartyEntity] {
        try await LedgerQueryService.shared.parties(matching: string).map(PartyEntity.init(snapshot:))
    }

    public func suggestedEntities() async throws -> [PartyEntity] {
        try await LedgerQueryService.shared.suggestedParties().map(PartyEntity.init(snapshot:))
    }
}
