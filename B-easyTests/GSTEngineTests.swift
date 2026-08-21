import XCTest
@testable import B_easy

@MainActor
final class GSTEngineTests: XCTestCase {

    func testInclusiveIdentity18Percent() {
        let result = GSTEngine.calculateTax(
            price: 118,
            quantity: 1,
            gstRate: 18,
            isInterState: false,
            pricesIncludeGST: true
        )
        XCTAssertTrue(GSTEngine.identityHolds(result))
        XCTAssertEqual(GSTEngine.paise(result.totalWithTax), GSTEngine.paise(118))
    }

    func testIntraHalvingDoesNotDropPaisa() {
        let result = GSTEngine.calculateTax(
            price: 4.51,
            quantity: 1,
            gstRate: 18,
            isInterState: false,
            pricesIncludeGST: false
        )
        XCTAssertTrue(GSTEngine.identityHolds(result))
        XCTAssertEqual(GSTEngine.paise(result.cgst) + GSTEngine.paise(result.sgst), GSTEngine.paise(result.totalTax))
    }

    func testMoneyRoundsToTwoDecimals() {
        XCTAssertEqual(Money.round2(0.23 * 45), 10.35)
        XCTAssertEqual(Money.line(quantity: 0.23, rate: 45), 10.35)
        XCTAssertEqual(Money.round2(10.129), 10.13)
        XCTAssertEqual(Money.round2(10.121), 10.12)
    }

    func testUnknownPlaceOfSupplyIsNotIntra() {
        XCTAssertNil(GSTEngine.isInterStateSupply(sellerStateCode: "07", buyerStateCode: nil))
        XCTAssertNil(GSTEngine.isInterStateSupply(sellerStateCode: nil, buyerStateCode: "07"))
        XCTAssertEqual(GSTEngine.isInterStateSupply(sellerStateCode: "07", buyerStateCode: "07"), false)
        XCTAssertEqual(GSTEngine.isInterStateSupply(sellerStateCode: "07", buyerStateCode: "27"), true)
    }

    func testDiscountThenTaxIdentity() {
        let discounted = GSTEngine.discountedUnitPrice(
            lineRevenue: 200,
            subtotal: 200,
            discount: 20,
            quantity: 1
        )
        let result = GSTEngine.calculateTax(
            price: discounted,
            quantity: 1,
            gstRate: 18,
            isInterState: false,
            pricesIncludeGST: true
        )
        XCTAssertTrue(GSTEngine.identityHolds(result))
    }

    func testInterStateUsesIGST() {
        let result = GSTEngine.calculateTax(
            price: 100,
            quantity: 1,
            gstRate: 18,
            isInterState: true,
            pricesIncludeGST: false
        )
        XCTAssertEqual(result.cgst, 0)
        XCTAssertEqual(result.sgst, 0)
        XCTAssertGreaterThan(result.igst, 0)
        XCTAssertTrue(GSTEngine.identityHolds(result))
    }

    func testSaleTransactionRollsBackOnThrow() throws {
        let db = SQLiteDatabase(path: ":memory:")
        let model = DataModel(database: db)
        var settings = try db.getSettings()
        settings.isGSTRegistered = false
        try db.updateSettings(settings)

        let item = Item(
            id: UUID(),
            name: "Test Aloo",
            unit: "kg",
            barcode: nil,
            defaultCostPrice: 10,
            defaultSellingPrice: 20,
            defaultPriceUpdatedAt: Date(),
            lowStockThreshold: 0,
            currentStock: 5,
            createdDate: Date(),
            lastRestockDate: nil,
            isActive: true
        )
        try db.insertItem(item)
        let batch = ItemBatch(
            id: UUID(),
            itemID: item.id,
            purchaseTransactionID: UUID(),
            quantityPurchased: 5,
            quantityRemaining: 5,
            costPrice: 10,
            sellingPrice: 20,
            expiryDate: nil,
            receivedDate: Date()
        )
        try db.insertBatch(batch)

        _ = try model.addMultiItemSale(
            items: [(itemID: item.id, quantity: 1, sellingPrice: 20)],
            customerName: nil,
            customerPhone: nil
        )
        let remaining = try db.getBatches(for: item.id).reduce(0) { $0 + $1.quantityRemaining }
        XCTAssertEqual(remaining, 4, accuracy: 0.001)
    }
}
