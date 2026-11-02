import Foundation

nonisolated struct LedgerQueryService: Sendable {
    static let shared = LedgerQueryService()

    private let dataModel: DataModel
    private let creditStore: CreditStore

    init(
        dataModel: DataModel = AppDataModel.shared.dataModel,
        creditStore: CreditStore = .shared
    ) {
        self.dataModel = dataModel
        self.creditStore = creditStore
    }

    func todaySummary() async throws -> TodaySummarySnapshot {
        let dataModel = dataModel
        let creditStore = creditStore
        return try await LedgerIO.runAsync {
            let stats = dataModel.getTodayStats()
            return TodaySummarySnapshot(
                revenue: stats.revenue,
                profit: stats.profit,
                saleCount: stats.saleCount,
                itemsSold: stats.itemsSold,
                receivable: creditStore.getTotalReceivable(),
                payable: creditStore.getTotalPayable()
            )
        }
    }

    func lowStock(limit: Int = 25) async throws -> LowStockSnapshot {
        let dataModel = dataModel
        return try await LedgerIO.runAsync {
            let alerts = try dataModel.getLowStockAlerts()
                .sorted { $0.currentStock < $1.currentStock }
            let items = alerts.prefix(max(1, limit)).map {
                LowStockItemSnapshot(
                    id: $0.id,
                    name: $0.itemName,
                    stock: $0.currentStock,
                    unit: $0.unit,
                    threshold: $0.threshold
                )
            }
            return LowStockSnapshot(items: Array(items), totalCount: alerts.count)
        }
    }

    func udhaar(limit: Int = 5) async throws -> UdhaarSnapshot {
        let creditStore = creditStore
        return try await LedgerIO.runAsync {
            let customers = creditStore.getAllCustomers()
                .map { ($0.id, $0.name, $0.netBalance) }
                .filter { $0.2 > 0.5 }
                .sorted { $0.2 > $1.2 }
                .prefix(max(1, limit))
                .map { PartyBalanceLine(id: "customer:\($0.0.uuidString)", name: $0.1, balance: $0.2) }

            let suppliers = creditStore.getAllSuppliers()
                .map { ($0.id, $0.name, $0.netBalance) }
                .filter { $0.2 > 0.5 }
                .sorted { $0.2 > $1.2 }
                .prefix(max(1, limit))
                .map { PartyBalanceLine(id: "supplier:\($0.0.uuidString)", name: $0.1, balance: $0.2) }

            return UdhaarSnapshot(
                receivable: creditStore.getTotalReceivable(),
                payable: creditStore.getTotalPayable(),
                topCustomers: Array(customers),
                topSuppliers: Array(suppliers)
            )
        }
    }

    func partyBalance(id: String) async throws -> PartyBalanceSnapshot {
        let creditStore = creditStore
        return try await LedgerIO.runAsync {
            guard let party = Self.parsePartyID(id) else {
                throw LedgerQueryError.partyNotFound
            }

            switch party.kind {
            case .customer:
                guard let customer = creditStore.getCustomer(id: party.uuid) else {
                    throw LedgerQueryError.partyNotFound
                }
                return PartyBalanceSnapshot(
                    party: PartySnapshot(
                        id: id,
                        name: customer.name,
                        kind: .customer
                    ),
                    balance: customer.netBalance
                )
            case .supplier:
                guard let supplier = creditStore.getSupplier(id: party.uuid) else {
                    throw LedgerQueryError.partyNotFound
                }
                return PartyBalanceSnapshot(
                    party: PartySnapshot(
                        id: id,
                        name: supplier.name,
                        kind: .supplier
                    ),
                    balance: supplier.netBalance
                )
            }
        }
    }

    func recentTransactions(limit: Int = 5) async throws -> RecentTransactionsSnapshot {
        let dataModel = dataModel
        return try await LedgerIO.runAsync {
            let recent = dataModel.getRecentTransactions(limit: max(1, limit), type: .sale)
            let snapshots = recent.map { entry in
                RecentTransactionSnapshot(
                    id: entry.transaction.id,
                    invoiceNumber: entry.transaction.invoiceNumber,
                    date: entry.transaction.date,
                    amount: entry.transaction.totalAmount,
                    partyName: entry.transaction.customerName,
                    summary: entry.itemsSummary,
                    isSale: entry.transaction.type == .sale
                )
            }
            return RecentTransactionsSnapshot(
                transactions: snapshots,
                totalCount: snapshots.count
            )
        }
    }

    func parties(matching query: String, limit: Int = 20) async throws -> [PartySnapshot] {
        let creditStore = creditStore
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await LedgerIO.runAsync {
            let customers = creditStore.getAllCustomers()
                .filter { needle.isEmpty || $0.name.localizedStandardContains(needle) }
                .map { PartySnapshot(id: "customer:\($0.id.uuidString)", name: $0.name, kind: .customer) }
            let suppliers = creditStore.getAllSuppliers()
                .filter { needle.isEmpty || $0.name.localizedStandardContains(needle) }
                .map { PartySnapshot(id: "supplier:\($0.id.uuidString)", name: $0.name, kind: .supplier) }
            return Array((customers + suppliers).prefix(max(1, limit)))
        }
    }

    func suggestedParties(limit: Int = 12) async throws -> [PartySnapshot] {
        let creditStore = creditStore
        return try await LedgerIO.runAsync {
            let customers = creditStore.getAllCustomers().map {
                PartySnapshot(id: "customer:\($0.id.uuidString)", name: $0.name, kind: .customer)
            }
            let suppliers = creditStore.getAllSuppliers().map {
                PartySnapshot(id: "supplier:\($0.id.uuidString)", name: $0.name, kind: .supplier)
            }
            let all = customers + suppliers
            return Array(all.prefix(max(1, limit)))
        }
    }

    func parties(for ids: [String]) async throws -> [PartySnapshot] {
        let creditStore = creditStore
        return try await LedgerIO.runAsync {
            ids.compactMap { id in
                guard let parsed = Self.parsePartyID(id) else { return nil }
                switch parsed.kind {
                case .customer:
                    guard let customer = creditStore.getCustomer(id: parsed.uuid) else { return nil }
                    return PartySnapshot(id: id, name: customer.name, kind: .customer)
                case .supplier:
                    guard let supplier = creditStore.getSupplier(id: parsed.uuid) else { return nil }
                    return PartySnapshot(id: id, name: supplier.name, kind: .supplier)
                }
            }
        }
    }

    func expiry(limit: Int = 25) async throws -> ExpirySnapshot {
        let dataModel = dataModel
        return try await LedgerIO.runAsync {
            let items = try dataModel.getAllItems()
            let units = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.unit) })
            let alerts = try dataModel.getExpiryAlerts()
                .sorted {
                    if $0.severity == $1.severity {
                        return $0.daysUntilExpiry < $1.daysUntilExpiry
                    }
                    return $0.severity.rawValue < $1.severity.rawValue
                }

            let snapshots = alerts.prefix(max(1, limit)).map {
                ExpiryItemSnapshot(
                    id: $0.batchID,
                    name: $0.itemName,
                    quantity: $0.quantityRemaining,
                    unit: units[$0.itemID] ?? "",
                    daysUntilExpiry: $0.daysUntilExpiry,
                    urgency: ExpiryUrgency(rawValue: $0.severity.rawValue) ?? .notice
                )
            }
            return ExpirySnapshot(items: Array(snapshots), totalCount: alerts.count)
        }
    }

    private static func parsePartyID(_ id: String) -> (kind: PartyKind, uuid: UUID)? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let kind = PartyKind(rawValue: parts[0]),
              let uuid = UUID(uuidString: parts[1]) else {
            return nil
        }
        return (kind, uuid)
    }
}
