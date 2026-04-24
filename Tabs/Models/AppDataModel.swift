import Foundation
class AppDataModel {

    static let shared = AppDataModel()

    let dataModel: DataModel

    private static let seedVersion = "v4"

     init() {
        let db = SQLiteDatabase.shared
        dataModel = DataModel(database: db)

        let lastSeed = UserDefaults.standard.string(forKey: "seedDataVersion")
        if lastSeed != Self.seedVersion {
            db.clearAllPersistedData()
            seedDummyData()
            UserDefaults.standard.set(Self.seedVersion, forKey: "seedDataVersion")
        }
    }

    // MARK: - Dummy Data Seeding
     func seedDummyData() {
        let cal = Calendar.current
        let now = Date()

        let maggi = Item(id: UUID(), name: "Maggi", unit: "pack", defaultCostPrice: 6, defaultSellingPrice: 10, defaultPriceUpdatedAt: now, lowStockThreshold: 10, currentStock: 100, createdDate: now, lastRestockDate: now, isActive: true)
        let fiveStar = Item(id: UUID(), name: "5 Star", unit: "pcs", defaultCostPrice: 8, defaultSellingPrice: 12, defaultPriceUpdatedAt: now, lowStockThreshold: 15, currentStock: 80, createdDate: now, lastRestockDate: now, isActive: true)
        let oreo = Item(id: UUID(), name: "Oreo Biscuits", unit: "pcs", defaultCostPrice: 22, defaultSellingPrice: 30, defaultPriceUpdatedAt: now, lowStockThreshold: 10, currentStock: 3, createdDate: now, lastRestockDate: now, isActive: true)
        let cashew = Item(id: UUID(), name: "Cashew", unit: "kg", defaultCostPrice: 600, defaultSellingPrice: 750, defaultPriceUpdatedAt: now, lowStockThreshold: 5, currentStock: 4, createdDate: now, lastRestockDate: now, isActive: true)
        let rice = Item(id: UUID(), name: "Basmati Rice", unit: "kg", defaultCostPrice: 80, defaultSellingPrice: 110, defaultPriceUpdatedAt: now, lowStockThreshold: 20, currentStock: 150, createdDate: now, lastRestockDate: now, isActive: true)
        let sugar = Item(id: UUID(), name: "Sugar", unit: "kg", defaultCostPrice: 40, defaultSellingPrice: 55, defaultPriceUpdatedAt: now, lowStockThreshold: 10, currentStock: 60, createdDate: now, lastRestockDate: now, isActive: true)
        let cocaCola = Item(id: UUID(), name: "Coca Cola", unit: "bottle", defaultCostPrice: 35, defaultSellingPrice: 45, defaultPriceUpdatedAt: now, lowStockThreshold: 12, currentStock: 48, createdDate: now, lastRestockDate: now, isActive: true)
        let maida = Item(id: UUID(), name: "Maida", unit: "kg", defaultCostPrice: 30, defaultSellingPrice: 42, defaultPriceUpdatedAt: now, lowStockThreshold: 8, currentStock: 35, createdDate: now, lastRestockDate: now, isActive: true)
        let dhaniya = Item(id: UUID(), name: "Dhaniya", unit: "kg", defaultCostPrice: 100, defaultSellingPrice: 140, defaultPriceUpdatedAt: now, lowStockThreshold: 3, currentStock: 12, createdDate: now, lastRestockDate: now, isActive: true)
        let aloo = Item(id: UUID(), name: "Aloo", unit: "kg", defaultCostPrice: 25, defaultSellingPrice: 35, defaultPriceUpdatedAt: now, lowStockThreshold: 10, currentStock: 50, createdDate: now, lastRestockDate: now, isActive: true)

        let allItems = [maggi, fiveStar, oreo, cashew, rice, sugar, cocaCola, maida, dhaniya, aloo]

        for item in allItems {
            try? dataModel.db.insertItem(item)
        }

        func makeBatch(item: Item, qty: Int, daysAgo: Int, expiryInDays: Int? = nil) {
            let receivedDate = cal.date(byAdding: .day, value: -daysAgo, to: now)!
            let expiryDate = expiryInDays.flatMap { cal.date(byAdding: .day, value: $0, to: now) }
            let purchaseTxID = UUID()

            // Purchase transaction
            let tx = Transaction(
                id: purchaseTxID,
                type: .purchase,
                date: receivedDate,
                invoiceNumber: "SEED-\(Int.random(in: 1000...9999))",
                customerName: nil,
                customerPhone: nil,
                supplierName: "Supplier \(["A", "B", "C"].randomElement()!)",
                totalAmount: Double(qty) * item.defaultCostPrice,
                notes: nil
            )
            try? dataModel.db.insertTransaction(tx)

            let txItem = TransactionItem(
                id: UUID(),
                transactionID: purchaseTxID,
                itemID: item.id,
                itemName: item.name,
                unit: item.unit,
                quantity: qty,
                sellingPricePerUnit: item.defaultSellingPrice,
                costPricePerUnit: item.defaultCostPrice,
                createdDate: receivedDate
            )
            try? dataModel.db.insertTransactionItems([txItem])

            let batch = ItemBatch(
                id: UUID(),
                itemID: item.id,
                purchaseTransactionID: purchaseTxID,
                quantityPurchased: qty,
                quantityRemaining: item.currentStock, // Simplified: remaining = current stock
                costPrice: item.defaultCostPrice,
                sellingPrice: item.defaultSellingPrice,
                expiryDate: expiryDate,
                receivedDate: receivedDate
            )
            try? dataModel.db.insertBatch(batch)
        }

        makeBatch(item: maggi, qty: 120, daysAgo: 10, expiryInDays: 180)
        makeBatch(item: fiveStar, qty: 100, daysAgo: 7, expiryInDays: 90)
        makeBatch(item: oreo, qty: 50, daysAgo: 14, expiryInDays: 60)
        makeBatch(item: cashew, qty: 10, daysAgo: 5)
        makeBatch(item: rice, qty: 200, daysAgo: 12)
        makeBatch(item: sugar, qty: 80, daysAgo: 8)
        makeBatch(item: cocaCola, qty: 60, daysAgo: 6, expiryInDays: 120)
        makeBatch(item: maida, qty: 50, daysAgo: 9)
        makeBatch(item: dhaniya, qty: 20, daysAgo: 4)
        makeBatch(item: aloo, qty: 60, daysAgo: 3)

        struct SaleSeed {
            let items: [(Item, Int)]  // (item, qty sold)
            let daysAgo: Int
            let customer: String?
        }

        var sales: [SaleSeed] = [
            // Today (day 0) — busy day, 8 transactions
            SaleSeed(items: [(maggi, 10), (fiveStar, 5)], daysAgo: 0, customer: "Rahul"),
            SaleSeed(items: [(oreo, 4), (cocaCola, 6)], daysAgo: 0, customer: nil),
            SaleSeed(items: [(rice, 5), (sugar, 3)], daysAgo: 0, customer: "Priya"),
            SaleSeed(items: [(cashew, 1), (dhaniya, 2)], daysAgo: 0, customer: "Amit"),
            SaleSeed(items: [(aloo, 8), (maida, 3)], daysAgo: 0, customer: nil),
            SaleSeed(items: [(fiveStar, 6), (cocaCola, 4)], daysAgo: 0, customer: "Sneha"),
            SaleSeed(items: [(maggi, 8), (sugar, 2)], daysAgo: 0, customer: "Harish"),
            SaleSeed(items: [(rice, 3), (aloo, 4)], daysAgo: 0, customer: "Meena"),

            // Yesterday (day 1) — 4 transactions
            SaleSeed(items: [(rice, 8), (sugar, 5), (maida, 3)], daysAgo: 1, customer: "Priya"),
            SaleSeed(items: [(cashew, 2), (dhaniya, 2)], daysAgo: 1, customer: "Amit"),
            SaleSeed(items: [(maggi, 12), (cocaCola, 6)], daysAgo: 1, customer: nil),
            SaleSeed(items: [(fiveStar, 8), (oreo, 3)], daysAgo: 1, customer: "Sneha"),

            // 2 days ago — 4 transactions
            SaleSeed(items: [(aloo, 15), (maggi, 10)], daysAgo: 2, customer: nil),
            SaleSeed(items: [(fiveStar, 20), (cocaCola, 8)], daysAgo: 2, customer: "Rajan"),
            SaleSeed(items: [(rice, 12), (sugar, 6)], daysAgo: 2, customer: "Harish"),
            SaleSeed(items: [(cashew, 3), (maida, 5)], daysAgo: 2, customer: "Meena"),

            // 3 days ago — 3 transactions
            SaleSeed(items: [(maggi, 4), (aloo, 3)], daysAgo: 3, customer: "Rahul"),
            SaleSeed(items: [(oreo, 5), (cocaCola, 3)], daysAgo: 3, customer: nil),
            SaleSeed(items: [(sugar, 4), (rice, 2)], daysAgo: 3, customer: "Priya"),

            // 4 days ago — 3 transactions
            SaleSeed(items: [(rice, 6), (maida, 4), (sugar, 3)], daysAgo: 4, customer: "Priya"),
            SaleSeed(items: [(fiveStar, 10), (cocaCola, 5)], daysAgo: 4, customer: nil),
            SaleSeed(items: [(dhaniya, 2), (aloo, 6)], daysAgo: 4, customer: "Amit"),

            // 5 days ago — 3 transactions
            SaleSeed(items: [(fiveStar, 15), (cocaCola, 10)], daysAgo: 5, customer: "Sneha"),
            SaleSeed(items: [(rice, 10), (cashew, 2)], daysAgo: 5, customer: nil),
            SaleSeed(items: [(maggi, 8), (sugar, 4)], daysAgo: 5, customer: "Meena"),

            // 6 days ago — 3 transactions
            SaleSeed(items: [(aloo, 5), (maggi, 6)], daysAgo: 6, customer: nil),
            SaleSeed(items: [(oreo, 3), (fiveStar, 7)], daysAgo: 6, customer: "Rajan"),
            SaleSeed(items: [(cocaCola, 4), (rice, 3)], daysAgo: 6, customer: "Harish"),
        ]

        // Add dynamically generated historical data (back to 65 days)
        for day in 7...65 {
            let numTransactions = Int.random(in: 2...6)
            for _ in 0..<numTransactions {
                let numberOfItems = Int.random(in: 1...3)
                var itemsList: [(Item, Int)] = []
                for _ in 0..<numberOfItems {
                    let randomItem = allItems.randomElement()!
                    let qty = Int.random(in: 1...15)
                    itemsList.append((randomItem, qty))
                }
                sales.append(SaleSeed(items: itemsList, daysAgo: day, customer: nil))
            }
        }

        var dailyRevenue: [Date: Double] = [:]
        var dailyProfit: [Date: Double] = [:]
        var dailySaleCount: [Date: Int] = [:]
        var dailyItemsSold: [Date: Int] = [:]
        var dailyPurchaseAmount: [Date: Double] = [:]
        var dailyPurchaseCount: [Date: Int] = [:]

        // Accumulate purchase transactions into daily summaries
        for item in allItems {
            let batches = (try? dataModel.db.getBatches(for: item.id)) ?? []
            for batch in batches {
                let dayKey = cal.startOfDay(for: batch.receivedDate)
                dailyPurchaseAmount[dayKey, default: 0] += Double(batch.quantityPurchased) * batch.costPrice
                dailyPurchaseCount[dayKey, default: 0] += 1
            }
        }

        for sale in sales {
            let saleDate = cal.date(byAdding: .day, value: -sale.daysAgo, to: now)!
            let dayKey = cal.startOfDay(for: saleDate)
            let txID = UUID()
            var totalAmount: Double = 0
            var totalProfit: Double = 0
            var totalItemCount: Int = 0

            var txItems: [TransactionItem] = []
            for (item, qty) in sale.items {
                let revenue = Double(qty) * item.defaultSellingPrice
                let cost = Double(qty) * item.defaultCostPrice
                totalAmount += revenue
                totalProfit += revenue - cost
                totalItemCount += qty
                txItems.append(TransactionItem(
                    id: UUID(),
                    transactionID: txID,
                    itemID: item.id,
                    itemName: item.name,
                    unit: item.unit,
                    quantity: qty,
                    sellingPricePerUnit: item.defaultSellingPrice,
                    costPricePerUnit: item.defaultCostPrice,
                    createdDate: saleDate
                ))
            }

            let tx = Transaction(
                id: txID,
                type: .sale,
                date: saleDate,
                invoiceNumber: "INV-\(String(format: "%04d", Int.random(in: 1...500)))",
                customerName: sale.customer,
                customerPhone: nil,
                supplierName: nil,
                totalAmount: totalAmount,
                notes: nil
            )
            try? dataModel.db.insertTransaction(tx)
            try? dataModel.db.insertTransactionItems(txItems)

            dailyRevenue[dayKey, default: 0] += totalAmount
            dailyProfit[dayKey, default: 0] += totalProfit
            dailySaleCount[dayKey, default: 0] += 1
            dailyItemsSold[dayKey, default: 0] += totalItemCount
        }

        // Merge all unique days from sales + purchases
        let allDays = Set(dailyRevenue.keys).union(dailyPurchaseAmount.keys)
        for day in allDays {
            let summary = DailySummary(
                id: UUID(),
                date: day,
                totalRevenue: dailyRevenue[day] ?? 0,
                totalProfit: dailyProfit[day] ?? 0,
                salesTransactionCount: dailySaleCount[day] ?? 0,
                itemsSoldCount: dailyItemsSold[day] ?? 0,
                totalPurchaseAmount: dailyPurchaseAmount[day] ?? 0,
                purchaseTransactionCount: dailyPurchaseCount[day] ?? 0
            )
            try? dataModel.db.upsertDailySummary(summary)
        }

    }
}
