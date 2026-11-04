import Foundation

nonisolated struct TodaySummarySnapshot: Sendable {
    let revenue: Double
    let profit: Double
    let saleCount: Int
    let itemsSold: Double
    let receivable: Double
    let payable: Double
}

nonisolated struct LowStockItemSnapshot: Identifiable, Sendable {
    let id: UUID
    let name: String
    let stock: Double
    let unit: String
    let threshold: Double
}

nonisolated struct LowStockSnapshot: Sendable {
    let items: [LowStockItemSnapshot]
    let totalCount: Int
}

public nonisolated enum PartyKind: String, Sendable {
    case customer
    case supplier
}

public nonisolated struct PartySnapshot: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: PartyKind

    public init(id: String, name: String, kind: PartyKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

nonisolated struct PartyBalanceLine: Identifiable, Sendable {
    let id: String
    let name: String
    let balance: Double
}

nonisolated struct UdhaarSnapshot: Sendable {
    let receivable: Double
    let payable: Double
    let topCustomers: [PartyBalanceLine]
    let topSuppliers: [PartyBalanceLine]
}

nonisolated struct PartyBalanceSnapshot: Sendable {
    let party: PartySnapshot
    let balance: Double
}

nonisolated struct RecentTransactionSnapshot: Identifiable, Sendable {
    let id: UUID
    let invoiceNumber: String
    let date: Date
    let amount: Double
    let partyName: String?
    let summary: String
    let isSale: Bool
}

nonisolated struct RecentTransactionsSnapshot: Sendable {
    let transactions: [RecentTransactionSnapshot]
    let totalCount: Int
}

nonisolated enum ExpiryUrgency: Int, Sendable, Comparable {
    case expired = 0
    case critical = 1
    case warning = 2
    case notice = 3

    static func < (lhs: ExpiryUrgency, rhs: ExpiryUrgency) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct ExpiryItemSnapshot: Identifiable, Sendable {
    let id: UUID
    let name: String
    let quantity: Double
    let unit: String
    let daysUntilExpiry: Int
    let urgency: ExpiryUrgency
}

nonisolated struct ExpirySnapshot: Sendable {
    let items: [ExpiryItemSnapshot]
    let totalCount: Int
}

public nonisolated enum LedgerQueryError: Error, Sendable {
    case itemNotFound
    case partyNotFound
    case unavailable
}
