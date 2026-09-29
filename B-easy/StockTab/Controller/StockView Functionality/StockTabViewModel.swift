import Foundation
import Combine

final class StockTabViewModel: ObservableObject {
    @Published var totalInventoryValue: Double = 0
    @Published var lowStockItemsCount: Int = 0
    @Published var totalItemsCount: Int = 0
    @Published var items: [Item] = []

    // Purchase tile data
    @Published var todayPurchaseAmount: Double = 0
    @Published var todayPurchaseItemCount: Int = 0

    // Expiry tile data
    @Published var expiryAlertsCount: Int = 0

    func loadStockData() {
        let dm = AppDataModel.shared.dataModel
        do {
            let items = try dm.db.getAllItems()
            var value = 0.0
            var lowCount = 0
            for item in items {
                value += Double(item.currentStock) * item.defaultCostPrice
                if item.currentStock <= item.lowStockThreshold {
                    lowCount += 1
                }
            }
            totalInventoryValue = value
            lowStockItemsCount = lowCount
            totalItemsCount = items.count
            self.items = items
        } catch {
            print("Error loading stock data: \(error)")
        }

        // Purchase data
        todayPurchaseAmount = dm.getTodayPurchaseTotal()
        todayPurchaseItemCount = dm.getTodayItemsPurchasedCount()

        // Expiry data
        let expiryAlerts = (try? dm.getExpiryAlerts()) ?? []
        expiryAlertsCount = expiryAlerts.count
    }
}
