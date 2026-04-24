import Foundation
class ChartDataProvider {

    static let shared = ChartDataProvider()
     var dm: DataModel { AppDataModel.shared.dataModel }
     let calendar = Calendar.current

     init() {}

    // MARK: - Data Structures (View-Model only)

    struct ProfitItem {
        let itemID: UUID?
        let name: String
        let quantity: Int
        let costPrice: Double
        let sellingPrice: Double

        var unitProfit: Double { sellingPrice - costPrice }
        var totalProfit: Double { unitProfit * Double(quantity) }
    }

    struct ChartPoint {
        let label: String
        let value: Double
    }

    // MARK: - Period Enum

    enum Period: Int, CaseIterable {
        case daily = 0, weekly, monthly, yearly
    }

    func getRevenueChartData(period: Period) -> [ChartPoint] {
        let sales = saleTransactions()

        switch period {
        case .daily:
            return dailyAggregation(sales: sales, keyPath: \.totalAmount, count: 7)
        case .weekly:
            return weeklyAggregation(sales: sales, keyPath: \.totalAmount)
        case .monthly:
            return monthlyAggregation(sales: sales, keyPath: \.totalAmount)
        case .yearly:
            return yearlyAggregation(sales: sales, keyPath: \.totalAmount)
        }
    }

    
    func getProfitChartData(period: Period) -> [ChartPoint] {
        let sales = saleTransactions()

        var profitMap: [UUID: Double] = [:]
        for tx in sales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            let profit = items.reduce(0.0) { sum, item in
                let sell = item.sellingPricePerUnit ?? 0
                let cost = item.costPricePerUnit ?? 0
                return sum + Double(item.quantity) * (sell - cost)
            }
            profitMap[tx.id] = profit
        }

        switch period {
        case .daily:
            return dailyProfitAggregation(sales: sales, profitMap: profitMap, count: 7)
        case .weekly:
            return weeklyProfitAggregation(sales: sales, profitMap: profitMap)
        case .monthly:
            return monthlyProfitAggregation(sales: sales, profitMap: profitMap)
        case .yearly:
            return yearlyProfitAggregation(sales: sales, profitMap: profitMap)
        }
    }

   
    func getTodayProfitItems() -> [ProfitItem] {
        return getProfitItems(period: .daily)
    }

    func getItemsSoldChartData(period: Period) -> [ChartPoint] {
        let sales = saleTransactions()

        switch period {
        case .daily:
            return dailyQuantityAggregation(sales: sales, count: 7)
        case .weekly:
            return weeklyQuantityAggregation(sales: sales)
        case .monthly:
            return monthlyQuantityAggregation(sales: sales)
        case .yearly:
            return yearlyQuantityAggregation(sales: sales)
        }
    }

 
    func getProfitItems(period: Period) -> [ProfitItem] {
        let filteredSales = saleTransactions(startingAt: startDate(for: period))

        var aggregated: [UUID: (name: String, qty: Int, cost: Double, sell: Double)] = [:]

        for tx in filteredSales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let existing = aggregated[item.itemID] ?? (name: item.itemName, qty: 0, cost: 0, sell: 0)
                aggregated[item.itemID] = (
                    name: existing.name,
                    qty: existing.qty + item.quantity,
                    cost: item.costPricePerUnit ?? existing.cost,
                    sell: item.sellingPricePerUnit ?? existing.sell
                )
            }
        }

        return aggregated.map { itemID, data in
            ProfitItem(
                itemID: itemID,
                name: data.name,
                quantity: data.qty,
                costPrice: data.cost,
                sellingPrice: data.sell
            )
        }.sorted { $0.totalProfit > $1.totalProfit }
    }

    /// Returns sales items for the given period, sorted by total revenue (quantity × selling price).
    func getSalesItems(period: Period) -> [ProfitItem] {
        let filteredSales = saleTransactions(startingAt: startDate(for: period))

        var aggregated: [UUID: (name: String, qty: Int, cost: Double, sell: Double)] = [:]

        for tx in filteredSales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let existing = aggregated[item.itemID] ?? (name: item.itemName, qty: 0, cost: 0, sell: 0)
                aggregated[item.itemID] = (
                    name: existing.name,
                    qty: existing.qty + item.quantity,
                    cost: item.costPricePerUnit ?? existing.cost,
                    sell: item.sellingPricePerUnit ?? existing.sell
                )
            }
        }

        return aggregated.map { itemID, data in
            ProfitItem(
                itemID: itemID,
                name: data.name,
                quantity: data.qty,
                costPrice: data.cost,
                sellingPrice: data.sell
            )
        }.sorted(by: sortItemsByQuantityThenRevenue)
    }

   
    func getSalesItems() -> [ProfitItem] {
        let sales = saleTransactions()

        var aggregated: [UUID: (name: String, qty: Int, cost: Double, sell: Double)] = [:]

        for tx in sales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let existing = aggregated[item.itemID] ?? (name: item.itemName, qty: 0, cost: 0, sell: 0)
                aggregated[item.itemID] = (
                    name: existing.name,
                    qty: existing.qty + item.quantity,
                    cost: item.costPricePerUnit ?? existing.cost,
                    sell: item.sellingPricePerUnit ?? existing.sell
                )
            }
        }

        return aggregated.map { itemID, data in
            ProfitItem(
                itemID: itemID,
                name: data.name,
                quantity: data.qty,
                costPrice: data.cost,
                sellingPrice: data.sell
            )
        }.sorted(by: sortItemsByQuantityThenRevenue)
    }

    // MARK: - Dashboard Weekly Data

    struct WeekDayData {
        let dayLabel: String
        let revenue: Double
        let profit: Double
    }

    /// Returns last 7 days of revenue + profit data for dashboard bar charts.
    func getWeeklyDashboardData() -> [WeekDayData] {
        let now = Date()
        var result: [WeekDayData] = []
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        for i in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -i, to: now) else { continue }

            if let summary = try? dm.db.getDailySummary(for: day) {
                let label = (i == 0) ? "Tod" : dayFormatter.string(from: day)
                result.append(WeekDayData(
                    dayLabel: label,
                    revenue: summary.totalRevenue,
                    profit: summary.totalProfit
                ))
            } else {
                let label = (i == 0) ? "Tod" : dayFormatter.string(from: day)
                result.append(WeekDayData(dayLabel: label, revenue: 0, profit: 0))
            }
        }

        return result
    }

    // MARK: - Today Summary Labels

    func getTodayRevenue() -> Double {
        return dm.getTodayRevenue()
    }

    func getTodayProfit() -> Double {
        return dm.getTodayProfit()
    }

    // MARK: -  Aggregation Helpers

     func dailyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>, count: Int) -> [ChartPoint] {
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        var result: [ChartPoint] = []

        for i in stride(from: count - 1, through: 0, by: -1) {
            guard let targetDate = calendar.date(byAdding: .day, value: -i, to: now) else { continue }
            let dayStart = calendar.startOfDay(for: targetDate)

            let dayTotal = sales
                .filter { calendar.startOfDay(for: $0.date) == dayStart }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            let label = (i == 0) ? "Tod" : dayFormatter.string(from: targetDate)
            result.append(ChartPoint(label: label, value: dayTotal))
        }

        return result
    }

     func dailyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double], count: Int) -> [ChartPoint] {
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        var result: [ChartPoint] = []

        for i in stride(from: count - 1, through: 0, by: -1) {
            guard let targetDate = calendar.date(byAdding: .day, value: -i, to: now) else { continue }
            let dayStart = calendar.startOfDay(for: targetDate)

            let dayTotal = sales
                .filter { calendar.startOfDay(for: $0.date) == dayStart }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            let label = (i == 0) ? "Tod" : dayFormatter.string(from: targetDate)
            result.append(ChartPoint(label: label, value: dayTotal))
        }

        return result
    }

     func weeklyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>) -> [ChartPoint] {
        let now = Date()
        var result: [ChartPoint] = []

        for i in stride(from: 6, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -i, to: now) else { continue }
            let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart)

            let weekTotal = sales
                .filter { tx in
                    guard let interval = interval else { return false }
                    return tx.date >= interval.start && tx.date < interval.end
                }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            let label = (i == 0) ? "This" : "W\(7 - i)"
            result.append(ChartPoint(label: label, value: weekTotal))
        }

        return result
    }

     func weeklyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double]) -> [ChartPoint] {
        let now = Date()
        var result: [ChartPoint] = []

        for i in stride(from: 6, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -i, to: now) else { continue }
            let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart)

            let weekTotal = sales
                .filter { tx in
                    guard let interval = interval else { return false }
                    return tx.date >= interval.start && tx.date < interval.end
                }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            let label = (i == 0) ? "This" : "W\(7 - i)"
            result.append(ChartPoint(label: label, value: weekTotal))
        }

        return result
    }

     let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

     func monthlyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>) -> [ChartPoint] {
        let now = Date()
        var result: [ChartPoint] = []

        for i in stride(from: 6, through: 0, by: -1) {
            guard let monthStart = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            let interval = calendar.dateInterval(of: .month, for: monthStart)
            let monthIndex = calendar.component(.month, from: monthStart) - 1

            let monthTotal = sales
                .filter { tx in
                    guard let interval = interval else { return false }
                    return tx.date >= interval.start && tx.date < interval.end
                }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            result.append(ChartPoint(label: monthNames[monthIndex], value: monthTotal))
        }

        return result
    }

     func monthlyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double]) -> [ChartPoint] {
        let now = Date()
        var result: [ChartPoint] = []

        for i in stride(from: 6, through: 0, by: -1) {
            guard let monthStart = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            let interval = calendar.dateInterval(of: .month, for: monthStart)
            let monthIndex = calendar.component(.month, from: monthStart) - 1

            let monthTotal = sales
                .filter { tx in
                    guard let interval = interval else { return false }
                    return tx.date >= interval.start && tx.date < interval.end
                }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            result.append(ChartPoint(label: monthNames[monthIndex], value: monthTotal))
        }

        return result
    }

     func yearlyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>) -> [ChartPoint] {
        let currentYear = calendar.component(.year, from: Date())
        var result: [ChartPoint] = []

        for year in (currentYear - 6)...currentYear {
            let yearTotal = sales
                .filter { calendar.component(.year, from: $0.date) == year }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            result.append(ChartPoint(label: "\(year)", value: yearTotal))
        }

        return result
    }

     func yearlyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double]) -> [ChartPoint] {
        let currentYear = calendar.component(.year, from: Date())
        var result: [ChartPoint] = []

        for year in (currentYear - 6)...currentYear {
            let yearTotal = sales
                .filter { calendar.component(.year, from: $0.date) == year }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            result.append(ChartPoint(label: "\(year)", value: yearTotal))
        }

        return result
    }

  
    func comparisonLabel(for period: Period) -> String {
        switch period {
        case .daily:   return "Previous 7 Days"
        case .weekly:  return "Previous 7 Weeks"
        case .monthly: return "Previous 7 Months"
        case .yearly:  return "Previous 7 Years"
        }
    }

   
    func getComparisonRevenueChartData(period: Period) -> [ChartPoint] {
        let sales = saleTransactions()

        switch period {
        case .daily:
            return dailyAggregation(sales: sales, keyPath: \.totalAmount, count: 7, offset: 7)
        case .weekly:
            return weeklyAggregation(sales: sales, keyPath: \.totalAmount, offset: 7)
        case .monthly:
            return monthlyAggregation(sales: sales, keyPath: \.totalAmount, offset: 7)
        case .yearly:
            return yearlyAggregation(sales: sales, keyPath: \.totalAmount, offset: 7)
        }
    }


    func getComparisonProfitChartData(period: Period) -> [ChartPoint] {
        let sales = saleTransactions()

        var profitMap: [UUID: Double] = [:]
        for tx in sales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            let profit = items.reduce(0.0) { sum, item in
                let sell = item.sellingPricePerUnit ?? 0
                let cost = item.costPricePerUnit ?? 0
                return sum + Double(item.quantity) * (sell - cost)
            }
            profitMap[tx.id] = profit
        }

        switch period {
        case .daily:
            return dailyProfitAggregation(sales: sales, profitMap: profitMap, count: 7, offset: 7)
        case .weekly:
            return weeklyProfitAggregation(sales: sales, profitMap: profitMap, offset: 7)
        case .monthly:
            return monthlyProfitAggregation(sales: sales, profitMap: profitMap, offset: 7)
        case .yearly:
            return yearlyProfitAggregation(sales: sales, profitMap: profitMap, offset: 7)
        }
    }

    private func saleTransactions(startingAt startDate: Date? = nil) -> [Transaction] {
        let transactions = (try? dm.db.getTransactions()) ?? []
        return transactions.filter { transaction in
            guard transaction.type == .sale else { return false }
            guard let startDate else { return true }
            return transaction.date >= startDate
        }
    }

    private func startDate(for period: Period) -> Date {
        let now = Date()
        let today = calendar.startOfDay(for: now)

        switch period {
        case .daily:
            return today
        case .weekly:
            return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .monthly:
            return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .yearly:
            return calendar.date(byAdding: .day, value: -364, to: today) ?? today
        }
    }

    private func totalQuantity(for sales: [Transaction], matching predicate: (Transaction) -> Bool) -> Int {
        sales
            .filter(predicate)
            .reduce(0) { total, transaction in
                let quantity = ((try? dm.db.getTransactionItems(for: transaction.id)) ?? [])
                    .reduce(0) { $0 + $1.quantity }
                return total + quantity
            }
    }

    private func sortItemsByQuantityThenRevenue(_ lhs: ProfitItem, _ rhs: ProfitItem) -> Bool {
        if lhs.quantity != rhs.quantity {
            return lhs.quantity > rhs.quantity
        }

        let lhsRevenue = lhs.sellingPrice * Double(lhs.quantity)
        let rhsRevenue = rhs.sellingPrice * Double(rhs.quantity)
        if lhsRevenue != rhsRevenue {
            return lhsRevenue > rhsRevenue
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func dailyQuantityAggregation(sales: [Transaction], count: Int) -> [ChartPoint] {
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        var result: [ChartPoint] = []

        for i in stride(from: count - 1, through: 0, by: -1) {
            guard let targetDate = calendar.date(byAdding: .day, value: -i, to: now) else { continue }
            let dayStart = calendar.startOfDay(for: targetDate)
            let quantity = totalQuantity(for: sales) { transaction in
                calendar.startOfDay(for: transaction.date) == dayStart
            }

            let label = (i == 0) ? "Tod" : dayFormatter.string(from: targetDate)
            result.append(ChartPoint(label: label, value: Double(quantity)))
        }

        return result
    }

    private func weeklyQuantityAggregation(sales: [Transaction]) -> [ChartPoint] {
        var result: [ChartPoint] = []

        for i in stride(from: 6, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -i, to: Date()) else { continue }
            let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart)
            let quantity = totalQuantity(for: sales) { transaction in
                guard let interval else { return false }
                return transaction.date >= interval.start && transaction.date < interval.end
            }

            let label = (i == 0) ? "This" : "W\(7 - i)"
            result.append(ChartPoint(label: label, value: Double(quantity)))
        }

        return result
    }

    private func monthlyQuantityAggregation(sales: [Transaction]) -> [ChartPoint] {
        var result: [ChartPoint] = []

        for i in stride(from: 6, through: 0, by: -1) {
            guard let monthStart = calendar.date(byAdding: .month, value: -i, to: Date()) else { continue }
            let interval = calendar.dateInterval(of: .month, for: monthStart)
            let monthIndex = calendar.component(.month, from: monthStart) - 1
            let quantity = totalQuantity(for: sales) { transaction in
                guard let interval else { return false }
                return transaction.date >= interval.start && transaction.date < interval.end
            }

            result.append(ChartPoint(label: monthNames[monthIndex], value: Double(quantity)))
        }

        return result
    }

    private func yearlyQuantityAggregation(sales: [Transaction]) -> [ChartPoint] {
        let currentYear = calendar.component(.year, from: Date())
        var result: [ChartPoint] = []

        for year in (currentYear - 6)...currentYear {
            let quantity = totalQuantity(for: sales) { transaction in
                calendar.component(.year, from: transaction.date) == year
            }

            result.append(ChartPoint(label: "\(year)", value: Double(quantity)))
        }

        return result
    }

    // MARK: - Offset-Aware Aggregation Helpers (for comparison)

     func dailyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>, count: Int, offset: Int) -> [ChartPoint] {
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        var result: [ChartPoint] = []

        // The current-period labels (so both lines share x-axis)
        let currentLabels = dailyAggregation(sales: sales, keyPath: keyPath, count: count).map { $0.label }

        for i in stride(from: count - 1, through: 0, by: -1) {
            guard let targetDate = calendar.date(byAdding: .day, value: -(i + offset), to: now) else { continue }
            let dayStart = calendar.startOfDay(for: targetDate)
            let dayTotal = sales
                .filter { calendar.startOfDay(for: $0.date) == dayStart }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            let labelIndex = count - 1 - i
            let label = labelIndex < currentLabels.count ? currentLabels[labelIndex] : dayFormatter.string(from: targetDate)
            result.append(ChartPoint(label: label, value: dayTotal))
        }
        return result
    }

     func dailyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double], count: Int, offset: Int) -> [ChartPoint] {
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        var result: [ChartPoint] = []

        let currentLabels = dailyProfitAggregation(sales: sales, profitMap: profitMap, count: count).map { $0.label }

        for i in stride(from: count - 1, through: 0, by: -1) {
            guard let targetDate = calendar.date(byAdding: .day, value: -(i + offset), to: now) else { continue }
            let dayStart = calendar.startOfDay(for: targetDate)
            let dayTotal = sales
                .filter { calendar.startOfDay(for: $0.date) == dayStart }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            let labelIndex = count - 1 - i
            let label = labelIndex < currentLabels.count ? currentLabels[labelIndex] : dayFormatter.string(from: targetDate)
            result.append(ChartPoint(label: label, value: dayTotal))
        }
        return result
    }

     func weeklyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>, offset: Int) -> [ChartPoint] {
        let now = Date()
        var result: [ChartPoint] = []
        let currentLabels = weeklyAggregation(sales: sales, keyPath: keyPath).map { $0.label }

        for i in stride(from: 6, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -(i + offset), to: now) else { continue }
            let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart)
            let weekTotal = sales
                .filter { tx in
                    guard let interval = interval else { return false }
                    return tx.date >= interval.start && tx.date < interval.end
                }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            let labelIndex = 6 - i
            let label = labelIndex < currentLabels.count ? currentLabels[labelIndex] : "W \(7 - i)"
            result.append(ChartPoint(label: label, value: weekTotal))
        }
        return result
    }

     func weeklyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double], offset: Int) -> [ChartPoint] {
        let now = Date()
        var result: [ChartPoint] = []
        let currentLabels = weeklyProfitAggregation(sales: sales, profitMap: profitMap).map { $0.label }

        for i in stride(from: 6, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -(i + offset), to: now) else { continue }
            let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart)
            let weekTotal = sales
                .filter { tx in
                    guard let interval = interval else { return false }
                    return tx.date >= interval.start && tx.date < interval.end
                }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            let labelIndex = 6 - i
            let label = labelIndex < currentLabels.count ? currentLabels[labelIndex] : "W \(7 - i)"
            result.append(ChartPoint(label: label, value: weekTotal))
        }
        return result
    }

     func monthlyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>, offset: Int) -> [ChartPoint] {
        let now = Date()
        var result: [ChartPoint] = []

        for i in stride(from: 6, through: 0, by: -1) {
            guard let monthStart = calendar.date(byAdding: .month, value: -(i + offset), to: now) else { continue }
            let interval = calendar.dateInterval(of: .month, for: monthStart)
            let monthIndex = calendar.component(.month, from: monthStart) - 1
            let monthTotal = sales
                .filter { tx in
                    guard let interval = interval else { return false }
                    return tx.date >= interval.start && tx.date < interval.end
                }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            result.append(ChartPoint(label: monthNames[monthIndex], value: monthTotal))
        }
        return result
    }

     func monthlyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double], offset: Int) -> [ChartPoint] {
        let now = Date()
        var result: [ChartPoint] = []

        for i in stride(from: 6, through: 0, by: -1) {
            guard let monthStart = calendar.date(byAdding: .month, value: -(i + offset), to: now) else { continue }
            let interval = calendar.dateInterval(of: .month, for: monthStart)
            let monthIndex = calendar.component(.month, from: monthStart) - 1
            let monthTotal = sales
                .filter { tx in
                    guard let interval = interval else { return false }
                    return tx.date >= interval.start && tx.date < interval.end
                }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            result.append(ChartPoint(label: monthNames[monthIndex], value: monthTotal))
        }
        return result
    }

     func yearlyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>, offset: Int) -> [ChartPoint] {
        let currentYear = calendar.component(.year, from: Date())
        var result: [ChartPoint] = []

        for year in (currentYear - 6 - offset)...(currentYear - offset) {
            let yearTotal = sales
                .filter { calendar.component(.year, from: $0.date) == year }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            result.append(ChartPoint(label: "\(year + offset)", value: yearTotal))
        }
        return result
    }

     func yearlyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double], offset: Int) -> [ChartPoint] {
        let currentYear = calendar.component(.year, from: Date())
        var result: [ChartPoint] = []

        for year in (currentYear - 6 - offset)...(currentYear - offset) {
            let yearTotal = sales
                .filter { calendar.component(.year, from: $0.date) == year }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            result.append(ChartPoint(label: "\(year + offset)", value: yearTotal))
        }
        return result
    }
}
