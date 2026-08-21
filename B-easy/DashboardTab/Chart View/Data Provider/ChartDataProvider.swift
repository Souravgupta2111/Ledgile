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

    // MARK: - Period Enum

    enum Period: Int, CaseIterable {
        case daily = 0, monthly, quarterly, yearly
    }

    func getRevenueChartData(period: Period) -> [ChartPoint] {
        let sales = saleTransactions()

        switch period {
        case .daily:
            return dailyAggregation(sales: sales, keyPath: \.totalAmount, count: 7)
        case .monthly:
            return monthlyAggregation(sales: sales, keyPath: \.totalAmount)
        case .quarterly:
            return quarterlyAggregation(sales: sales, keyPath: \.totalAmount)
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
                return sum + Money.round2(
                    Money.line(quantity: item.quantity, rate: sell)
                        - Money.line(quantity: item.quantity, rate: cost)
                )
            }
            profitMap[tx.id] = profit
        }

        switch period {
        case .daily:
            return dailyProfitAggregation(sales: sales, profitMap: profitMap, count: 7)
        case .monthly:
            return monthlyProfitAggregation(sales: sales, profitMap: profitMap)
        case .quarterly:
            return quarterlyProfitAggregation(sales: sales, profitMap: profitMap)
        case .yearly:
            return yearlyProfitAggregation(sales: sales, profitMap: profitMap)
        }
    }
    
    func getPurchaseChartData(period: Period) -> [ChartPoint] {
        let purchases = purchaseTransactions()
        
        switch period {
        case .daily:
            return dailyAggregation(sales: purchases, keyPath: \.totalAmount, count: 7)
        case .monthly:
            return monthlyAggregation(sales: purchases, keyPath: \.totalAmount)
        case .quarterly:
            return quarterlyAggregation(sales: purchases, keyPath: \.totalAmount)
        case .yearly:
            return yearlyAggregation(sales: purchases, keyPath: \.totalAmount)
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
        case .monthly:
            return monthlyQuantityAggregation(sales: sales)
        case .quarterly:
            return quarterlyQuantityAggregation(sales: sales)
        case .yearly:
            return yearlyQuantityAggregation(sales: sales)
        }
    }

 
    func getProfitItems(period: Period) -> [ProfitItem] {
        let filteredSales = saleTransactions(startingAt: startDate(for: period))

        var aggregated: [UUID: (name: String, qty: Double, totalCost: Double, totalRevenue: Double)] = [:]

        for tx in filteredSales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let existing = aggregated[item.itemID] ?? (name: item.itemName, qty: 0, totalCost: 0, totalRevenue: 0)
                let itemCost = Money.line(quantity: item.quantity, rate: item.costPricePerUnit ?? 0)
                let itemRevenue = Money.line(quantity: item.quantity, rate: item.sellingPricePerUnit ?? 0)
                aggregated[item.itemID] = (
                    name: existing.name,
                    qty: existing.qty + item.quantity,
                    totalCost: existing.totalCost + itemCost,
                    totalRevenue: existing.totalRevenue + itemRevenue
                )
            }
        }

        return aggregated.map { itemID, data in
            let avgCost = data.qty > 0 ? data.totalCost / data.qty : 0
            let avgSell = data.qty > 0 ? data.totalRevenue / data.qty : 0
            return ProfitItem(
                itemID: itemID,
                name: data.name,
                quantity: data.qty,
                costPrice: avgCost,
                sellingPrice: avgSell
            )
        }.sorted { $0.totalProfit > $1.totalProfit }
    }

    /// Returns sales items for the given period, sorted by total revenue (quantity × selling price).
    func getSalesItems(period: Period) -> [ProfitItem] {
        let filteredSales = saleTransactions(startingAt: startDate(for: period))

        var aggregated: [UUID: (name: String, qty: Double, totalCost: Double, totalRevenue: Double)] = [:]

        for tx in filteredSales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let existing = aggregated[item.itemID] ?? (name: item.itemName, qty: 0, totalCost: 0, totalRevenue: 0)
                let itemCost = Money.line(quantity: item.quantity, rate: item.costPricePerUnit ?? 0)
                let itemRevenue = Money.line(quantity: item.quantity, rate: item.sellingPricePerUnit ?? 0)
                aggregated[item.itemID] = (
                    name: existing.name,
                    qty: existing.qty + item.quantity,
                    totalCost: existing.totalCost + itemCost,
                    totalRevenue: existing.totalRevenue + itemRevenue
                )
            }
        }

        return aggregated.map { itemID, data in
            let avgCost = data.qty > 0 ? data.totalCost / data.qty : 0
            let avgSell = data.qty > 0 ? data.totalRevenue / data.qty : 0
            return ProfitItem(
                itemID: itemID,
                name: data.name,
                quantity: data.qty,
                costPrice: avgCost,
                sellingPrice: avgSell
            )
        }.sorted(by: sortItemsByQuantityThenRevenue)
    }

    func getPurchaseItems(period: Period) -> [ProfitItem] {
        let filteredPurchases = purchaseTransactions(startingAt: startDate(for: period))

        var aggregated: [UUID: (name: String, qty: Double, totalCost: Double, totalRevenue: Double)] = [:]

        for tx in filteredPurchases {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let existing = aggregated[item.itemID] ?? (name: item.itemName, qty: 0, totalCost: 0, totalRevenue: 0)
                let itemCost = Money.line(quantity: item.quantity, rate: item.costPricePerUnit ?? 0)
                let itemRevenue = Money.line(quantity: item.quantity, rate: item.sellingPricePerUnit ?? 0)
                aggregated[item.itemID] = (
                    name: existing.name,
                    qty: existing.qty + item.quantity,
                    totalCost: existing.totalCost + itemCost,
                    totalRevenue: existing.totalRevenue + itemRevenue
                )
            }
        }

        return aggregated.map { itemID, data in
            let avgCost = data.qty > 0 ? data.totalCost / data.qty : 0
            let avgSell = data.qty > 0 ? data.totalRevenue / data.qty : 0
            return ProfitItem(
                itemID: itemID,
                name: data.name,
                quantity: data.qty,
                costPrice: avgCost,
                sellingPrice: avgSell
            )
        }.sorted { ($0.costPrice * $0.quantity) > ($1.costPrice * $1.quantity) }
    }
   
    func getSalesItems() -> [ProfitItem] {
        let sales = saleTransactions()

        var aggregated: [UUID: (name: String, qty: Double, totalCost: Double, totalRevenue: Double)] = [:]

        for tx in sales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                let existing = aggregated[item.itemID] ?? (name: item.itemName, qty: 0, totalCost: 0, totalRevenue: 0)
                let itemCost = Money.line(quantity: item.quantity, rate: item.costPricePerUnit ?? 0)
                let itemRevenue = Money.line(quantity: item.quantity, rate: item.sellingPricePerUnit ?? 0)
                aggregated[item.itemID] = (
                    name: existing.name,
                    qty: existing.qty + item.quantity,
                    totalCost: existing.totalCost + itemCost,
                    totalRevenue: existing.totalRevenue + itemRevenue
                )
            }
        }

        return aggregated.map { itemID, data in
            let avgCost = data.qty > 0 ? data.totalCost / data.qty : 0
            let avgSell = data.qty > 0 ? data.totalRevenue / data.qty : 0
            return ProfitItem(
                itemID: itemID,
                name: data.name,
                quantity: data.qty,
                costPrice: avgCost,
                sellingPrice: avgSell
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
     let monthLetters = ["J","F","M","A","M","J","J","A","S","O","N","D"]

     func monthlyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>) -> [ChartPoint] {
        let now = Date()
        var result: [ChartPoint] = []

        for i in stride(from: 11, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            guard let interval = calendar.dateInterval(of: .month, for: date) else { continue }
            let monthIndex = calendar.component(.month, from: date) - 1

            let monthTotal = sales
                .filter { $0.date >= interval.start && $0.date < interval.end }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            result.append(ChartPoint(label: monthLetters[monthIndex], value: monthTotal))
        }

        return result
    }

     func monthlyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double]) -> [ChartPoint] {
        let now = Date()
        var result: [ChartPoint] = []

        for i in stride(from: 11, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            guard let interval = calendar.dateInterval(of: .month, for: date) else { continue }
            let monthIndex = calendar.component(.month, from: date) - 1

            let monthTotal = sales
                .filter { $0.date >= interval.start && $0.date < interval.end }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            result.append(ChartPoint(label: monthLetters[monthIndex], value: monthTotal))
        }

        return result
    }

     func yearlyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>) -> [ChartPoint] {
        let currentYear = calendar.component(.year, from: Date())
        var result: [ChartPoint] = []

        for year in (currentYear - 5)...currentYear {
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

        for year in (currentYear - 5)...currentYear {
            let yearTotal = sales
                .filter { calendar.component(.year, from: $0.date) == year }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            result.append(ChartPoint(label: "\(year)", value: yearTotal))
        }

        return result
    }

  
    func comparisonLabel(for period: Period) -> String {
        switch period {
        case .daily:     return "from yesterday"
        case .monthly:   return "from last month"
        case .quarterly: return "from last quarter"
        case .yearly:    return "from last year"
        }
    }

    // MARK: - Period-Specific Growth Calculation

    /// Calculates percentage growth for the current period vs the immediately preceding period.
    /// Daily: today vs yesterday, Monthly: this month vs last month, Quarterly: this quarter vs last quarter, Yearly: this year vs last year.
    func periodGrowth(for period: Period, metric: PeriodMetric) -> String {
        let (current, previous) = periodTotals(for: period, metric: metric)
        return formatGrowth(current: current, previous: previous)
    }

    enum PeriodMetric {
        case revenue
        case profit
    }

    private func periodTotals(for period: Period, metric: PeriodMetric) -> (current: Double, previous: Double) {
        let sales = saleTransactions()
        let now = Date()

        switch period {
        case .daily:
            let todayStart = calendar.startOfDay(for: now)
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

            let todayTotal = aggregateTotal(sales: sales, from: todayStart, to: now, metric: metric)
            let yesterdayTotal = aggregateTotal(sales: sales, from: yesterdayStart, to: todayStart, metric: metric)
            return (todayTotal, yesterdayTotal)

        case .monthly:
            guard let thisMonthInterval = calendar.dateInterval(of: .month, for: now) else { return (0, 0) }
            let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now)!
            guard let lastMonthInterval = calendar.dateInterval(of: .month, for: lastMonthDate) else { return (0, 0) }

            let thisTotal = aggregateTotal(sales: sales, from: thisMonthInterval.start, to: thisMonthInterval.end, metric: metric)
            let lastTotal = aggregateTotal(sales: sales, from: lastMonthInterval.start, to: lastMonthInterval.end, metric: metric)
            return (thisTotal, lastTotal)

        case .quarterly:
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            let currentQ = (currentMonth - 1) / 3  // 0-based quarter index

            let (cStart, cEnd) = quarterRange(year: currentYear, quarter: currentQ)

            // Previous quarter
            let prevQ = currentQ == 0 ? 3 : currentQ - 1
            let prevYear = currentQ == 0 ? currentYear - 1 : currentYear
            let (pStart, pEnd) = quarterRange(year: prevYear, quarter: prevQ)

            let thisTotal = aggregateTotal(sales: sales, from: cStart, to: cEnd, metric: metric)
            let lastTotal = aggregateTotal(sales: sales, from: pStart, to: pEnd, metric: metric)
            return (thisTotal, lastTotal)

        case .yearly:
            let currentYear = calendar.component(.year, from: now)
            let thisYearStart = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1))!
            let thisYearEnd = calendar.date(from: DateComponents(year: currentYear + 1, month: 1, day: 1))!
            let lastYearStart = calendar.date(from: DateComponents(year: currentYear - 1, month: 1, day: 1))!
            let lastYearEnd = thisYearStart

            let thisTotal = aggregateTotal(sales: sales, from: thisYearStart, to: thisYearEnd, metric: metric)
            let lastTotal = aggregateTotal(sales: sales, from: lastYearStart, to: lastYearEnd, metric: metric)
            return (thisTotal, lastTotal)
        }
    }

    private func quarterRange(year: Int, quarter: Int) -> (start: Date, end: Date) {
        let startMonth = quarter * 3 + 1
        let qStart = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1))!
        let qEnd = calendar.date(from: DateComponents(year: year, month: startMonth + 3, day: 1)) ?? qStart
        return (qStart, qEnd)
    }

    private func aggregateTotal(sales: [Transaction], from start: Date, to end: Date, metric: PeriodMetric) -> Double {
        let filtered = sales.filter { $0.date >= start && $0.date < end }
        switch metric {
        case .revenue:
            return filtered.reduce(0.0) { $0 + $1.totalAmount }
        case .profit:
            return filtered.reduce(0.0) { sum, tx in
                let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
                let profit = items.reduce(0.0) { s, item in
                    let sell = item.sellingPricePerUnit ?? 0
                    let cost = item.costPricePerUnit ?? 0
                    return s + Money.round2(
                        Money.line(quantity: item.quantity, rate: sell)
                            - Money.line(quantity: item.quantity, rate: cost)
                    )
                }
                return sum + profit
            }
        }
    }

    private func formatGrowth(current: Double, previous: Double) -> String {
        if previous == 0 {
            return current > 0 ? "+100%" : "0%"
        }
        let growth = ((current - previous) / previous) * 100
        let sign = growth >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", growth))%"
    }

   
    func getComparisonRevenueChartData(period: Period) -> [ChartPoint] {
        let sales = saleTransactions()

        switch period {
        case .daily:
            return dailyAggregation(sales: sales, keyPath: \.totalAmount, count: 7, offset: 7)
        case .monthly:
            return monthlyAggregation(sales: sales, keyPath: \.totalAmount, yearOffset: 1)
        case .quarterly:
            return quarterlyAggregation(sales: sales, keyPath: \.totalAmount, yearOffset: 1)
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
                return sum + Money.round2(
                    Money.line(quantity: item.quantity, rate: sell)
                        - Money.line(quantity: item.quantity, rate: cost)
                )
            }
            profitMap[tx.id] = profit
        }

        switch period {
        case .daily:
            return dailyProfitAggregation(sales: sales, profitMap: profitMap, count: 7, offset: 7)
        case .monthly:
            return monthlyProfitAggregation(sales: sales, profitMap: profitMap, yearOffset: 1)
        case .quarterly:
            return quarterlyProfitAggregation(sales: sales, profitMap: profitMap, yearOffset: 1)
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

    private func purchaseTransactions(startingAt startDate: Date? = nil) -> [Transaction] {
        let transactions = (try? dm.db.getTransactions()) ?? []
        return transactions.filter { transaction in
            guard transaction.type == .purchase else { return false }
            guard let startDate = startDate else { return true }
            return transaction.date >= startDate
        }
    }

    private func startDate(for period: Period) -> Date {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: now)

        switch period {
        case .daily:
            return today
        case .monthly:
            let elevenMonthsAgo = calendar.date(byAdding: .month, value: -11, to: today) ?? today
            var comps = calendar.dateComponents([.year, .month], from: elevenMonthsAgo)
            comps.day = 1
            return calendar.date(from: comps) ?? today
        case .quarterly:
            var comps = DateComponents()
            comps.year = currentYear
            comps.month = 1
            comps.day = 1
            return calendar.date(from: comps) ?? today
        case .yearly:
            return calendar.date(byAdding: .day, value: -364, to: today) ?? today
        }
    }

    private func totalQuantity(for sales: [Transaction], matching predicate: (Transaction) -> Bool) -> Int {
        let matchingSales = sales.filter(predicate)
        var uniqueItems = Set<UUID>()
        for tx in matchingSales {
            let items = (try? dm.db.getTransactionItems(for: tx.id)) ?? []
            for item in items {
                uniqueItems.insert(item.itemID)
            }
        }
        return uniqueItems.count
    }

    private func sortItemsByQuantityThenRevenue(_ lhs: ProfitItem, _ rhs: ProfitItem) -> Bool {
        if lhs.quantity != rhs.quantity {
            return lhs.quantity > rhs.quantity
        }

        let lhsRevenue = lhs.sellingPrice * lhs.quantity
        let rhsRevenue = rhs.sellingPrice * rhs.quantity
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
        let now = Date()
        var result: [ChartPoint] = []

        for i in stride(from: 11, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            guard let interval = calendar.dateInterval(of: .month, for: date) else { continue }
            let monthIndex = calendar.component(.month, from: date) - 1

            let quantity = totalQuantity(for: sales) { tx in
                tx.date >= interval.start && tx.date < interval.end
            }

            result.append(ChartPoint(label: monthLetters[monthIndex], value: Double(quantity)))
        }

        return result
    }

    private func yearlyQuantityAggregation(sales: [Transaction]) -> [ChartPoint] {
        let currentYear = calendar.component(.year, from: Date())
        var result: [ChartPoint] = []

        for year in (currentYear - 5)...currentYear {
            let quantity = totalQuantity(for: sales) { transaction in
                calendar.component(.year, from: transaction.date) == year
            }

            result.append(ChartPoint(label: "\(year)", value: Double(quantity)))
        }

        return result
    }

    // MARK: - Quarterly Aggregation

    func quarterlyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>) -> [ChartPoint] {
        let currentYear = calendar.component(.year, from: Date())
        let quarterLabels = ["Q1", "Q2", "Q3", "Q4"]
        var result: [ChartPoint] = []

        for q in 0..<4 {
            let startMonth = q * 3 + 1
            var startComps = DateComponents()
            startComps.year = currentYear
            startComps.month = startMonth
            startComps.day = 1
            guard let qStart = calendar.date(from: startComps) else { continue }

            var endComps = DateComponents()
            endComps.year = currentYear
            endComps.month = startMonth + 3
            endComps.day = 1
            let qEnd = calendar.date(from: endComps) ?? qStart

            let total = sales
                .filter { $0.date >= qStart && $0.date < qEnd }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            result.append(ChartPoint(label: quarterLabels[q], value: total))
        }
        return result
    }

    func quarterlyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>, yearOffset: Int) -> [ChartPoint] {
        let targetYear = calendar.component(.year, from: Date()) - yearOffset
        let quarterLabels = ["Q1", "Q2", "Q3", "Q4"]
        var result: [ChartPoint] = []

        for q in 0..<4 {
            let startMonth = q * 3 + 1
            var startComps = DateComponents()
            startComps.year = targetYear
            startComps.month = startMonth
            startComps.day = 1
            guard let qStart = calendar.date(from: startComps) else { continue }

            var endComps = DateComponents()
            endComps.year = targetYear
            endComps.month = startMonth + 3
            endComps.day = 1
            let qEnd = calendar.date(from: endComps) ?? qStart

            let total = sales
                .filter { $0.date >= qStart && $0.date < qEnd }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            result.append(ChartPoint(label: quarterLabels[q], value: total))
        }
        return result
    }

    func quarterlyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double]) -> [ChartPoint] {
        let currentYear = calendar.component(.year, from: Date())
        let quarterLabels = ["Q1", "Q2", "Q3", "Q4"]
        var result: [ChartPoint] = []

        for q in 0..<4 {
            let startMonth = q * 3 + 1
            var startComps = DateComponents()
            startComps.year = currentYear
            startComps.month = startMonth
            startComps.day = 1
            guard let qStart = calendar.date(from: startComps) else { continue }

            var endComps = DateComponents()
            endComps.year = currentYear
            endComps.month = startMonth + 3
            endComps.day = 1
            let qEnd = calendar.date(from: endComps) ?? qStart

            let total = sales
                .filter { $0.date >= qStart && $0.date < qEnd }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            result.append(ChartPoint(label: quarterLabels[q], value: total))
        }
        return result
    }

    func quarterlyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double], yearOffset: Int) -> [ChartPoint] {
        let targetYear = calendar.component(.year, from: Date()) - yearOffset
        let quarterLabels = ["Q1", "Q2", "Q3", "Q4"]
        var result: [ChartPoint] = []

        for q in 0..<4 {
            let startMonth = q * 3 + 1
            var startComps = DateComponents()
            startComps.year = targetYear
            startComps.month = startMonth
            startComps.day = 1
            guard let qStart = calendar.date(from: startComps) else { continue }

            var endComps = DateComponents()
            endComps.year = targetYear
            endComps.month = startMonth + 3
            endComps.day = 1
            let qEnd = calendar.date(from: endComps) ?? qStart

            let total = sales
                .filter { $0.date >= qStart && $0.date < qEnd }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            result.append(ChartPoint(label: quarterLabels[q], value: total))
        }
        return result
    }

    private func quarterlyQuantityAggregation(sales: [Transaction]) -> [ChartPoint] {
        let currentYear = calendar.component(.year, from: Date())
        let quarterLabels = ["Q1", "Q2", "Q3", "Q4"]
        var result: [ChartPoint] = []

        for q in 0..<4 {
            let startMonth = q * 3 + 1
            var startComps = DateComponents()
            startComps.year = currentYear
            startComps.month = startMonth
            startComps.day = 1
            guard let qStart = calendar.date(from: startComps) else { continue }

            var endComps = DateComponents()
            endComps.year = currentYear
            endComps.month = startMonth + 3
            endComps.day = 1
            let qEnd = calendar.date(from: endComps) ?? qStart

            let quantity = totalQuantity(for: sales) { tx in
                tx.date >= qStart && tx.date < qEnd
            }

            result.append(ChartPoint(label: quarterLabels[q], value: Double(quantity)))
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

     func monthlyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>, yearOffset: Int) -> [ChartPoint] {
        let now = Date()
        guard let targetDate = calendar.date(byAdding: .year, value: -yearOffset, to: now) else { return [] }
        var result: [ChartPoint] = []

        for i in stride(from: 11, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -i, to: targetDate) else { continue }
            guard let interval = calendar.dateInterval(of: .month, for: date) else { continue }
            let monthIndex = calendar.component(.month, from: date) - 1

            let monthTotal = sales
                .filter { $0.date >= interval.start && $0.date < interval.end }
                .reduce(0.0) { $0 + $1[keyPath: keyPath] }

            result.append(ChartPoint(label: monthLetters[monthIndex], value: monthTotal))
        }
        return result
    }

     func monthlyProfitAggregation(sales: [Transaction], profitMap: [UUID: Double], yearOffset: Int) -> [ChartPoint] {
        let now = Date()
        guard let targetDate = calendar.date(byAdding: .year, value: -yearOffset, to: now) else { return [] }
        var result: [ChartPoint] = []

        for i in stride(from: 11, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -i, to: targetDate) else { continue }
            guard let interval = calendar.dateInterval(of: .month, for: date) else { continue }
            let monthIndex = calendar.component(.month, from: date) - 1

            let monthTotal = sales
                .filter { $0.date >= interval.start && $0.date < interval.end }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            result.append(ChartPoint(label: monthLetters[monthIndex], value: monthTotal))
        }
        return result
    }

     func yearlyAggregation(sales: [Transaction], keyPath: KeyPath<Transaction, Double>, offset: Int) -> [ChartPoint] {
        let currentYear = calendar.component(.year, from: Date())
        var result: [ChartPoint] = []

        for year in (currentYear - 5 - offset)...(currentYear - offset) {
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

        for year in (currentYear - 5 - offset)...(currentYear - offset) {
            let yearTotal = sales
                .filter { calendar.component(.year, from: $0.date) == year }
                .reduce(0.0) { $0 + (profitMap[$1.id] ?? 0) }

            result.append(ChartPoint(label: "\(year + offset)", value: yearTotal))
        }
        return result
    }
}
