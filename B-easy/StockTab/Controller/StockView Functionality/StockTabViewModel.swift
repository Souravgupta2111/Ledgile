import Foundation
import Combine

final class StockTabViewModel: ObservableObject {
    @Published var totalInventoryValue: Double = 0
    @Published var lowStockItemsCount: Int = 0
    @Published var totalItemsCount: Int = 0
    @Published var items: [Item] = []

    func loadStockData() {
        do {
            let items = try AppDataModel.shared.dataModel.db.getAllItems()
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
    }
}
