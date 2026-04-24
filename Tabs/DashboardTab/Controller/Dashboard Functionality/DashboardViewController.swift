import UIKit
import DGCharts
import QuickLook

class DashboardViewController: UIViewController {

    // MARK: - Reports
    private let reportTypes: [ReportType] = ReportType.allCases
    private var pdfPreviewDataSource: PDFPreviewDataSource?
    struct WeekData {
        var revenue: Double
        var investment: Double
    }
    
    var recentTransactions: [(transaction: Transaction, itemsSummary: String)] = []
    var filteredTransactions: [(transaction: Transaction, itemsSummary: String)] = []
    var weeklyData: [String: WeekData] = [:]
    let orderedDays = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
    let calendar = Calendar.current
    let datePicker = UIDatePicker()
    @IBOutlet var tableView: UITableView!

    override func viewDidLoad() {
        tableView.backgroundColor = .systemGray6
        super.viewDidLoad()
        self.additionalSafeAreaInsets.top = 0
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemGray6
        tableView.sectionHeaderTopPadding = 0
        tableView.register(UINib(nibName: "ItemTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "ItemTableViewCell")
        
        tableView.register(UINib(nibName: "DashboardTopTileTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "DashboardTopTileTableViewCell")
        
        tableView.register(UINib(nibName: "LabelTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "LabelTableViewCell")
        tableView.register(UINib(nibName: "EmptyTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "EmptyTableViewCell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.separatorStyle = .none
        loadSalesData()
        loadWeeklyChartData()
        showLargeTitleProfileButton()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hideLargeTitleProfileButton()
    }
    
    
    private func loadWeeklyChartData() {
        let cal = Calendar.current
        let now = Date()
        let dm = AppDataModel.shared.dataModel
        weeklyData = [:]

        for i in 0..<7 {
            let day = cal.date(byAdding: .day, value: -i, to: now)!
            let dayName = orderedDays[cal.component(.weekday, from: day) - 1]

            if let summary = try? dm.db.getDailySummary(for: day) {
                weeklyData[dayName] = WeekData(
                    revenue: summary.totalRevenue,
                    investment: summary.totalPurchaseAmount
                )
            } else {
                weeklyData[dayName] = WeekData(revenue: 0, investment: 0)
            }
        }
    }
    
    func loadSalesData() {
        let dm = AppDataModel.shared.dataModel
        let all = dm.getRecentTransactions(limit: 100)
        recentTransactions = all
        filterTransactions(for: datePicker.date)
    }
    func filterTransactions(for date: Date) {
        filteredTransactions = Array(recentTransactions.prefix(3))
        tableView.reloadData()
    }
    
    @objc func didTapViewAllTransactions() {
        performSegue(withIdentifier: "recent_transactions", sender: nil)
    }
}

extension DashboardViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 1
        case 1:
            return filteredTransactions.isEmpty ? 1 : min(3, filteredTransactions.count)
        case 2:
            return min(4, reportTypes.count) 
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let dm = AppDataModel.shared.dataModel
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "DashboardTopTileTableViewCell",
                for: indexPath
            ) as! DashboardTopTileTableViewCell
            let revenue = dm.getFinancialYearRevenue()
            let profit = dm.getTodayProfit()
            let lowStockCount = (try? dm.getLowStockAlerts()) ?? []
            let expiryAlerts = (try? dm.getExpiryAlerts()) ?? []
            
            let youWillGet = CreditStore.shared.getTotalReceivable()
            let youWillPay = CreditStore.shared.getTotalPayable()
            
            let investment = dm.getFinancialYearInvestment()

            cell.configure(
                revenueAmount: String(format: "₹%.0f", revenue),
                investmentAmount: String(format: "₹%.0f", investment),
                lowStockCountText: "\(lowStockCount.count) items need restocking",
                expiryCountText: "\(expiryAlerts.count) items expiring soon",
                youWillGetAmount: youWillGet,
                youWillPayAmount: youWillPay
            )
            
            let mappedWeeklyData: [String: DashboardTopTileTableViewCell.WeekData] = weeklyData.reduce(into: [:]) { dict, pair in
                dict[pair.key] = DashboardTopTileTableViewCell.WeekData(
                    revenue: pair.value.revenue,
                    investment: pair.value.investment
                )
            }
            cell.configureCharts(with: mappedWeeklyData)
            
            cell.revenueTapped = { [weak self] in
                self?.performSegue(withIdentifier: "sales_by_item", sender: nil)
            }
            cell.investmentTapped = { [weak self] in
                self?.performSegue(withIdentifier: "stock_report", sender: nil)
            }
            cell.lowStockTapped = { [weak self] in
                self?.performSegue(withIdentifier: "low_stock", sender: nil)
            }
            cell.expiryTapped = { [weak self] in
                self?.navigateToExpiryAlerts()
            }
            cell.manualSalesTapped = { [weak self] in
                self?.performSegue(withIdentifier: "manual_sales_from_dashboard", sender: nil)
            }
            cell.voiceSalesTapped = { [weak self] in
                self?.performSegue(withIdentifier: "voice_sales_from_dashboard", sender: nil)
            }
            cell.manualPurchaseTapped = { [weak self] in
                self?.performSegue(withIdentifier: "manual_purchase_from_dashboard", sender: nil)
            }
            cell.objectPurchaseTapped = { [weak self] in
                    guard let self = self else { return }
                    let scanVC = ScanCameraViewController(mode: .purchase)
                    scanVC.onPurchaseResult = { [weak self] result in
                        guard let self = self,
                              let storyboard = self.storyboard,
                              let purchaseVC = storyboard.instantiateViewController(withIdentifier: "AddPurchaseViewController") as? AddPurchaseViewController else { return }
                        let parsedResult = ParsedResult(
                            entities: [],
                            products: result.items.map { item in
                                (name: item.name,
                                 quantity: item.quantity,
                                 unit: item.unit,
                                 price: item.sellingPrice,
                                 costPrice: item.costPrice)
                            },
                            customerName: result.supplierName,
                            isNegation: false,
                            isReference: false,
                            productItemIDs: nil,
                            productConfidences: nil
                        )
                        purchaseVC.pendingResult = parsedResult
                        self.navigationController?.pushViewController(purchaseVC, animated: true)
                    }
                    let nav = UINavigationController(rootViewController: scanVC)
                    nav.modalPresentationStyle = .fullScreen
                    self.present(nav, animated: true)
            }
            cell.getTapped = { [weak self] in
                self?.performSegue(withIdentifier: "you_will_get", sender: nil)
            }
            cell.payTapped = { [weak self] in
                self?.performSegue(withIdentifier: "you_will_pay", sender: nil)
            }
            return cell
        }
        if indexPath.section == 1 {
            let transactionCount = filteredTransactions.count
            if transactionCount == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "EmptyTableViewCell", for: indexPath) as! EmptyTableViewCell
                cell.titleLabel.text = "No recent transactions"
                cell.applySectionCornerMask(isFirst: true, isLast: true)
                
                return cell
            }
            else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "ItemTableViewCell", for: indexPath) as! ItemTableViewCell
                
                let maxRows = min(3, filteredTransactions.count)
                let isFirst = indexPath.row == 0
                let isLast = indexPath.row == maxRows - 1
                
                cell.applySectionCornerMask(isFirst: isFirst, isLast: isLast)
                
                let entry = filteredTransactions[indexPath.row]
                let tx = entry.transaction
                if tx.type == .purchase {
                    cell.itemNameLabel.text = "Purchase"
                } else if let name = tx.customerName, !name.isEmpty {
                    cell.itemNameLabel.text = name
                } else {
                    cell.itemNameLabel.text = "Cash Sale"
                }
                
                let details = tx.toBillingDetails()
                let itemCount = details.items.count
                if let firstItem = details.items.first {
                    var quantityLabelText = "\(firstItem.itemName) x \(firstItem.quantity)"
                    if itemCount > 1 {
                        quantityLabelText += " + \(itemCount - 1) more"
                    }
                    cell.quantityLabel.text = quantityLabelText
                } else {
                    cell.quantityLabel.text = "Unknown"
                }
                
                cell.priceLabel.textColor = tx.type == .purchase ? .systemRed : UIColor(named: "Lime Moss")!
                cell.priceLabel.text = "₹\(tx.totalAmount)"
                cell.separatorView.backgroundColor = .separator
                return cell
            }

        }
        if indexPath.section == 2 {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "LabelTableViewCell",
                for: indexPath
            ) as! LabelTableViewCell

            let visibleCount = min(4, reportTypes.count)
            let isFirst = indexPath.row == 0
            let isLast = indexPath.row == visibleCount - 1

            cell.applyCornerMask(isFirst: isFirst, isLast: isLast)

            let report = reportTypes[indexPath.row]
            cell.titleLabel.text = report.rawValue
            cell.selectionStyle = .default

            return cell
        }
        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return nil
        case 1: return "Recent Transactions"
        case 2: return "Reports"
        default: return nil
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 1 || section == 2 else {
            return UIView()
        }

        let container = UIView()
        container.backgroundColor = .clear

        let titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label

        let button = UIButton(type: .system)
        button.setTitle("View All", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        button.tintColor = .limeMoss

        if section == 1 {
            titleLabel.text = "Recent Transactions"
            button.addTarget(self, action: #selector(didTapViewAllTransactions), for: .touchUpInside)
        } else {
            titleLabel.text = "Reports"
            button.addTarget(self, action: #selector(didTapViewAllReports), for: .touchUpInside)
        }

        let stack = UIStackView(arrangedSubviews: [titleLabel, UIView(), button])
        stack.axis = .horizontal
        stack.alignment = .center

        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: -3),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3)
        ])

        return container
    }
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
            header.textLabel?.textColor = .label
            header.contentView.backgroundColor = .clear
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            if section == 1 || section == 2 { return 48 }
            return CGFloat.leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 1, indexPath.row < filteredTransactions.count {
            let tx = filteredTransactions[indexPath.row].transaction
            presentBillSheet(for: tx)
        }
        else if indexPath.section == 2 {
            let report = reportTypes[indexPath.row]
            handleReportTap(report)
        }
    }
    

    @objc func didTapViewAllReports() {
        performSegue(withIdentifier: "reports_segue", sender: nil)
    }
}


extension DashboardViewController: QLPreviewControllerDataSource {

    func handleReportTap(_ report: ReportType) {
        if report.needsDateRange {

            guard let picker = storyboard?.instantiateViewController(
                withIdentifier: "ReportDatePickerViewController"
            ) as? ReportDatePickerViewController else {
                return
            }

            picker.reportType = report
            picker.onGenerate = { [weak self] from, to in
                self?.generateAndPreview(report: report, from: from, to: to)
            }

            present(picker, animated: true)
        } else {
            let cal = Calendar.current
            let from = cal.date(byAdding: .year, value: -10, to: Date()) ?? Date()
            generateAndPreview(report: report, from: from, to: Date())
        }
    }

    private func generateAndPreview(report: ReportType, from: Date, to: Date) {
        guard let pdfURL = ReportGenerator.shared.generateReport(type: report, from: from, to: to) else {
            let alert = UIAlertController(title: "Error", message: "Failed to generate report.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let item = PDFPreviewItem(url: pdfURL, name: report.rawValue)
        pdfPreviewDataSource = PDFPreviewDataSource(item: item)

        let ql = QLPreviewController()
        ql.dataSource = self
        present(ql, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        pdfPreviewDataSource?.item ?? PDFPreviewItem(url: URL(fileURLWithPath: ""), name: "")
    }
}

extension DashboardViewController {
    func refreshCharts() {
        let indexPath = IndexPath(row: 0, section: 0)
        if let cell = tableView.cellForRow(at: indexPath) as? DashboardTopTileTableViewCell {
            let mappedWeeklyData: [String: DashboardTopTileTableViewCell.WeekData] = weeklyData.reduce(into: [:]) { dict, pair in
                dict[pair.key] = DashboardTopTileTableViewCell.WeekData(
                    revenue: pair.value.revenue,
                    investment: pair.value.investment
                )
            }
            cell.configureCharts(with: mappedWeeklyData)
        } else {
            if tableView.numberOfSections > 0 && tableView.numberOfRows(inSection: 0) > 0 {
                tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
    }
    func updateChartData(for day: String, revenue: Double, investment: Double) {
        weeklyData[day] = WeekData(revenue: revenue, investment: investment)
        refreshCharts()
    }

    private func navigateToExpiryAlerts() {
        if let vc = storyboard?.instantiateViewController(withIdentifier: "ExpiryTableViewController") as? ExpiryTableViewController {
            self.navigationController?.pushViewController(vc, animated: true)
        } else {
            // Fallback to segue if ID is missing (though we'll add the ID next)
            self.performSegue(withIdentifier: "expiry_segue", sender: nil)
        }
    }
}

