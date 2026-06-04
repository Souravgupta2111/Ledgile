
struct ProfitItem {
    let name: String
    let quantity: Double
    let costPrice: Double
    let sellingPrice: Double
    var unitProfit: Double { sellingPrice - costPrice }
    var totalProfit: Double { unitProfit * quantity }
    }

struct ChartPoint {
    let label: String
    let value: Double
    }

enum Period: Int, CaseIterable {
    case daily = 0, weekly, monthly, yearly
}

