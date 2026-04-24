
import UIKit

class SalesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    @IBOutlet weak var addEntryButton: UIButton!
    @IBOutlet weak var tableView: UITableView!
    let calendar = Calendar.current
    private var allTransactions: [(transaction: Transaction, itemsSummary: String)] = []
    private var filteredTransactions: [(transaction: Transaction, itemsSummary: String)] = []
    
    // Header view components
    let headerContainer = UIView()
    let transactionsLabel = UILabel()
    let datePicker = UIDatePicker()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.dataSource = self
        tableView.delegate = self
        tableView.sectionHeaderTopPadding = 0
        tableView.register(UINib(nibName: "ItemTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "ItemTableViewCell")
        
        tableView.register(UINib(nibName: "SalesTopTileTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "SalesTopTileTableViewCell")
        
        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSalesData()
    }

    private func presentSalesTypeSheet(from sourceView: UIView?) {
        let alert = UIAlertController(
            title: "Add Sale",
            message: "Choose how you want to record this sale.",
            preferredStyle: .actionSheet
        )

        alert.addAction(makeSalesAction(
            title: "Manual Entry",
            systemImageName: "square.and.pencil"
        ) { [weak self] in
            self?.openManualSalesEntry()
        })

        alert.addAction(makeSalesAction(
            title: "Voice Entry",
            systemImageName: "waveform"
        ) { [weak self] in
            self?.openVoiceSalesEntry()
        })

        alert.addAction(makeSalesAction(
            title: "Scan Sale",
            systemImageName: "camera.viewfinder"
        ) { [weak self] in
            self?.openScannedSalesEntry()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popoverPresentationController = alert.popoverPresentationController {
            popoverPresentationController.sourceView = sourceView ?? addEntryButton
            popoverPresentationController.sourceRect = sourceView?.bounds ?? addEntryButton.bounds
            popoverPresentationController.permittedArrowDirections = [.down, .up]
        }

        present(alert, animated: true)
    }

    private func makeSalesAction(
        title: String,
        systemImageName: String,
        handler: @escaping () -> Void
    ) -> UIAlertAction {
        let action = UIAlertAction(title: title, style: .default) { _ in
            handler()
        }

        if let image = UIImage(systemName: systemImageName) {
            action.setValue(image, forKey: "image")
        }

        return action
    }

    @IBAction func addEntryTapped(_ sender: UIButton) {
        presentSalesTypeSheet(from: sender)
    }

    private func openScannedSalesEntry() {
        salesScanButtonTapped(addEntryButton)
    }

    private func openManualSalesEntry() {
        performSegue(withIdentifier: "manual_sales", sender: nil)
    }

    private func openVoiceSalesEntry() {
        guard let voiceVC = storyboard?.instantiateViewController(
            withIdentifier: "VoiceEntryViewController"
        ) as? VoiceEntryViewController else {
            return
        }

        navigationController?.pushViewController(voiceVC, animated: true)
    }

    @IBAction func salesScanButtonTapped(_ sender: UIButton) {
        let scanVC = ScanCameraViewController(mode: .sale)
        scanVC.onSaleResult = { [weak self] result in
            guard let self = self else { return }
            guard let storyboard = self.storyboard,
                  let salesEntryVC = storyboard.instantiateViewController(withIdentifier: "SalesEntryTableViewController") as? SalesEntryTableViewController else { return }
            salesEntryVC.pendingResult = result
            salesEntryVC.entryMode = .camera
            self.navigationController?.pushViewController(salesEntryVC, animated: true)
        }
        let nav = UINavigationController(rootViewController: scanVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    @IBAction func manualSalesEntryTapped(_ sender: UIButton) {
        openManualSalesEntry()
    }

    @IBAction func voiceEntryTapped(_ sender: UIButton) {
        openVoiceSalesEntry()
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 1 else { return nil }
        
        let container = UIView()
        
        let label = UILabel()
        label.text = "Transactions"
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)
        
        let stack = UIStackView(arrangedSubviews: [label, UIView(), datePicker])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        
        return container
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return section == 1 ? 64 : 0
    }
    
    func loadSalesData() {
        let dm = AppDataModel.shared.dataModel
        let all = dm.getRecentTransactions(limit: 100)
        allTransactions = all.filter { $0.transaction.type == .sale }
        filterTransactions(for: datePicker.date)
    }
    
    func filterTransactions(for date: Date) {
        let startOfDay = calendar.startOfDay(for: date)
        filteredTransactions = allTransactions.filter {
            calendar.startOfDay(for: $0.transaction.date) == startOfDay
        }
        tableView.reloadData()
    }
    
    @objc private func dateChanged(_ sender: UIDatePicker) {
        filterTransactions(for: sender.date)
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        } else {
            return filteredTransactions.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SalesTopTileTableViewCell", for: indexPath) as! SalesTopTileTableViewCell
            cell.delegate = self
            let dm = AppDataModel.shared.dataModel
                    
            let revenue = dm.getTodayRevenue()
            let profit = dm.getTodayProfit()
                    
            let revenueString = String(format: "₹%.0f", revenue)
            let profitString = String(format: "₹%.0f", profit)
            
            var salesPercentChange: Double? = nil
            var profitPercentChange: Double? = nil
            
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())),
                let yesterdaySummary = try? dm.db.getDailySummary(for: yesterday) {
                salesPercentChange = revenue.percentChange(from: yesterdaySummary.totalRevenue)
                profitPercentChange = profit.percentChange(from: yesterdaySummary.totalProfit)
            }

            cell.configure(
                revenueAmount: revenueString,
                profitAmount: profitString,
                revenueReceipts: "\(dm.getTodaySaleCount()) receipts",
                profitItems: "\(dm.getTodayItemsSoldCount()) items",
                salesPercentChange: salesPercentChange,
                profitPercentChange: profitPercentChange
            )
            
            return cell
        }
        
        if indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ItemTableViewCell", for: indexPath) as! ItemTableViewCell
            
            let isFirst = indexPath.row == 0
            let isLast = indexPath.row == filteredTransactions.count - 1
            
            cell.applySectionCornerMask(isFirst: isFirst, isLast: isLast)
            
            let entry = filteredTransactions[indexPath.row]
            let tx = entry.transaction
            let type = "\(tx.type)"
            
            if type == "sale" && ((tx.customerName?.isEmpty) == nil) {
                cell.itemNameLabel.text = "Cash Sale"
            } else if type == "sale" && ((tx.customerName?.isEmpty) != nil) {
                cell.itemNameLabel.text = tx.customerName
            } else {
                cell.itemNameLabel.text = "Purchase"
            }
            var quantityLabelText = ""
            let details = tx.toBillingDetails()
            let itemCount = tx.toBillingDetails().items.count
            if let firstItem = details.items.first {
                quantityLabelText = "\(firstItem.itemName) x \(firstItem.quantity)"
                if itemCount > 1 {
                    quantityLabelText += " + \(itemCount - 1) more"
                }
                cell.quantityLabel.text = quantityLabelText
            } else {
                cell.quantityLabel.text = "Unknown"
            }
            
            cell.priceLabel.textColor = UIColor(named: "Lime Moss")!
            cell.priceLabel.text = "₹\(tx.totalAmount)"
            cell.separatorView.backgroundColor = .separator
            return cell
        }
        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 1 else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        let tx = filteredTransactions[indexPath.row].transaction
        presentBillSheet(for: tx)
    }
}
extension SalesViewController: SalesTopTileTableViewCell.SalesTopTileTableViewCellDelegate {
    
    func topTileCellDidTapRevenue(_ cell: SalesTopTileTableViewCell) {
        performSegue(withIdentifier: "revenue_segue", sender: cell)
    }
    func topTileCellDidTapProfit(_ cell: SalesTopTileTableViewCell) {
        performSegue(withIdentifier: "profit_segue", sender: cell)
    }
}
