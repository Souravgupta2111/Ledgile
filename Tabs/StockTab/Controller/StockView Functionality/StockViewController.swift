import UIKit

class StockViewController: UIViewController {
    @IBOutlet private weak var addStockButton: UIButton!
    @IBOutlet private weak var blurEffectView: UIVisualEffectView!
    @IBOutlet private weak var tableView: UITableView!
    
    var items: [Item] = []
    private let dm = AppDataModel.shared.dataModel

    override func viewDidLoad() {
            super.viewDidLoad()
            
            tableView.separatorStyle = .none
            tableView.backgroundColor = .systemGray6
            tableView.showsVerticalScrollIndicator = false
            tableView.rowHeight = UITableView.automaticDimension
            tableView.estimatedRowHeight = 120
            
            tableView.dataSource = self
            tableView.delegate = self
            
            tableView.register(UINib(nibName: "TopTileTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "TopTileTableViewCell")

            tableView.register(UINib(nibName: "AlertTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "AlertTableViewCell")
            
            tableView.register(UINib(nibName: "ItemTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "ItemTableViewCell")
            reloadItems()
        }



    private func presentPurchaseTypeSheet(from sourceView: UIView?) {
        let alert = UIAlertController(
            title: "Add Stock",
            message: "Choose how you want to record this purchase.",
            preferredStyle: .actionSheet
        )

        alert.addAction(makePurchaseAction(
            title: "Manual Entry",
            systemImageName: "square.and.pencil"
        ) { [weak self] in
            self?.openManualPurchaseEntry()
        })

        alert.addAction(makePurchaseAction(
            title: "Voice Entry",
            systemImageName: "waveform"
        ) { [weak self] in
            self?.openVoicePurchaseEntry()
        })

        alert.addAction(makePurchaseAction(
            title: "Scan Purchase",
            systemImageName: "camera.viewfinder"
        ) { [weak self] in
            self?.scanPurchaseTapped()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popoverPresentationController = alert.popoverPresentationController {
            popoverPresentationController.sourceView = sourceView ?? addStockButton
            popoverPresentationController.sourceRect = sourceView?.bounds ?? addStockButton.bounds
            popoverPresentationController.permittedArrowDirections = [.down, .up]
        }

        present(alert, animated: true)
    }

    private func makePurchaseAction(
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

    private func openManualPurchaseEntry() {
        performSegue(withIdentifier: "AddPurchaseFromStock", sender: nil)
    }

    private func openVoicePurchaseEntry() {
        guard let voiceVC = storyboard?.instantiateViewController(
            withIdentifier: "VoicePurchaseEntryViewController"
        ) as? VoicePurchaseEntryViewController else {
            return
        }

        navigationController?.pushViewController(voiceVC, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadItems()
    }

    private func reloadItems() {
        items = ((try? dm.getAllItems()) ?? []).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        tableView.reloadData()
        }
    
    @IBAction func addPurchaseManualTapped(_ sender: UIButton) {
        openManualPurchaseEntry()
    }
    
    @IBAction func addStockButtonTapped(_ sender: Any) {
        presentPurchaseTypeSheet(from: sender as? UIView)
    }
    @IBAction func scanPurchaseTapped() {
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
        present(nav, animated: true)
    }
}

    extension StockViewController: UITableViewDataSource, UITableViewDelegate {
        
        func numberOfSections(in tableView: UITableView) -> Int {
            return 2
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            switch section {
            case 0: return 1
            case 1: return items.count
            default: return 0
            }
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            if indexPath.section == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "TopTileTableViewCell", for: indexPath) as! TopTileTableViewCell
                cell.delegate = self
                if indexPath.row == 0 {
                    let dm = AppDataModel.shared.dataModel
                    let investment = dm.getTotalInvestment()
                    let allItemsCount = items.count
                    let purchaseToday = dm.getTodayPurchaseTotal()
                    let itemsPurchasedToday = dm.getTodayItemsPurchasedCount()
                    let lowStockAlerts = (try? dm.getLowStockAlerts()) ?? []
                    let expiryAlerts = (try? dm.getExpiryAlerts()) ?? []
                    // Compute gross margin from current inventory:
                    var grossMarginPercent: Double? = nil
                    var totalCost: Double = 0
                    var totalPotentialRevenue: Double = 0
                    if let allItems = try? dm.db.getAllItems() {
                        for item in allItems {
                            if let batches = try? dm.db.getBatches(for: item.id) {
                                for batch in batches where batch.quantityRemaining > 0 {
                                    totalCost += Double(batch.quantityRemaining) * batch.costPrice
                                    totalPotentialRevenue += Double(batch.quantityRemaining) * batch.sellingPrice
                                }
                            }
                        }
                    }
                    if totalPotentialRevenue > 0 {
                        grossMarginPercent = ((totalPotentialRevenue - totalCost) / totalPotentialRevenue) * 100
                    }
                                        
                    // Compute purchase percent change from yesterday
                    let calendar = Calendar.current
                    var purchasePercentChange: Double? = nil
                    if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())),
                    let yesterdaySummary = try? dm.db.getDailySummary(for: yesterday) {
                        purchasePercentChange = purchaseToday.percentChange(from: yesterdaySummary.totalPurchaseAmount)
                    }

                    cell.configure(
                        investmentAmount: String(format: "₹%.0f", investment),
                        itemCount: "\(allItemsCount) items",
                        purchaseAmount: String(format: "₹%.0f", purchaseToday),
                        purchaseCount: "\(itemsPurchasedToday) items",
                        lowStockCountText: "\(lowStockAlerts.count) items",
                        grossMarginPercent: grossMarginPercent,
                        purchasePercentChange: purchasePercentChange,
                        expiryText: "\(expiryAlerts.count) items"
                    )
                    return cell
                }
            }
            else {
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: "ItemTableViewCell",
                    for: indexPath
                ) as! ItemTableViewCell
                let isFirst = indexPath.row == 0
                let isLast = indexPath.row == items.count - 1
                
                cell.separatorView.backgroundColor = .separator
                cell.applySectionCornerMask(isFirst: isFirst, isLast: isLast)
                
                let item = items[indexPath.row]
                let qtyText = "\(item.currentStock) \(item.unit)"
                let priceText = String(format: "₹%.0f", item.defaultSellingPrice)
                cell.configure(
                    itemName: item.name,
                    qty: qtyText,
                    price: priceText
                )
                cell.itemNameLabel.textColor = item.isLowStock ? .systemRed : .label
                return cell
            }
            return UITableViewCell()
        }
        
        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            if section == 1 { return 30 }
            return 0
        }
        
        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            let view = UIView()
            
            if section == 1 {
                let label = UILabel()
                label.text = "Items"
                label.font = .systemFont(ofSize: 20, weight: .bold)
                label.textColor = .label
                label.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                    label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
                ])
            }
            return view
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            guard indexPath.section == 1 else { return }
            tableView.deselectRow(at: indexPath, animated: true)
            let selectedItem = items[indexPath.row]
            performSegue(withIdentifier: "item_profile", sender: selectedItem)

        }
        
        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard indexPath.section == 1 else { return nil }

            let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                guard let self = self else { completion(false); return }
                let item = self.items[indexPath.row]

                do {
                    try self.dm.deleteItem(id: item.id)
                    self.items.remove(at: indexPath.row)
                    if self.items.isEmpty {
                        tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
                    } else {
                        tableView.deleteRows(at: [indexPath], with: .automatic)
                        tableView.reloadSections(IndexSet(integer: 1), with: .none)
                    }
                    completion(true)
                } catch {
                    completion(false)
                }
            }
            deleteAction.backgroundColor = .systemRed
            deleteAction.image = UIImage(systemName: "trash")

            let config = UISwipeActionsConfiguration(actions: [deleteAction])
            config.performsFirstActionWithFullSwipe = true
            return config
        }
        
        override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
            if segue.identifier == "item_profile",
            let itemProfileVC = segue.destination as? ItemProfileTableViewController,
            let selectedItem = sender as? Item {
                itemProfileVC.itemID = selectedItem.id
            }
        }
}

extension StockViewController: TopTileTableViewCell.TopTileTableViewCellDelegate {
    func topTileCellDidTapExpiring(_ cell: TopTileTableViewCell) {
        performSegue(withIdentifier: "expiry_segue", sender: cell)
    }
    
    func topTileCellDidTapInvestment(_ cell: TopTileTableViewCell) {
        performSegue(withIdentifier: "report_segue", sender: cell)
    }
    
    func topTileCellDidTapPurchase(_ cell: TopTileTableViewCell) {
        performSegue(withIdentifier: "purchase_segue", sender: cell)
    }

    func topTileCellDidTapLowStock(_ cell: TopTileTableViewCell) {
        performSegue(withIdentifier: "low_stock_from_stock", sender: cell)
    }
    
}
