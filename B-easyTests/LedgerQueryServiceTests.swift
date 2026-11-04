import XCTest
@testable import B_easy

@MainActor
final class LedgerQueryServiceTests: XCTestCase {

    private func makeService() throws -> (LedgerQueryService, SQLiteDatabase, CreditStore) {
        let db = SQLiteDatabase(path: ":memory:")
        var settings = try db.getSettings()
        settings.isGSTRegistered = false
        try db.updateSettings(settings)

        let model = DataModel(database: db)
        let creditStore = CreditStore(database: db)
        return (LedgerQueryService(dataModel: model, creditStore: creditStore), db, creditStore)
    }

    private func makeItem(
        name: String,
        stock: Double,
        threshold: Double = 0,
        sellingPrice: Double = 20,
        costPrice: Double = 10,
        barcode: String? = nil,
        unit: String = "kg"
    ) -> Item {
        Item(
            id: UUID(),
            name: name,
            unit: unit,
            barcode: barcode,
            defaultCostPrice: costPrice,
            defaultSellingPrice: sellingPrice,
            defaultPriceUpdatedAt: Date(),
            lowStockThreshold: threshold,
            currentStock: stock,
            createdDate: Date(),
            lastRestockDate: nil,
            isActive: true
        )
    }

    private func insertBatch(
        for item: Item,
        quantity: Double,
        expiryDate: Date? = nil,
        into db: SQLiteDatabase
    ) throws {
        try db.insertBatch(
            ItemBatch(
                id: UUID(),
                itemID: item.id,
                purchaseTransactionID: UUID(),
                quantityPurchased: quantity,
                quantityRemaining: quantity,
                costPrice: item.defaultCostPrice,
                sellingPrice: item.defaultSellingPrice,
                expiryDate: expiryDate,
                receivedDate: Date()
            )
        )
    }

    func testTodaySummaryIncludesSalesAndUdhaar() async throws {
        let (service, db, creditStore) = try makeService()
        let item = makeItem(name: "Aloo", stock: 5)
        try db.insertItem(item)
        try insertBatch(for: item, quantity: 5, into: db)

        let model = DataModel(database: db)
        _ = try model.addMultiItemSale(
            items: [(itemID: item.id, quantity: 1, sellingPrice: 20)],
            customerName: nil,
            customerPhone: nil
        )
        creditStore.addCreditSale(amount: 50, customerName: "Ramesh")

        let snapshot = try await service.todaySummary()

        XCTAssertEqual(snapshot.revenue, 20, accuracy: 0.001)
        XCTAssertEqual(snapshot.profit, 10, accuracy: 0.001)
        XCTAssertEqual(snapshot.saleCount, 1)
        XCTAssertEqual(snapshot.itemsSold, 1, accuracy: 0.001)
        XCTAssertEqual(snapshot.receivable, 50, accuracy: 0.001)
        XCTAssertEqual(snapshot.payable, 0, accuracy: 0.001)
    }

    func testLowStockIsSortedAndCounted() async throws {
        let (service, db, _) = try makeService()
        try db.insertItem(makeItem(name: "Low Atta", stock: 1, threshold: 2))
        try db.insertItem(makeItem(name: "Zero Sugar", stock: 0, threshold: 1))
        try db.insertItem(makeItem(name: "Healthy Rice", stock: 8, threshold: 2))

        let snapshot = try await service.lowStock()

        XCTAssertEqual(snapshot.totalCount, 2)
        XCTAssertEqual(snapshot.items.map(\.name), ["Zero Sugar", "Low Atta"])
    }

    func testUdhaarReturnsTopCustomersAndSuppliers() async throws {
        let (service, _, creditStore) = try makeService()
        creditStore.addCreditSale(amount: 50, customerName: "Ramesh")
        creditStore.addCreditSale(amount: 90, customerName: "Suresh")
        creditStore.addCreditPurchase(amount: 30, supplierName: "Sharma Traders")

        let snapshot = try await service.udhaar()

        XCTAssertEqual(snapshot.receivable, 140, accuracy: 0.001)
        XCTAssertEqual(snapshot.payable, 30, accuracy: 0.001)
        XCTAssertEqual(snapshot.topCustomers.map(\.name), ["Suresh", "Ramesh"])
        XCTAssertEqual(snapshot.topSuppliers.map(\.name), ["Sharma Traders"])
    }

    func testPartyBalanceForCustomerAndSupplier() async throws {
        let (service, _, creditStore) = try makeService()
        creditStore.addCreditSale(amount: 75, customerName: "Ramesh")
        creditStore.addCreditPurchase(amount: 40, supplierName: "Sharma Traders")

        let customer = try XCTUnwrap(creditStore.getAllCustomers().first { $0.name == "Ramesh" })
        let supplier = try XCTUnwrap(creditStore.getAllSuppliers().first { $0.name == "Sharma Traders" })

        let customerBalance = try await service.partyBalance(id: "customer:\(customer.id.uuidString)")
        let supplierBalance = try await service.partyBalance(id: "supplier:\(supplier.id.uuidString)")

        XCTAssertEqual(customerBalance.balance, 75, accuracy: 0.001)
        XCTAssertEqual(customerBalance.party.kind, .customer)
        XCTAssertEqual(supplierBalance.balance, 40, accuracy: 0.001)
        XCTAssertEqual(supplierBalance.party.kind, .supplier)
    }

    func testRecentTransactionsReturnsLatestBills() async throws {
        let (service, db, _) = try makeService()
        let item = makeItem(name: "Aloo", stock: 10)
        try db.insertItem(item)
        try insertBatch(for: item, quantity: 10, into: db)

        let model = DataModel(database: db)
        _ = try model.addMultiItemSale(
            items: [(itemID: item.id, quantity: 2, sellingPrice: 30)],
            customerName: "Ramesh",
            customerPhone: nil
        )

        let snapshot = try await service.recentTransactions(limit: 5)
        XCTAssertEqual(snapshot.totalCount, 1)
        let first = try XCTUnwrap(snapshot.transactions.first)
        XCTAssertEqual(first.amount, 60, accuracy: 0.001)
        XCTAssertEqual(first.partyName, "Ramesh")
        XCTAssertTrue(first.isSale)
    }

    func testExpiryAlertsIncludeDaysAndUrgency() async throws {
        let (service, db, _) = try makeService()
        let item = makeItem(name: "Doodh", stock: 6, unit: "packet")
        try db.insertItem(item)
        try insertBatch(
            for: item,
            quantity: 6,
            expiryDate: Calendar.current.date(
                byAdding: .day,
                value: 3,
                to: Calendar.current.startOfDay(for: Date())
            ),
            into: db
        )

        let snapshot = try await service.expiry()

        XCTAssertEqual(snapshot.totalCount, 1)
        let alert = try XCTUnwrap(snapshot.items.first)
        XCTAssertEqual(alert.name, "Doodh")
        XCTAssertEqual(alert.unit, "packet")
        XCTAssertEqual(alert.urgency, .critical)
        XCTAssertEqual(alert.daysUntilExpiry, 2)
    }

    func testInvalidPartyIDThrowsNotFound() async throws {
        let (service, _, _) = try makeService()

        do {
            _ = try await service.partyBalance(id: "not-a-party")
            XCTFail("Expected partyNotFound")
        } catch LedgerQueryError.partyNotFound {
        }
    }
}
