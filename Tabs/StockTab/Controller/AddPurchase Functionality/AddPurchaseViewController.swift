import UIKit
import AVFoundation


class AddPurchaseViewController: UITableViewController, PurchaseItemInformationDelegate {
    
    func itemInformation(
        _ controller: PurchaseItemInformationTableViewController,
        entry: PurchaseEntry
    ) {
        entries.append(entry)

        tableView.reloadSections(
            IndexSet([
                Section.items.rawValue,
                Section.summary.rawValue
            ]),
            with: .automatic
        )
    }
    
    enum Section: Int, CaseIterable {
        case supplier
        case items
        case paymentType
        case summary

        var title: String {
            switch self {
            case .supplier: return "Supplier"
            case .items: return "Items"
            case .paymentType: return "Credit Purchase"
            case .summary: return "Summary"
            }
        }
    }
    
    private var entries: [PurchaseEntry] = []
    private var supplierName: String?
    private var isPayLaterEnabled = false
    private var inventoryCache: [Item] = []
    private var currentSuggestions: [Item] = []
    private let suggestionsTableView = UITableView(frame: .zero, style: .plain)
    private weak var activeNameField: UITextField?

    /// Index of the expanded item (chevron tapped to show detail fields). nil = all collapsed.
    private var expandedItemIndex: Int? = nil

    /// Holds voice/scan result passed before viewDidLoad; consumed in viewDidLoad.
    var pendingResult: ParsedResult?
    var pendingPurchaseResult: ParsedPurchaseResult?
    var entryMode: EntryMode = .manual
    
    private var isEditingEnabled = false {
        didSet {
            tableView.reloadData()
        }
    }

    private var supplierTextField = UITextField()


    private var subTotal: Double {
        entries.reduce(0) { $0 + ($1.quantity * $1.costPrice) }
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Add Purchase"

        tableView.backgroundColor = .systemGray6
        tableView.rowHeight = UITableView.automaticDimension

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(UINib(nibName: "LabelTextFieldTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "LabelTextFieldTableViewCell")
        tableView.register(UINib(nibName: "AddNewItemTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "AddNewItemTableViewCell")
        tableView.register(UINib(nibName: "EditSalesItemTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "EditSalesItemTableViewCell")
        tableView.register(UINib(nibName: "SalesItemTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "SalesItemTableViewCell")
        tableView.register(UINib(nibName: "LabelDatePickerTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "LabelDatePickerTableViewCell")
        tableView.register(UINib(nibName: "StockTwoLabelsTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "StockTwoLabelsTableViewCell")
        inventoryCache = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        setupSuggestionsTableView()
        
        // Apply any data passed before viewDidLoad (e.g. from voice or scan callback)
        if let result = pendingResult {
            pendingResult = nil
            appendEntries(from: result)
        }
        if let result = pendingPurchaseResult {
            pendingPurchaseResult = nil
            appendEntries(fromPurchaseResult: result)
        }
    }

    private func setupSuggestionsTableView() {
        suggestionsTableView.isHidden = true
        suggestionsTableView.layer.cornerRadius = 12
        suggestionsTableView.layer.borderWidth = 0.5
        suggestionsTableView.layer.borderColor = UIColor.systemGray3.cgColor
        suggestionsTableView.backgroundColor = .systemBackground
        suggestionsTableView.rowHeight = 44
        suggestionsTableView.dataSource = self
        suggestionsTableView.delegate = self
        suggestionsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "PurchaseSuggestionCell")
        
        // Remove all extra spacing that causes the blank area above rows
        suggestionsTableView.sectionHeaderTopPadding = 0
        suggestionsTableView.sectionHeaderHeight = 0
        suggestionsTableView.sectionFooterHeight = 0
        suggestionsTableView.contentInset = .zero
        suggestionsTableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        
        // Shadow for floating appearance
        suggestionsTableView.layer.shadowColor = UIColor.black.cgColor
        suggestionsTableView.layer.shadowOpacity = 0.15
        suggestionsTableView.layer.shadowOffset = CGSize(width: 0, height: 4)
        suggestionsTableView.layer.shadowRadius = 12
        suggestionsTableView.layer.masksToBounds = false
    }

    private func updateSuggestions(for query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            suggestionsTableView.isHidden = true
            suggestionsTableView.removeFromSuperview()
            return
        }

        if inventoryCache.isEmpty {
            inventoryCache = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        }
        currentSuggestions = InventoryMatcher.shared.getSuggestions(for: normalized, against: inventoryCache)
        guard !currentSuggestions.isEmpty, let field = activeNameField else {
            suggestionsTableView.isHidden = true
            suggestionsTableView.removeFromSuperview()
            return
        }

        // Add to the application window so it floats above the table view
        guard let window = view.window else { return }
        
        let fieldRect = field.convert(field.bounds, to: window)
        
        let horizontalPadding: CGFloat = 16
        let dropdownWidth = window.bounds.width - (horizontalPadding * 2)
        let desiredHeight = min(CGFloat(currentSuggestions.count) * suggestionsTableView.rowHeight, 220)
        
        let spaceBelow = window.bounds.height - fieldRect.maxY - 20
        let yPosition: CGFloat
        if spaceBelow >= desiredHeight {
            yPosition = fieldRect.maxY + 4
        } else {
            yPosition = fieldRect.minY - desiredHeight - 4
        }
        
        suggestionsTableView.frame = CGRect(
            x: horizontalPadding,
            y: yPosition,
            width: dropdownWidth,
            height: desiredHeight
        )
        
        if suggestionsTableView.superview != window {
            suggestionsTableView.removeFromSuperview()
            window.addSubview(suggestionsTableView)
        }
        
        suggestionsTableView.reloadData()
        suggestionsTableView.isHidden = false
        window.bringSubviewToFront(suggestionsTableView)
    }

    private func syncInventoryMatchForEntry(at index: Int) {
        guard index >= 0 && index < entries.count else { return }
        let typedName = (entries[index].selectedItemName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typedName.isEmpty else { return }
        guard let matched = inventoryCache.first(where: { $0.name.caseInsensitiveCompare(typedName) == .orderedSame }) else { return }

        entries[index].selectedItemID = matched.id
        entries[index].selectedItemName = matched.name
        entries[index].selectedUnitName = matched.unit
        if entries[index].costPrice <= 0 {
            entries[index].costPrice = matched.defaultCostPrice
        }
        if entries[index].sellingPrice <= 0 {
            entries[index].sellingPrice = matched.defaultSellingPrice
        }
        // Auto-fill GST fields from existing item
        if entries[index].hsnCode == nil, let hsn = matched.hsnCode {
            entries[index].hsnCode = hsn
        }
        if entries[index].gstRate == nil, let rate = matched.gstRate {
            entries[index].gstRate = rate
        }
        
        // Auto-fill GST fields from HSN database if still nil
        if entries[index].hsnCode == nil || entries[index].gstRate == nil {
            if let hsnMatch = HSNDatabase.shared.searchByName(query: typedName) {
                if entries[index].hsnCode == nil {
                    entries[index].hsnCode = hsnMatch.code
                }
                if entries[index].gstRate == nil {
                    entries[index].gstRate = hsnMatch.gstRate
                }
            }
        }
    }
    
    // MARK: - Add New Item (re-open voice/camera if entry started that way)
    
    private func addNewItemByEntryMode() {
        switch entryMode {
        case .voice:
            if let sb = storyboard,
               let vc = sb.instantiateViewController(withIdentifier: "VoicePurchaseEntryViewController") as? VoicePurchaseEntryViewController {
                vc.onItemsParsed = { [weak self] result in
                    guard let self = self else { return }
                    self.appendEntries(from: result)
                    self.navigationController?.popToViewController(self, animated: true)
                }
                navigationController?.pushViewController(vc, animated: true)
            }
        case .camera:
            let scanVC = ScanCameraViewController(mode: .purchase)
            scanVC.onPurchaseResult = { [weak self] result in
                guard let self = self else { return }
                self.appendEntries(fromPurchaseResult: result)
            }
            let nav = UINavigationController(rootViewController: scanVC)
            nav.modalPresentationStyle = .fullScreen
            present(nav, animated: true)
        case .manual:
            self.entries.append(PurchaseEntry())
            self.expandedItemIndex = self.entries.count - 1
            self.tableView.reloadData()
        }
    }

    // MARK: - Append Entries from Voice/Scan
    
    func appendEntries(from result: ParsedResult) {
        if inventoryCache.isEmpty {
            inventoryCache = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        }
        let inventoryItems = self.inventoryCache
        
        let matchedProducts = InventoryMatcher.shared.matchProducts(
            products: result.products,
            items: inventoryItems
        )
        
        for product in matchedProducts {
            var inputQty = Double(product.quantity) ?? 1.0
            var finalUnit = product.unit ?? "pcs"
            
            // Auto-scale fractional units to avoid decimal loss (e.g. 0.5 kg -> 500 g)
            if floor(inputQty) != inputQty {
                let nUnit = UnitConversionService.shared.normalizeUnit(finalUnit)
                if nUnit == "kg" {
                    inputQty *= 1000.0
                    finalUnit = "g"
                } else if nUnit == "l" {
                    inputQty *= 1000.0
                    finalUnit = "ml"
                }
            }
            
            var finalCostPrice: Double = Double(product.costPrice ?? "") ?? 0
            var finalSellingPrice: Double = Double(product.price ?? "") ?? 0
            var finalQty = inputQty == 0 ? 1.0 : inputQty
            
            let matchedItem = product.itemID.flatMap { id in inventoryItems.first { $0.id == id } }
            
            // Apply unit conversion if matched
            if let inv = matchedItem {
                print("[PurchaseLog] Item=\(inv.name), invUnit=\(inv.unit), reqUnit=\(finalUnit), reqQty=\(inputQty), invCost=\(inv.defaultCostPrice)")
                if let conversion = UnitConversionService.shared.calculateProrated(
                    requestedQty: inputQty,
                    requestedUnit: finalUnit,
                    inventoryPrice: inv.defaultCostPrice,
                    inventoryUnit: inv.unit
                ) {
                    finalQty = Double(conversion.quantity)
                    finalUnit = conversion.unit
                    if finalCostPrice <= 0 {
                        finalCostPrice = conversion.proratedPrice
                    }
                    print("[PurchaseLog] ✓ Converted: qty=\(finalQty), unit=\(finalUnit), cost=\(finalCostPrice)")
                } else {
                    finalUnit = inv.unit
                    if finalCostPrice <= 0 { finalCostPrice = inv.defaultCostPrice }
                    print("[PurchaseLog] ✗ No conversion needed/possible, using cost=\(finalCostPrice), unit=\(finalUnit)")
                }
                if finalSellingPrice <= 0 { finalSellingPrice = inv.defaultSellingPrice }
            } else {
                print("[PurchaseLog] ✗ No match found for '\(product.name)'")
            }
            
            // Normalize unit
            finalUnit = UnitConversionService.displayName(for: finalUnit)
            
            var entry = PurchaseEntry()
            entry.selectedItemName = product.name
            entry.selectedItemID = matchedItem?.id
            entry.selectedUnitName = finalUnit
            entry.quantity = finalQty
            entry.costPrice = finalCostPrice
            entry.sellingPrice = finalSellingPrice
            
            entries.append(entry)
        }
        
        // NER stores supplier in customerName for purchase context
        if let supplier = result.customerName {
            supplierName = supplier
        }
        
        tableView.reloadData()
    }
    
    func appendEntries(fromPurchaseResult result: ParsedPurchaseResult) {
        if inventoryCache.isEmpty {
            inventoryCache = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        }
        let inventoryItems = self.inventoryCache
        
        for item in result.items {
            var inputQty = Double(item.quantity) ?? 1.0
            var finalUnit = item.unit ?? "pcs"
            
            if floor(inputQty) != inputQty {
                let nUnit = UnitConversionService.shared.normalizeUnit(finalUnit)
                if nUnit == "kg" { inputQty *= 1000.0; finalUnit = "g" }
                else if nUnit == "l" { inputQty *= 1000.0; finalUnit = "ml" }
            }
            
            var finalCostPrice: Double = Double(item.costPrice ?? "") ?? 0
            var finalSellingPrice: Double = Double(item.sellingPrice ?? "") ?? 0
            var finalQty = inputQty == 0 ? 1.0 : inputQty
            
            let matchedItem = inventoryItems.first(where: { $0.name.lowercased() == item.name.lowercased() })
            
            if let inv = matchedItem {
                if let conversion = UnitConversionService.shared.calculateProrated(
                    requestedQty: inputQty,
                    requestedUnit: finalUnit,
                    inventoryPrice: inv.defaultCostPrice,
                    inventoryUnit: inv.unit
                ) {
                    finalQty = Double(conversion.quantity)
                    finalUnit = conversion.unit
                    if finalCostPrice <= 0 { finalCostPrice = conversion.proratedPrice }
                } else {
                    finalUnit = inv.unit
                    if finalCostPrice <= 0 { finalCostPrice = inv.defaultCostPrice }
                }
                if finalSellingPrice <= 0 { finalSellingPrice = inv.defaultSellingPrice }
            }
            
            finalUnit = UnitConversionService.displayName(for: finalUnit)
            
            var entry = PurchaseEntry()
            entry.selectedItemName = item.name
            entry.selectedItemID = matchedItem?.id
            entry.selectedUnitName = finalUnit
            entry.quantity = finalQty
            entry.costPrice = finalCostPrice
            entry.sellingPrice = finalSellingPrice
            
            // Apply extracted GST fields
            entry.hsnCode = item.hsnCode ?? matchedItem?.hsnCode
            if let rateStr = item.gstRate, let rate = Double(rateStr) {
                entry.gstRate = rate
            } else if let rate = matchedItem?.gstRate {
                entry.gstRate = rate
            }
            
            entries.append(entry)
        }
        
        if let supplier = result.supplierName {
            supplierName = supplier
        }
        
        // Note: result.invoiceNumber and result.totalTaxableValue can be handled later if UI fields exist for invoice number
        
        tableView.reloadData()
    }

    @IBAction func saveButtonTapped(_ sender: UIBarButtonItem) {
        guard !entries.isEmpty else { return }

        // Credit validation: supplier name is required for credit purchases
        if isPayLaterEnabled {
            let name = (supplierName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                let alert = UIAlertController(
                    title: "Supplier Required",
                    message: "Supplier name is required for credit purchases.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    self.supplierTextField.becomeFirstResponder()
                })
                present(alert, animated: true)
                return
            }
        }

            let supplier = supplierName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalSupplier = (supplier?.isEmpty == true) ? nil : supplier

            let dm = AppDataModel.shared.dataModel
            let db = dm.db

            do {
                let allItems = try db.getAllItems()
                var nameToItem: [String: Item] = [:]
                for item in allItems {
                    nameToItem[item.name.lowercased()] = item
                }

                var purchaseItems: [(itemID: UUID, quantity: Int, costPrice: Double, sellingPrice: Double, expiryDate: Date?)] = []
                
                for entry in entries {
                    guard let itemNameRaw = entry.selectedItemName else { continue }
                    let itemName = itemNameRaw.trimmingCharacters(in: .whitespaces)
                    if itemName.isEmpty { continue }

                    let key = itemName.lowercased()
                    let quantity = Int(round(entry.quantity))
                    let costPrice = entry.costPrice
                    let sellingPrice = entry.sellingPrice > 0 ? entry.sellingPrice : costPrice

                    let itemID: UUID

                    if var existing = nameToItem[key] {
                        itemID = existing.id
                        // Update existing item's GST fields if they are currently nil
                        var needsUpdate = false
                        if existing.hsnCode == nil, let hsn = entry.hsnCode {
                            existing.hsnCode = hsn
                            needsUpdate = true
                        }
                        if existing.gstRate == nil, let rate = entry.gstRate {
                            existing.gstRate = rate
                            needsUpdate = true
                        }
                        if needsUpdate {
                            try db.updateItem(existing)
                            nameToItem[key] = existing
                        }
                    } else {
                        var newItem = Item(
                            id: UUID(),
                            name: itemName,
                            unit: entry.selectedUnitName ?? "pcs",
                            defaultCostPrice: costPrice,
                            defaultSellingPrice: sellingPrice,
                            defaultPriceUpdatedAt: Date(),
                            lowStockThreshold: entry.lowStockThreshold,
                            currentStock: 0,
                            createdDate: Date(),
                            lastRestockDate: nil,
                            isActive: true
                        )
                        // Persist GST fields from purchase entry
                        newItem.hsnCode = entry.hsnCode
                        newItem.gstRate = entry.gstRate

                        try db.insertItem(newItem)
                        nameToItem[key] = newItem
                        itemID = newItem.id
                    }

                    if !entry.pendingItemPhotos.isEmpty {
                        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let tabsDataDir = docsDir.appendingPathComponent("TabsData", isDirectory: true)
                        let photosDir = tabsDataDir.appendingPathComponent("ProductPhotos/\(itemID.uuidString)")
                        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
                        
                        for photo in entry.pendingItemPhotos {
                            if let jpegData = photo.jpegData(compressionQuality: 0.7) {
                                let fileName = UUID().uuidString + ".jpg"
                                let absolutePath = photosDir.appendingPathComponent(fileName)
                                try? jpegData.write(to: absolutePath)
                                
                                let relativePath = "ProductPhotos/\(itemID.uuidString)/\(fileName)"
                                let productPhoto = ProductPhoto(
                                    id: UUID(),
                                    itemID: itemID,
                                    localPath: relativePath,
                                    createdAt: Date()
                                )
                                try? db.insertProductPhoto(productPhoto)
                            }
                        }
                        ProductFingerprintManager.shared.updateEmbeddings(for: itemID) { }
                    }

                    purchaseItems.append((itemID: itemID, 
                                          quantity: quantity, 
                                          costPrice: costPrice, 
                                          sellingPrice: sellingPrice, 
                                          expiryDate: entry.expiryDate))
                }

                guard !purchaseItems.isEmpty else { return }
                
                let transaction = try dm.addMultiItemPurchase(
                    items: purchaseItems,
                    supplierName: finalSupplier
                )

                if isPayLaterEnabled, transaction.totalAmount > 0 {
                    let note = "Credit purchase \(transaction.invoiceNumber)"
                    CreditStore.shared.addCreditPurchase(
                        amount: transaction.totalAmount,
                        supplierName: finalSupplier ?? "Supplier",
                        note: note
                    )
                }

                dismiss(animated: true)
                navigationController?.popViewController(animated: true)

            } catch {
                let alert = UIAlertController(
                    title: "Error",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
    }

    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "item_details",
           let vc = segue.destination as? PurchaseItemInformationTableViewController {
            vc.delegate = self
        }
    }

    // MARK: - TableView DataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        if tableView == suggestionsTableView {
            return 1
        }
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == suggestionsTableView {
            return currentSuggestions.count
        }
        switch Section(rawValue: section)! {
        case .supplier:
            return 1

        case .items:
            if entries.isEmpty {
                return 1  // "Add Item" row
            } else {
                // Each entry = 1 summary row. If expanded, that entry also gets detail rows.
                var count = entries.count + 1  // +1 for "Add Item" row
                if let expanded = expandedItemIndex, expanded < entries.count {
                    count += detailRowCount()  // extra rows for the expanded item
                }
                return count
            }

        case .summary:
            return 2
        case .paymentType:
            return 1
        }
    }
    
    /// Number of detail rows shown when an item is expanded
    private func detailRowCount() -> Int {
        let isGST = (try? AppDataModel.shared.dataModel.db.getSettings())?.isGSTRegistered ?? false
        return isGST ? 11 : 9  // +2 for HSN code and GST rate when GST is enabled
    }
    
    /// Maps an indexPath.row in the items section to (entryIndex, isDetail, detailRow)
    private func resolveItemRow(_ row: Int) -> (entryIndex: Int, isDetailRow: Bool, detailRow: Int) {
        guard let expanded = expandedItemIndex else {
            // No expansion — simple mapping
            return (entryIndex: row, isDetailRow: false, detailRow: -1)
        }
        
        if row <= expanded {
            return (entryIndex: row, isDetailRow: false, detailRow: -1)
        }
        
        let detailCount = detailRowCount()
        let detailEnd = expanded + 1 + detailCount
        
        if row < detailEnd {
            return (entryIndex: expanded, isDetailRow: true, detailRow: row - expanded - 1)
        }
        
        // After detail rows
        return (entryIndex: row - detailCount, isDetailRow: false, detailRow: -1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == suggestionsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "PurchaseSuggestionCell", for: indexPath)
            let item = currentSuggestions[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.text = item.name
            content.textProperties.font = .systemFont(ofSize: 13, weight: .regular)
            content.textProperties.numberOfLines = 1
            cell.contentConfiguration = content
            cell.accessoryType = .none
            return cell
        }

        switch Section(rawValue: indexPath.section)! {

        case .supplier:
            let cell = tableView.dequeueReusableCell(withIdentifier: "StockTwoLabelsTableViewCell", for: indexPath) as! StockTwoLabelsTableViewCell

            cell.titleLabel.text = "Supplier Name"
            cell.titleLabel.textColor = .label
            cell.detailLabel.text = supplierName ?? "Tap to select"
            cell.detailLabel.textColor = supplierName != nil ? .label : .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell

        case .items:
            // "Add Item" row (last row, accounting for expanded detail)
            let addItemRow: Int
            if entries.isEmpty {
                addItemRow = 0
            } else if let expanded = expandedItemIndex, expanded < entries.count {
                addItemRow = entries.count + detailRowCount()
            } else {
                addItemRow = entries.count
            }
            
            if indexPath.row == addItemRow {
                let cell = tableView.dequeueReusableCell(withIdentifier: "AddNewItemTableViewCell", for: indexPath) as! AddNewItemTableViewCell
                cell.onAddTapped = { [weak self] in
                    guard let self = self else { return }
                    self.addNewItemByEntryMode()
                }
                return cell
            }

            let resolved = resolveItemRow(indexPath.row)
            
            if resolved.isDetailRow {
                // EXPANDED DETAIL ROWS — full item information form
                return buildDetailCell(for: resolved.entryIndex, detailRow: resolved.detailRow, at: indexPath)
            }

            // SUMMARY ROW for each entry
            let entry = entries[resolved.entryIndex]
            let isExpanded = expandedItemIndex == resolved.entryIndex

            let cell = tableView.dequeueReusableCell(withIdentifier: "SalesItemTableViewCell", for: indexPath) as! SalesItemTableViewCell
            cell.selectionStyle = .none

            let name = entry.selectedItemName ?? "Item"
            let qty = entry.quantity > 0 ? String(format: "%g", entry.quantity) : "Qty"
            let cost = entry.costPrice > 0 ? "₹\(entry.costPrice)" : "Cost"

            cell.titleLabel?.text = name
            cell.detailLabel?.text = "\(qty) × \(cost)"

            let total = entry.quantity * entry.costPrice
            cell.priceLabel?.text = "₹\(total)"
            
            // Chevron indicator
            cell.accessoryType = isExpanded ? .none : .disclosureIndicator

            return cell

        case .paymentType:
            let identifier = "payLaterToggleCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
            cell.selectionStyle = .none
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }

            let titleLabel = UILabel()
            titleLabel.text = "Credit Purchase"
            titleLabel.font = .preferredFont(forTextStyle: .body)

            let subtitleLabel = UILabel()
            subtitleLabel.text = "Enable if purchase is on credit."
            subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
            subtitleLabel.textColor = .secondaryLabel

            let labelStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
            labelStack.axis = .vertical
            labelStack.spacing = 2

            let toggle = UISwitch()
            toggle.isOn = isPayLaterEnabled
            toggle.addTarget(self, action: #selector(payLaterToggleChanged(_:)), for: .valueChanged)

            let stack = UIStackView(arrangedSubviews: [labelStack, UIView(), toggle])
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = 12

            cell.contentView.backgroundColor = .cell
            cell.contentView.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
                stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16)
            ])

            return cell
        case .summary:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "summary")
            cell.selectionStyle = .none
            if indexPath.row == 0 {
                cell.textLabel?.text = "Subtotal"
                cell.detailTextLabel?.text = String(format: "₹%.2f", subTotal)
                cell.textLabel?.font = .systemFont(ofSize: 17)
                cell.detailTextLabel?.font = .systemFont(ofSize: 17)
            } else {
                cell.textLabel?.text = "Total(INR)"
                cell.textLabel?.font = .boldSystemFont(ofSize: 17)
                cell.detailTextLabel?.font = .boldSystemFont(ofSize: 17)
                cell.detailTextLabel?.text = String(format: "₹%.2f", subTotal)
            }
            cell.contentView.backgroundColor = .cell
            return cell

        
        }
    }
    
    // MARK: - Build Detail Cell for Expanded Item
    
    /// Logical detail row types
    private enum DetailRowType {
        case itemName, unit, quantity, costPrice, sellingPrice
        case hsnCode, gstRate   // GST-only
        case lowStock, expiry, barcode, photoRecord
    }

    /// Build the ordered list of detail rows based on GST registration
    private func detailRowTypes() -> [DetailRowType] {
        let isGST = (try? AppDataModel.shared.dataModel.db.getSettings())?.isGSTRegistered ?? false
        var rows: [DetailRowType] = [.itemName, .unit, .quantity, .costPrice, .sellingPrice]
        if isGST {
            rows.append(contentsOf: [.hsnCode, .gstRate])
        }
        rows.append(contentsOf: [.lowStock, .expiry, .barcode, .photoRecord])
        return rows
    }

    private func buildDetailCell(for entryIndex: Int, detailRow: Int, at indexPath: IndexPath) -> UITableViewCell {
        let entry = entries[entryIndex]
        let rowTypes = detailRowTypes()
        guard detailRow < rowTypes.count else { return UITableViewCell() }
        let rowType = rowTypes[detailRow]

        switch rowType {
        case .itemName:
            // Item Name
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "summary")
            cell.textLabel?.text = "  Item"
            cell.textLabel?.textColor = .systemRed
            cell.detailTextLabel?.text = entry.selectedItemName ?? "Tap to Select"
            cell.textLabel?.font = .systemFont(ofSize: 17)
            cell.detailTextLabel?.font = .systemFont(ofSize: 17)
            cell.accessoryType = .disclosureIndicator
            cell.contentView.backgroundColor = .cell
            cell.backgroundColor = .cell
            return cell
            
        case .unit:
            // Unit
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "summary")
            cell.textLabel?.text = "  Unit"
            cell.textLabel?.textColor = .systemRed
            cell.detailTextLabel?.text = entry.selectedUnitName ?? "Tap to Select"
            cell.textLabel?.font = .systemFont(ofSize: 17)
            cell.detailTextLabel?.font = .systemFont(ofSize: 17)
            cell.accessoryType = .disclosureIndicator
            cell.contentView.backgroundColor = .cell
            cell.backgroundColor = .cell
            return cell
            
        case .quantity:
            // Quantity
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "  Quantity"
            cell.titleLabel.textColor = .systemRed
            cell.textField.placeholder = "0"
            cell.textField.keyboardType = .decimalPad
            cell.textField.text = entry.quantity > 0 ? String(format: "%g", entry.quantity) : ""
            cell.textField.isUserInteractionEnabled = true
            cell.accessoryType = .none
            cell.onTextChanged = { [weak self] text in
                self?.entries[entryIndex].quantity = Double(text) ?? 0
            }
            return cell
            
        case .costPrice:
            // Cost Price
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "  Cost Price"
            cell.titleLabel.textColor = .systemRed
            cell.textField.placeholder = "₹ 0.00"
            cell.textField.keyboardType = .decimalPad
            cell.textField.text = entry.costPrice > 0 ? String(format: "%.2f", entry.costPrice) : ""
            cell.textField.isUserInteractionEnabled = true
            cell.accessoryType = .none
            cell.onTextChanged = { [weak self] text in
                self?.entries[entryIndex].costPrice = Double(text) ?? 0
            }
            return cell
            
        case .sellingPrice:
            // Selling Price
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "  Selling Price"
            cell.textField.placeholder = "₹ 0.00"
            cell.textField.keyboardType = .decimalPad
            cell.textField.text = entry.sellingPrice > 0 ? String(format: "%.2f", entry.sellingPrice) : ""
            cell.textField.isUserInteractionEnabled = true
            cell.accessoryType = .none
            cell.onTextChanged = { [weak self] text in
                self?.entries[entryIndex].sellingPrice = Double(text) ?? 0
            }
            return cell
            
        case .hsnCode:
            // HSN / SAC Code
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "  HSN Code"
            cell.textField.placeholder = "e.g. 1006"
            cell.textField.keyboardType = .numberPad
            cell.textField.text = entry.hsnCode ?? ""
            cell.textField.isUserInteractionEnabled = true
            cell.accessoryType = .none
            cell.onTextChanged = { [weak self] text in
                guard let self = self else { return }
                self.entries[entryIndex].hsnCode = text.isEmpty ? nil : text
                
                // Autocomplete GST rate
                if !text.isEmpty, let rate = HSNDatabase.shared.lookupGSTRate(hsnCode: text) {
                    self.entries[entryIndex].gstRate = rate
                    
                    // Update UI directly to avoid keyboard dismissal
                    let gstRateIndexPath = IndexPath(row: indexPath.row + 1, section: indexPath.section)
                    if let gstCell = self.tableView.cellForRow(at: gstRateIndexPath) {
                        gstCell.detailTextLabel?.text = "\(rate)%"
                        gstCell.detailTextLabel?.textColor = .label
                    } else {
                        self.tableView.reloadRows(at: [gstRateIndexPath], with: .none)
                    }
                }
            }
            return cell

        case .gstRate:
            // GST Rate
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "gstRateCell")
            cell.textLabel?.text = "  GST Rate"
            let rate = entry.gstRate
            cell.detailTextLabel?.text = rate != nil ? "\(rate!)%" : "Tap to Select"
            cell.detailTextLabel?.textColor = rate != nil ? .label : .secondaryLabel
            cell.textLabel?.font = .systemFont(ofSize: 17)
            cell.detailTextLabel?.font = .systemFont(ofSize: 17)
            cell.accessoryType = .disclosureIndicator
            cell.contentView.backgroundColor = .cell
            cell.backgroundColor = .cell
            return cell

        case .lowStock:
            // Low Stock Alert
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "  Low Stock Alert"
            cell.textField.placeholder = "Enter count"
            cell.textField.keyboardType = .numberPad
            cell.textField.text = entry.lowStockThreshold > 0 ? "\(entry.lowStockThreshold)" : ""
            cell.textField.isUserInteractionEnabled = true
            cell.accessoryType = .none
            cell.onTextChanged = { [weak self] text in
                self?.entries[entryIndex].lowStockThreshold = Int(text) ?? 0
            }
            return cell
            
        case .expiry:
            // Expiry Date Row
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelDatePickerTableViewCell", for: indexPath) as! LabelDatePickerTableViewCell
            cell.titleLabel.text = "  Expiry"
            cell.datePicker.date = entry.expiryDate
            cell.datePicker.tag = entryIndex
            cell.onDateChanged = { [weak self] date in
                self?.entries[entryIndex].expiryDate = date
            }
            return cell
            
        case .barcode:
            // Barcode
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "  Barcode"
            cell.textField.placeholder = "Scan or enter..."
            cell.textField.text = entry.barcode ?? ""
            cell.textField.keyboardType = .default
            cell.textField.isUserInteractionEnabled = true
            cell.accessoryType = .none
            cell.onTextChanged = { [weak self] text in
                self?.entries[entryIndex].barcode = text
            }
            
            let scanBtn = UIButton(type: .system)
            scanBtn.setImage(UIImage(systemName: "barcode.viewfinder"), for: .normal)
            scanBtn.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
            scanBtn.tag = entryIndex
            scanBtn.addTarget(self, action: #selector(scanBarcodeTapped(_:)), for: .touchUpInside)
            
            cell.textField.rightView = scanBtn
            cell.textField.rightViewMode = .always
            return cell
            
        case .photoRecord:
            // Photo / Record / Delete buttons
            let cell = UITableViewCell()
            cell.selectionStyle = .none
            
            // Photo buttons
            let addPhotoBtn = UIButton(type: .system)
            let cameraConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            addPhotoBtn.setImage(UIImage(systemName: "camera.badge.ellipsis", withConfiguration: cameraConfig), for: .normal)
            addPhotoBtn.setTitle(" Photo", for: .normal)
            addPhotoBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            addPhotoBtn.tag = entryIndex
            addPhotoBtn.addTarget(self, action: #selector(addPhotoForEntry(_:)), for: .touchUpInside)
            addPhotoBtn.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(addPhotoBtn)
            
            let recordBtn = UIButton(type: .system)
            let recordConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            recordBtn.setImage(UIImage(systemName: "record.circle", withConfiguration: recordConfig), for: .normal)
            recordBtn.setTitle(" Record", for: .normal)
            recordBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            recordBtn.tag = entryIndex
            recordBtn.addTarget(self, action: #selector(recordVideoForEntry(_:)), for: .touchUpInside)
            recordBtn.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(recordBtn)
            
            // Delete button
            let deleteBtn = UIButton(type: .system)
            deleteBtn.setImage(UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)), for: .normal)
            deleteBtn.tintColor = .systemRed
            deleteBtn.tag = entryIndex
            deleteBtn.addTarget(self, action: #selector(deleteItem(_:)), for: .touchUpInside)
            deleteBtn.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(deleteBtn)
            
            let photoCount = entry.pendingItemPhotos.count
            let subtitle = UILabel()
            subtitle.text = photoCount > 0 ? "\(photoCount) frames" : ""
            subtitle.font = .systemFont(ofSize: 11)
            subtitle.textColor = photoCount > 0 ? UIColor(named: "Lime Moss")! : .secondaryLabel
            subtitle.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(subtitle)
            cell.contentView.backgroundColor = .cell
            NSLayoutConstraint.activate([
                addPhotoBtn.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                addPhotoBtn.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                addPhotoBtn.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
                
                recordBtn.centerYAnchor.constraint(equalTo: addPhotoBtn.centerYAnchor),
                recordBtn.leadingAnchor.constraint(equalTo: addPhotoBtn.trailingAnchor, constant: 24),
                
                subtitle.centerYAnchor.constraint(equalTo: addPhotoBtn.centerYAnchor),
                subtitle.leadingAnchor.constraint(equalTo: recordBtn.trailingAnchor, constant: 12),
                
                deleteBtn.centerYAnchor.constraint(equalTo: addPhotoBtn.centerYAnchor),
                deleteBtn.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            ])
            
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard Section(rawValue: section) == .items else { return nil }

        let container = UIView()

        let title = UILabel()
        title.text = "Item Details"
        title.textColor = .gray
        title.font = .preferredFont(forTextStyle: .headline)

        let stack = UIStackView(arrangedSubviews: [title, UIView()])
        stack.axis = .horizontal

        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if tableView == suggestionsTableView {
            return nil
        }
        return Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if tableView == suggestionsTableView {
            return 0.01
        }
        guard Section(rawValue: section) == .items else { return UITableView.automaticDimension }
        return 44
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == suggestionsTableView {
            let selectedItem = currentSuggestions[indexPath.row]
            guard let field = activeNameField else { return }
            let index = field.tag
            guard index >= 0 && index < entries.count else { return }

            entries[index].selectedItemName = selectedItem.name
            entries[index].selectedItemID = selectedItem.id
            entries[index].selectedUnitName = selectedItem.unit
            // Forcefully override with the selected item's cost and selling prices
            entries[index].costPrice = selectedItem.defaultCostPrice
            entries[index].sellingPrice = selectedItem.defaultSellingPrice
            // Auto-fill GST fields from matched item
            if let hsn = selectedItem.hsnCode { entries[index].hsnCode = hsn }
            if let rate = selectedItem.gstRate { entries[index].gstRate = rate }

            field.text = selectedItem.name
            suggestionsTableView.isHidden = true
            suggestionsTableView.removeFromSuperview()
            field.resignFirstResponder()
            tableView.deselectRow(at: indexPath, animated: true)
            self.tableView.reloadSections(IndexSet([Section.items.rawValue, Section.summary.rawValue]), with: .none)
            return
        }

        if Section(rawValue: indexPath.section) == .supplier {
            if let vc = storyboard?.instantiateViewController(withIdentifier: "SupplierSelectionViewController") as? SupplierSelectionViewController {
                vc.delegate = self
                navigationController?.pushViewController(vc, animated: true)
            }
        }

        if Section(rawValue: indexPath.section) == .items {
            let resolved = resolveItemRow(indexPath.row)
            
            // "Add Item" row
            let addItemRow: Int
            if entries.isEmpty {
                addItemRow = 0
            } else if let expanded = expandedItemIndex, expanded < entries.count {
                addItemRow = entries.count + detailRowCount()
            } else {
                addItemRow = entries.count
            }
            
            if indexPath.row == addItemRow {
                self.entries.append(PurchaseEntry())
                self.expandedItemIndex = self.entries.count - 1
                self.tableView.reloadData()
                return
            }
            
            // Detail row: item row -> navigate to item selection
            if resolved.isDetailRow {
                let rowTypes = detailRowTypes()
                guard resolved.detailRow < rowTypes.count else { return }
                let rowType = rowTypes[resolved.detailRow]
                
                if rowType == .itemName {
                    expandedUnitEntryIndex = resolved.entryIndex
                    if let storyboard = storyboard,
                       let itemVC = storyboard.instantiateViewController(withIdentifier: "PurchaseItemSelectionTableViewController") as? PurchaseItemSelectionTableViewController {
                        itemVC.delegate = self
                        navigationController?.pushViewController(itemVC, animated: true)
                    } else {
                        let itemVC = PurchaseItemSelectionTableViewController(style: .plain)
                        itemVC.delegate = self
                        navigationController?.pushViewController(itemVC, animated: true)
                    }
                    return
                }
                
                // Detail row: unit row -> navigate to unit selection
                if rowType == .unit {
                    expandedUnitEntryIndex = resolved.entryIndex
                    if let storyboard = storyboard,
                       let unitVC = storyboard.instantiateViewController(withIdentifier: "PurchaseUnitSelectionTableViewController") as? PurchaseUnitSelectionTableViewController {
                        unitVC.unitDelegate = self
                        navigationController?.pushViewController(unitVC, animated: true)
                    } else {
                        let unitVC = PurchaseUnitSelectionTableViewController(style: .plain)
                        unitVC.unitDelegate = self
                        unitVC.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
                        navigationController?.pushViewController(unitVC, animated: true)
                    }
                    return
                }
                
                // Detail row: GST Rate -> show rate picker
                if rowType == .gstRate {
                    let entryIdx = resolved.entryIndex
                    let alert = UIAlertController(title: "Select GST Rate", message: nil, preferredStyle: .actionSheet)
                    for rate in [0.0, 0.25, 3.0, 5.0, 12.0, 18.0, 28.0] {
                        let title = rate == 0 ? "Exempt (0%)" : "\(rate)%"
                        alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                            self?.entries[entryIdx].gstRate = rate
                            self?.tableView.reloadSections(IndexSet(integer: Section.items.rawValue), with: .none)
                        })
                    }
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                    if let popover = alert.popoverPresentationController,
                       let cell = tableView.cellForRow(at: indexPath) {
                        popover.sourceView = cell
                        popover.sourceRect = cell.bounds
                    }
                    present(alert, animated: true)
                    return
                }
                
                return  // other detail rows handle their own interaction
            }
            
            // Summary row tapped — toggle expand/collapse
            if !resolved.isDetailRow && resolved.entryIndex < entries.count {
                if expandedItemIndex == resolved.entryIndex {
                    expandedItemIndex = nil
                } else {
                    expandedItemIndex = resolved.entryIndex
                }
                tableView.reloadSections(IndexSet(integer: Section.items.rawValue), with: .automatic)
            }
        }
    }
    
    /// Tracks which entry's unit is being selected
    private var expandedUnitEntryIndex: Int = 0

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            suggestionsTableView.isHidden = true
            suggestionsTableView.removeFromSuperview()
        }
    }
    
    // MARK: - Actions

    @objc private func deleteItem(_ sender: UIButton) {
        let index = sender.tag
        guard index < entries.count else { return }

        if expandedItemIndex == index {
            expandedItemIndex = nil
        } else if let expanded = expandedItemIndex, expanded > index {
            expandedItemIndex = expanded - 1
        }
        
        entries.remove(at: index)
        tableView.reloadSections(IndexSet([Section.items.rawValue, Section.summary.rawValue]), with: .automatic)
    }

    @objc private func payLaterToggleChanged(_ sender: UISwitch) {
        isPayLaterEnabled = sender.isOn
    }

    @objc private func expiryDateChanged(_ sender: UIDatePicker) {
        let index = sender.tag
        guard index < entries.count else { return }
        entries[index].expiryDate = sender.date
    }
    
    @objc private func detailNameEditingDidBegin(_ sender: UITextField) {
        activeNameField = sender
        updateSuggestions(for: sender.text ?? "")
    }
    
    @objc private func detailNameEditingChanged(_ sender: UITextField) {
        let index = sender.tag
        guard index >= 0 && index < entries.count else { return }
        entries[index].selectedItemName = sender.text
        entries[index].selectedItemID = nil
        syncInventoryMatchForEntry(at: index)
        if sender.isFirstResponder {
            activeNameField = sender
            updateSuggestions(for: sender.text ?? "")
        }
    }
    
    @objc private func detailNameEditingDidEnd(_ sender: UITextField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.suggestionsTableView.isHidden = true
            self?.suggestionsTableView.removeFromSuperview()
        }
    }
    
    // MARK: - Photo/Video for expanded entries
    
    @objc private func scanBarcodeTapped(_ sender: UIButton) {
        let entryIndex = sender.tag
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            let alert = UIAlertController(title: "Error", message: "Camera unavailable", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let scanVC = QuickBarcodeScanViewController()
        scanVC.onBarcodeScanned = { [weak self] barcode in
            guard let self = self else { return }
            self.entries[entryIndex].barcode = barcode
            DispatchQueue.main.async {
                self.tableView.reloadSections(IndexSet(integer: Section.items.rawValue), with: .none)
            }
        }
        let nav = UINavigationController(rootViewController: scanVC)
        present(nav, animated: true)
    }

    @objc private func addPhotoForEntry(_ sender: UIButton) {
        let entryIndex = sender.tag
        guard entryIndex < entries.count else { return }
        
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
            self?.presentCameraForEntry(at: entryIndex)
        })
        alert.addAction(UIAlertAction(title: "Choose from Library", style: .default) { [weak self] _ in
            self?.presentPhotoPickerForEntry(at: entryIndex)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    @objc private func recordVideoForEntry(_ sender: UIButton) {
        let entryIndex = sender.tag
        guard entryIndex < entries.count else { return }
        
        let vc = InventoryCaptureVideoViewController()
        vc.onComplete = { [weak self] images in
            guard let self = self, !images.isEmpty else { return }
            self.entries[entryIndex].pendingItemPhotos.append(contentsOf: images)
            DispatchQueue.main.async {
                self.tableView.reloadSections(IndexSet(integer: Section.items.rawValue), with: .none)
            }
        }
        vc.onCancel = { /* nothing */ }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
    
    private var photoTargetEntryIndex: Int = 0
    
    private func presentCameraForEntry(at index: Int) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        photoTargetEntryIndex = index
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }
    
    private func presentPhotoPickerForEntry(at index: Int) {
        photoTargetEntryIndex = index
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        present(picker, animated: true)
    }
}

// MARK: - SupplierSelectionDelegate

extension AddPurchaseViewController: SupplierSelectionDelegate {
    func didSelectSupplier(name: String) {
        supplierName = name
        supplierTextField.text = name
        tableView.reloadSections(IndexSet(integer: Section.supplier.rawValue), with: .none)
    }
}

// MARK: - PurchaseItemSelectionDelegate
extension AddPurchaseViewController: PurchaseItemSelectionDelegate {
    func itemSelection(_ controller: PurchaseItemSelectionTableViewController, didSelectItem item: String) {
        let index = expandedUnitEntryIndex
        guard index >= 0 && index < entries.count else { return }
        entries[index].selectedItemName = item
        entries[index].selectedItemID = nil
        syncInventoryMatchForEntry(at: index)
        tableView.reloadSections(IndexSet([Section.items.rawValue, Section.summary.rawValue]), with: .automatic)
    }
}

// MARK: - PurchaseUnitSelectionDelegate

extension AddPurchaseViewController: PurchaseUnitSelectionDelegate {
    func unitSelection(_ controller: PurchaseUnitSelectionTableViewController, unit: String) {
        let standardized = UnitConversionService.displayName(for: unit)
        let index = expandedUnitEntryIndex
        guard index >= 0 && index < entries.count else { return }
        
        let oldUnit = entries[index].selectedUnitName ?? "pcs"
        entries[index].selectedUnitName = standardized
        
        // Auto-convert prices when unit changes between compatible families
        if entries[index].costPrice > 0 {
            if let converted = UnitConversionService.shared.convertPrice(from: oldUnit, to: standardized, price: entries[index].costPrice) {
                entries[index].costPrice = converted
            }
        }
        if entries[index].sellingPrice > 0 {
            if let converted = UnitConversionService.shared.convertPrice(from: oldUnit, to: standardized, price: entries[index].sellingPrice) {
                entries[index].sellingPrice = converted
            }
        }
        
        tableView.reloadSections(IndexSet([Section.items.rawValue, Section.summary.rawValue]), with: .none)
    }
}

// MARK: - UIImagePickerControllerDelegate

extension AddPurchaseViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let image = info[.originalImage] as? UIImage {
            let maxDim: CGFloat = 480
            let scale = min(maxDim / max(image.size.width, image.size.height), 1.0)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let compressed = resized?.jpegData(compressionQuality: 0.7),
               let final = UIImage(data: compressed) {
                entries[photoTargetEntryIndex].pendingItemPhotos.append(final)
            } else {
                entries[photoTargetEntryIndex].pendingItemPhotos.append(image)
            }
            tableView.reloadSections(IndexSet(integer: Section.items.rawValue), with: .none)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
