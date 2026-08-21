import UIKit
import Vision
import AVFoundation

class ItemProfileTableViewController: UITableViewController {
    
    struct StockHistoryEntry {
        let date: Date
        let stockIn: Double
        let soldOut: Double
        let balance: Double
    }
    
    let dm = AppDataModel.shared.dataModel
    
    var item: Item?
    var originalQuantity: Double?
    var originalCostPrice: Double?
    var itemID: UUID!
    var purchaseDates: [String] = []
    let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yy" // e.g. 17/03/26
        return df
    }()
    var stockHistory: [StockHistoryEntry] = []
    
    enum RowType {
        case itemType, name, quantity, unit, alternateUnitName, alternateUnitFactor, costPrice, sellingPrice, stockValue, barcode, hsn, gst, lowStock
    }
    
    var visibleRows: [RowType] {
        let isService = item?.isService ?? false
        var rows: [RowType] = [.itemType, .name]

        if !isService {
            rows.append(contentsOf: [.quantity, .lowStock, .unit, .alternateUnitName, .alternateUnitFactor])
        } else {
            rows.append(.unit)
        }

        rows.append(contentsOf: [.costPrice, .sellingPrice])

        if !isService {
            rows.append(contentsOf: [.stockValue, .barcode])
        }
        
        let isGST = (try? dm.db.getSettings().isGSTRegistered) ?? false
        if isGST {
            rows.append(contentsOf: [.hsn, .gst])
        }
        return rows
    }

    @IBAction func saveButtonTapped(_ sender: UIBarButtonItem) {
        guard var updatedItem = item else { return }

        // Read barcode using dynamic row index
        if let barcodeIdx = visibleRows.firstIndex(of: .barcode),
           let barcodeCell = tableView.cellForRow(at: IndexPath(row: barcodeIdx, section: 0)) as? LabelTextFieldTableViewCell {
            let barcodeText = barcodeCell.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedItem.barcode = (barcodeText?.isEmpty == true) ? nil : barcodeText
        }
        
        let isGST = (try? dm.db.getSettings().isGSTRegistered) ?? false
        if isGST {
            if let hsnIdx = visibleRows.firstIndex(of: .hsn),
               let hsnCell = tableView.cellForRow(at: IndexPath(row: hsnIdx, section: 0)) as? LabelTextFieldTableViewCell {
                let text = hsnCell.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                updatedItem.hsnCode = (text?.isEmpty == true) ? nil : text
            }
            if let gstIdx = visibleRows.firstIndex(of: .gst),
               let rateCell = tableView.cellForRow(at: IndexPath(row: gstIdx, section: 0)) as? LabelTextFieldTableViewCell {
                if let text = rateCell.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines), let rate = Double(text) {
                    updatedItem.gstRate = rate
                } else {
                    updatedItem.gstRate = nil
                }
            }
        }

        do {
            try dm.db.updateItem(updatedItem)
            
            // Retroactive Sweeps & Adjustment Batches
            let newQty = updatedItem.currentStock
            let newCP = updatedItem.defaultCostPrice
            
            if let oldQty = originalQuantity, newQty > oldQty {
                // Create an Adjustment Batch for the added stock
                let diff = newQty - oldQty
                let batchID = UUID()
                let txID = UUID()
                let now = Date()
                
                let batch = ItemBatch(
                    id: batchID,
                    itemID: updatedItem.id,
                    purchaseTransactionID: txID,
                    quantityPurchased: diff,
                    quantityRemaining: diff,
                    costPrice: newCP,
                    sellingPrice: updatedItem.defaultSellingPrice,
                    expiryDate: nil,
                    receivedDate: now
                )
                try dm.db.insertBatch(batch)
                
                // Ensure a "System Adjustment" purchase transaction is recorded
                let tx = Transaction(
                    id: txID,
                    type: .purchase,
                    date: now,
                    invoiceNumber: "ADJ-\(Int(now.timeIntervalSince1970))",
                    customerName: nil,
                    customerPhone: nil,
                    supplierName: "System Adjustment",
                    totalAmount: newCP * Double(diff),
                    notes: "Profile edit quantity adjustment",
                    buyerGSTIN: nil,
                    placeOfSupply: nil,
                    placeOfSupplyCode: nil,
                    isInterState: nil,
                    totalTaxableValue: nil,
                    totalCGST: nil,
                    totalSGST: nil,
                    totalIGST: nil,
                    totalCess: nil,
                    isReverseCharge: false
                )
                let txItem = TransactionItem(
                    id: UUID(),
                    transactionID: txID,
                    itemID: updatedItem.id,
                    itemName: updatedItem.name,
                    unit: updatedItem.unit,
                    quantity: diff,
                    sellingPricePerUnit: updatedItem.defaultSellingPrice,
                    costPricePerUnit: newCP,
                    createdDate: now
                )
                try dm.db.insertTransaction(tx)
                try dm.db.insertTransactionItems([txItem])
            }
            
            if let oldCP = originalCostPrice, newCP != oldCP {
                // Retroactively update past transactions with the new CP
                try dm.db.retroactivelyUpdateCostPrice(for: updatedItem.id, newCP: newCP)
            }
            
            item = updatedItem
            navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    
    override func viewDidLoad() {
        guard let itemID = itemID else {
            return
        }
            
        do {
            item = try dm.db.getItem(id: itemID)
            
            // Reconcile currentStock from batch data (source of truth)
            let batches = try dm.db.getBatches(for: itemID)
            let trueStock = batches.reduce(0) { $0 + $1.quantityRemaining }
            if item?.currentStock != trueStock {
                print("[ItemProfile] Stock reconciliation: currentStock=\(item?.currentStock ?? -1) → trueStock=\(trueStock)")
                item?.currentStock = trueStock
                if var fixedItem = item {
                    fixedItem.currentStock = trueStock
                    try dm.db.updateItem(fixedItem)
                    item = fixedItem
                }
            }
            
            originalQuantity = item?.currentStock
            originalCostPrice = item?.defaultCostPrice
        } catch {
        }
        purchaseDates = getUniquePurchaseDateStrings(for: itemID)
        tableView.register(UINib(nibName: "StockHistoryTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "StockHistoryTableViewCell")
        tableView.register(UINib(nibName: "LabelTextFieldTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "LabelTextFieldTableViewCell")
        tableView.register(UINib(nibName: "LabelDatePickerTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "LabelDatePickerTableViewCell")
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 50
        loadStockHistory()
        tableView.reloadData()
    }
    
    func getUniquePurchaseDateStrings(for itemID: UUID) -> [String] {
        do {
            let batches = try dm.db.getBatches(for: itemID)
            
            let uniqueDays = Set(
                batches.map { Calendar.current.startOfDay(for: $0.receivedDate) }
            )
            
            let sortedDays = uniqueDays.sorted()
            
            return sortedDays.map { dateFormatter.string(from: $0) }
            
        } catch {
            return []
        }
    }
    
    func getNearestExpiryDate(for itemID: UUID) -> Date? {
        do {
            let batches = try dm.db.getBatches(for: itemID)
                .filter { $0.quantityRemaining > 0 && $0.expiryDate != nil }
            
            return batches
                .compactMap { $0.expiryDate }
                .sorted()
                .first
            
        } catch {
            return nil
        }
    }
    
    func getTotalProfit(for itemID: UUID) -> Double {
        do {
            let transactions = try dm.db.getTransactions()
            let itemDefaultCP = item?.defaultCostPrice ?? 0
            var totalProfit: Double = 0
            
            for tx in transactions where tx.type == .sale {
                let items = try dm.db.getTransactionItems(for: tx.id)
                
                for txItem in items where txItem.itemID == itemID {
                    let sell = txItem.sellingPricePerUnit ?? 0
                    let cost = txItem.costPricePerUnit ?? itemDefaultCP
                    totalProfit += Money.round2(
                        Money.line(quantity: txItem.quantity, rate: sell)
                            - Money.line(quantity: txItem.quantity, rate: cost)
                    )
                }
            }
            
            return totalProfit
            
        } catch {
            return 0
        }
    }
    
    func getTotalQuantitySold(for itemID: UUID) -> Double {
        do {
            let transactions = try dm.db.getTransactions()
            var totalQty = 0.0
            
            for tx in transactions where tx.type == .sale {
                let items = try dm.db.getTransactionItems(for: tx.id)
                
                for item in items where item.itemID == itemID {
                    totalQty += item.quantity
                }
            }
            
            return totalQty
            
        } catch {
            return 0
        }
    }
    
    func loadStockHistory() {
        guard let itemID = itemID else { return }
        
        do {
            let batches = try dm.db.getBatches(for: itemID)
            
            let transactions = try dm.db.getTransactions()
            
            var historyDict: [Date: (stockIn: Double, soldOut: Double)] = [:]
            
            // Process batches
            for batch in batches {
                let day = Calendar.current.startOfDay(for: batch.receivedDate)
                historyDict[day, default: (0,0)].stockIn += batch.quantityPurchased
            }
            
            // Process sales
            for tx in transactions where tx.type == .sale {
                let items = try dm.db.getTransactionItems(for: tx.id)
                
                for soldItem in items where soldItem.itemID == itemID {
                    let day = Calendar.current.startOfDay(for: tx.date)
                    historyDict[day, default: (0,0)].soldOut += soldItem.quantity
                }
            }
            
            var runningBalance = 0.0
            let sortedDates = historyDict.keys.sorted()
            
            let chronological = sortedDates.map { date -> StockHistoryEntry in
                let stockIn = historyDict[date]?.stockIn ?? 0
                let soldOut = historyDict[date]?.soldOut ?? 0
                runningBalance += stockIn - soldOut
                return StockHistoryEntry(date: date, stockIn: stockIn, soldOut: soldOut, balance: runningBalance)
            }
            stockHistory = Array(chronological.reversed())
            
        } catch {
            stockHistory = []
        }
    }
    
    @objc func dateChanged(_ sender: UIDatePicker) {
        _ = sender.date
        
        tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
    }

    @objc private func lowStockBellTapped(_ sender: UIButton) {
        guard let row = visibleRows.firstIndex(of: .lowStock),
              let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? LabelTextFieldTableViewCell else { return }
        cell.textField.becomeFirstResponder()
    }

    @objc private func profileItemTypeChanged(_ sender: UISegmentedControl) {
        item?.itemType = sender.selectedSegmentIndex == 1 ? .services : .goods
        if item?.itemType == .services {
            item?.lowStockThreshold = 0
            item?.barcode = nil
        }
        tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return visibleRows.count
        case 1:
            return 2
        case 2:
            return stockHistory.count + 1
        default:
            return 0
        }
    }
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        
        let headerView = UIView()
        headerView.backgroundColor = .systemGray6
        
        // Title Label
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        
        switch section {
        case 0:
            return nil
            
        case 1:
            let container = UIView()
            
            let label = UILabel()
            label.text = "Profit by Item"
            label.font = .systemFont(ofSize: 20, weight: .semibold)
            
            
            let stack = UIStackView(arrangedSubviews: [label])
            stack.axis = .horizontal
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            
            container.addSubview(stack)
            
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
                stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
            ])
            
            return container
            
        case 2:
            label.text = "Stock History"
            label.font = .systemFont(ofSize: 20, weight: .semibold)
            
        default:
            return nil
        }
        
        headerView.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -12)
        ])
        
        return headerView
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
            case 0:
                let rowType = visibleRows[indexPath.row]
                switch rowType {
                    case .itemType:
                        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                        cell.selectionStyle = .none

                        let titleLabel = UILabel()
                        titleLabel.text = "Type"
                        titleLabel.font = .systemFont(ofSize: 17)
                        titleLabel.translatesAutoresizingMaskIntoConstraints = false
                        cell.contentView.addSubview(titleLabel)

                        let seg = UISegmentedControl(items: ["Goods", "Service"])
                        seg.selectedSegmentIndex = (item?.isService == true) ? 1 : 0
                        seg.translatesAutoresizingMaskIntoConstraints = false
                        seg.addTarget(self, action: #selector(profileItemTypeChanged(_:)), for: .valueChanged)
                        cell.contentView.addSubview(seg)

                        NSLayoutConstraint.activate([
                            titleLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                            titleLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                            seg.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                            seg.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                            seg.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
                            seg.widthAnchor.constraint(equalToConstant: 160),
                            cell.contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
                        ])
                        return cell
                    case .name:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        cell.titleLabel.text = "Item Name"
                        cell.textField.placeholder = "Enter name"
                        cell.textField.text = item?.name
                        
                        cell.onTextChanged = { [weak self] text in
                            guard let self = self else { return }
                            self.item?.name = text
                            
                            // Autocomplete HSN and GST rate if GST is enabled
                            let isGST = (try? self.dm.db.getSettings().isGSTRegistered) ?? false
                            if isGST, !text.isEmpty {
                                if let hsnMatch = HSNDatabase.shared.searchByName(query: text) {
                                    var reloadedRows: [IndexPath] = []
                                    
                                    if self.item?.hsnCode == nil {
                                        self.item?.hsnCode = hsnMatch.code
                                        if let rowIdx = self.visibleRows.firstIndex(of: .hsn) {
                                            let ip = IndexPath(row: rowIdx, section: 0)
                                            if let hsnCell = self.tableView.cellForRow(at: ip) as? LabelTextFieldTableViewCell {
                                                hsnCell.textField.text = hsnMatch.code
                                            } else {
                                                reloadedRows.append(ip)
                                            }
                                        }
                                    }
                                    if self.item?.gstRate == nil {
                                        self.item?.gstRate = hsnMatch.gstRate
                                        if let rowIdx = self.visibleRows.firstIndex(of: .gst) {
                                            let ip = IndexPath(row: rowIdx, section: 0)
                                            if let gstCell = self.tableView.cellForRow(at: ip) as? LabelTextFieldTableViewCell {
                                                if let rate = hsnMatch.gstRate {
                                                    gstCell.textField.text = String(format: "%.0f", rate)
                                                }
                                            } else {
                                                reloadedRows.append(ip)
                                            }
                                        }
                                    }
                                    
                                    if !reloadedRows.isEmpty {
                                        self.tableView.reloadRows(at: reloadedRows, with: .none)
                                    }
                                }
                            }
                        }
                        return cell
                    case .quantity:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        cell.titleLabel.text = "Balance Stock"
                        cell.textField.placeholder = "Enter Quantity"
                        cell.textField.text = item?.currentStock.description
                        cell.textField.keyboardType = .numberPad
                        cell.textField.rightView = nil
                        cell.textField.rightViewMode = .never
                        cell.onTextChanged = { [weak self] text in
                            self?.item?.currentStock = Double(text) ?? 0
                        }
                        return cell
                    case .lowStock:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        cell.titleLabel.text = "Low Stock Alert"
                        cell.textField.placeholder = "Alert below"
                        cell.textField.keyboardType = .numberPad
                        let threshold = item?.lowStockThreshold ?? 0
                        cell.textField.text = threshold > 0 ? threshold.cleanString : ""
                        let bell = UIButton(type: .system)
                        let on = threshold > 0
                        bell.setImage(UIImage(systemName: on ? "bell.fill" : "bell"), for: .normal)
                        bell.tintColor = UIColor(named: "Lime Moss") ?? .systemGreen
                        bell.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
                        bell.addTarget(self, action: #selector(lowStockBellTapped(_:)), for: .touchUpInside)
                        cell.textField.rightView = bell
                        cell.textField.rightViewMode = .always
                        cell.onTextChanged = { [weak self] text in
                            self?.item?.lowStockThreshold = Double(text) ?? 0
                            let active = (self?.item?.lowStockThreshold ?? 0) > 0
                            bell.setImage(UIImage(systemName: active ? "bell.fill" : "bell"), for: .normal)
                        }
                        return cell
                    case .unit:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        cell.titleLabel.text = "Unit"
                        cell.textField.placeholder = "Enter unit"
                        cell.textField.text = item?.unit
                        cell.onTextChanged = { [weak self] text in
                            self?.item?.unit = text
                        }
                        return cell
                    case .alternateUnitName:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        cell.titleLabel.text = "Alternate Unit"
                        cell.textField.placeholder = "e.g. Bag, Box"
                        cell.textField.text = item?.alternateUnitName
                        cell.onTextChanged = { [weak self] text in
                            self?.item?.alternateUnitName = text.isEmpty ? nil : text
                        }
                        return cell
                    case .alternateUnitFactor:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        cell.titleLabel.text = "Items per Alt Unit"
                        cell.textField.placeholder = "e.g. 50"
                        if let factor = item?.alternateUnitFactor {
                            cell.textField.text = factor.cleanString
                        } else {
                            cell.textField.text = ""
                        }
                        cell.textField.keyboardType = .decimalPad
                        cell.onTextChanged = { [weak self] text in
                            if text.isEmpty {
                                self?.item?.alternateUnitFactor = nil
                            } else if let val = Double(text) {
                                self?.item?.alternateUnitFactor = val
                            }
                        }
                        return cell
                    case .costPrice:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        cell.titleLabel.text = "Cost Price"
                        cell.textField.placeholder = "Enter Price"
                        cell.textField.text = item?.defaultCostPrice.description
                        cell.textField.keyboardType = .decimalPad
                        cell.onTextChanged = { [weak self] text in
                            self?.item?.defaultCostPrice = Double(text) ?? 0.0
                        }
                        return cell
                    case .sellingPrice:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        cell.titleLabel.text = "Selling Price"
                        cell.textField.placeholder = "Enter Price"
                        cell.textField.text = item?.defaultSellingPrice.description
                        cell.textField.keyboardType = .decimalPad
                        cell.onTextChanged = { [weak self] text in
                            self?.item?.defaultSellingPrice = Double(text) ?? 0.0
                        }
                        return cell
                    case .stockValue:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        cell.titleLabel.text = "Stock Value"
                        cell.textField.placeholder = "Enter Value"
                        if let item = item {
                            let stockValue = Double(item.currentStock) * item.defaultCostPrice
                            cell.textField.text = String(format: "%.2f", stockValue)
                        } else {
                            cell.textField.text = "-"
                        }
                        cell.textField.isEnabled = false
                        return cell
                    case .barcode:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        cell.titleLabel.text = "Barcode"
                        cell.textField.placeholder = "Scan or enter barcode"
                        cell.textField.text = item?.barcode
                        cell.textField.keyboardType = .default
                        let scanBtn = UIButton(type: .system)
                        scanBtn.setImage(UIImage(systemName: "barcode.viewfinder"), for: .normal)
                        scanBtn.tintColor = UIColor(named: "Lime Moss") ?? .systemGreen
                        scanBtn.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
                        scanBtn.addTarget(self, action: #selector(scanBarcodeTapped), for: .touchUpInside)
                        cell.textField.rightView = scanBtn
                        cell.textField.rightViewMode = .always
                        return cell
                    case .hsn:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        let isService = item?.isService ?? false
                        cell.titleLabel.text = isService ? "SAC Code" : "HSN Code"
                        cell.textField.placeholder = isService ? "e.g. 9983" : "e.g. 1902"
                        cell.textField.text = item?.hsnCode
                        cell.textField.keyboardType = .numberPad
                        
                        cell.onTextChanged = { [weak self] text in
                            guard let self = self else { return }
                            self.item?.hsnCode = text.isEmpty ? nil : text
                            
                            if !text.isEmpty, let rate = HSNDatabase.shared.lookupGSTRate(hsnCode: text) {
                                self.item?.gstRate = rate
                                
                                if let rowIdx = self.visibleRows.firstIndex(of: .gst) {
                                    let gstRateIndexPath = IndexPath(row: rowIdx, section: 0)
                                    if let gstCell = self.tableView.cellForRow(at: gstRateIndexPath) as? LabelTextFieldTableViewCell {
                                        gstCell.textField.text = String(format: "%.0f", rate)
                                    } else {
                                        self.tableView.reloadRows(at: [gstRateIndexPath], with: .none)
                                    }
                                }
                            }
                        }
                        return cell
                    case .gst:
                        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                        cell.titleLabel.text = "GST Rate (%)"
                        cell.textField.placeholder = "0, 3, 5, 12, 18, 28"
                        if let rate = item?.gstRate {
                            cell.textField.text = String(format: "%.0f", rate)
                        } else {
                            cell.textField.text = ""
                        }
                        cell.textField.keyboardType = .decimalPad
                        cell.onTextChanged = { [weak self] text in
                            self?.item?.gstRate = Double(text)
                        }
                        return cell
                }
            case 1:
                switch indexPath.row {
                    //Values Change based on header's date picker value
                    case 0:
                        let cell: UITableViewCell
                        if let dequeued = tableView.dequeueReusableCell(withIdentifier: "rightDetail") {
                            cell = dequeued
                        } else {
                            cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
                        }

                        cell.textLabel?.text = "Profit Amount"
                        cell.textLabel?.font = .systemFont(ofSize: 17)
                        
                        let profit = getTotalProfit(for: itemID)
                        cell.detailTextLabel?.text = String(format: "₹ %.2f", profit)
                        cell.detailTextLabel?.font = .systemFont(ofSize: 17)
                        
                        cell.selectionStyle = .none
                        return cell
                    case 1:
                        let cell: UITableViewCell
                        if let dequeued = tableView.dequeueReusableCell(withIdentifier: "rightDetail") {
                            cell = dequeued
                        } else {
                            cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
                        }
                        
                        cell.textLabel?.text = "Stock Sold"
                        cell.textLabel?.font = .systemFont(ofSize: 17)
                        
                        let qty = getTotalQuantitySold(for: itemID)
                        cell.detailTextLabel?.text = "\(qty)"
                        cell.detailTextLabel?.font = .systemFont(ofSize: 17)
                        
                        cell.selectionStyle = .none
                        return cell
                    default:
                        return UITableViewCell()
                }
            case 2:
                    let cell = tableView.dequeueReusableCell(withIdentifier: "StockHistoryTableViewCell", for: indexPath) as! StockHistoryTableViewCell
                    if indexPath.row == 0 {
                        // Header
                        cell.firstLabel.text = "Date"
                        cell.secondLabel.text = "Stock In"
                        cell.thirdLabel.text = "Sold Out"
                        cell.fourthLabel.text = "Balance"
                    } else {
                        let entry = stockHistory[indexPath.row - 1]
                        cell.firstLabel.text = dateFormatter.string(from: entry.date)
                        cell.firstLabel.textColor = .gray
                        if entry.stockIn == 0 {
                            cell.secondLabel.text = "-"
                        } else {
                            cell.secondLabel.text = "\(entry.stockIn)"
                        }
                        
                        cell.secondLabel.textColor = .systemBlue
                        if entry.soldOut == 0 {
                            cell.thirdLabel.text = "-"
                        } else {
                            cell.thirdLabel.text = "\(entry.soldOut)"
                        }
                        cell.thirdLabel.textColor = UIColor(named: "Lime Moss")!
                        cell.fourthLabel.text = "\(entry.balance)"
                        cell.fourthLabel.textColor = .gray
                    }
                    return cell
        default:
            return UITableViewCell()
        }
    
    }

    // MARK: - Barcode Scan

    @objc func scanBarcodeTapped() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            let alert = UIAlertController(title: "Error", message: "Camera unavailable", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        // Quick single-barcode scan VC
        let scanVC = QuickBarcodeScanViewController()
        scanVC.onBarcodeScanned = { [weak self] barcode in
            guard let self = self else { return }
            // Populate the barcode text field
            if let row = self.visibleRows.firstIndex(of: .barcode),
               let cell = self.tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? LabelTextFieldTableViewCell {
                cell.textField.text = barcode
            }
            self.item?.barcode = barcode
        }
        let nav = UINavigationController(rootViewController: scanVC)
        present(nav, animated: true)
    }
}

// MARK: - Quick Barcode Scanner (for Item Profile)

class QuickBarcodeScanViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onBarcodeScanned: ((String) -> Void)?
     var captureSession: AVCaptureSession?
     var previewLayer: AVCaptureVideoPreviewLayer?
     var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Scan Barcode"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        let label = UILabel()
        label.text = "Point at the barcode"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])

        setupCamera()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

     func setupCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let session = AVCaptureSession()
            session.sessionPreset = .high
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let videoOut = AVCaptureVideoDataOutput()
            videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOut.setSampleBufferDelegate(self, queue: DispatchQueue(label: "quick.barcode"))
            videoOut.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(videoOut) { session.addOutput(videoOut) }

            self.captureSession = session
            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.view.bounds
                self.view.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
            }
            session.startRunning()
        }
    }

    @objc func cancelTapped() { dismiss(animated: true) }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !hasScanned, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }

        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])

        if let payload = (request.results as? [VNBarcodeObservation])?.first?.payloadStringValue, !payload.isEmpty {
            hasScanned = true
            DispatchQueue.main.async {
                self.onBarcodeScanned?(payload)
                self.dismiss(animated: true)
            }
        }
    }
}

