import Foundation
import Observation

@Observable
final class SalesTabViewModel {

    var allTransactions: [(transaction: Transaction, itemsSummary: String)] = []

    var filteredTransactions: [(transaction: Transaction, itemsSummary: String)] = []

    var selectedDate = Date() {
        didSet { filterTransactions(for: selectedDate) }
    }

    var revenue: Double = 0
    var profit: Double = 0
    var receiptCount: Int = 0

    var itemsSoldCount: Double = 0
    var salesPercentChange: Double?
    var profitPercentChange: Double?

    @ObservationIgnored private let calendar = Calendar.current

    var isEmpty: Bool { filteredTransactions.isEmpty }

    var selectableDates: ClosedRange<Date> {
        let today = calendar.startOfDay(for: Date())
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today)?
            .addingTimeInterval(-1) ?? Date()

        let oldest = allTransactions
            .map { calendar.startOfDay(for: $0.transaction.date) }
            .min() ?? today

        return min(oldest, today)...endOfToday
    }

    func loadSalesData() {
        let dm = AppDataModel.shared.dataModel
        allTransactions = dm.getRecentTransactions(limit: 100)
            .filter { $0.transaction.type == .sale }

        revenue = dm.getTodayRevenue()
        profit = dm.getTodayProfit()
        receiptCount = dm.getTodaySaleCount()
        itemsSoldCount = dm.getTodayItemsSoldCount()

        if let yesterday = calendar.date(byAdding: .day, value: -1,
                                         to: calendar.startOfDay(for: Date())),
           let yesterdaySummary = try? dm.db.getDailySummary(for: yesterday) {
            salesPercentChange = revenue.percentChange(from: yesterdaySummary.totalRevenue)
            profitPercentChange = profit.percentChange(from: yesterdaySummary.totalProfit)
        } else {
            salesPercentChange = nil
            profitPercentChange = nil
        }

        filterTransactions(for: selectedDate)
    }

    func filterTransactions(for date: Date) {
        let startOfDay = calendar.startOfDay(for: date)
        filteredTransactions = allTransactions.filter {
            calendar.startOfDay(for: $0.transaction.date) == startOfDay
        }
    }
}
