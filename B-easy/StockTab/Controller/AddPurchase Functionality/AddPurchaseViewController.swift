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
            case .paymentType: return "Payment Type"
            case .summary: return "Summary"
            }
        }
    }
    
    private var entries: [PurchaseEntry] = []
    private var supplierName: String?
    private var supplierGSTIN: String?
    private var saveSpinnerOverlay: UIView?
    private var isPayLaterEnabled = false
    private var inventoryCache: [Item] = []
    private var currentSuggestions: [Item] = []
    private let suggestionsContainerView = UIView()
    private let suggestionsTableView = UITableView(frame: .zero, style: .plain)
    private weak var activeNameField: UITextField?
    private weak var activeUnitField: UITextField?
    private var isSuggestingUnits = false
    private var currentUnitSuggestions: [String] = []

    // Index of the expanded item (chevron tapped to show detail fields).
    private var expandedItemIndex: Int? = nil

  
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
        Money.round2(entries.reduce(0) {
            let qty = $1.quantity
            return $0 + Money.line(quantity: qty, rate: $1.costPrice)
        })
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTableTap(_:)))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)
        
        // Apply any data passed before viewDidLoad (e.g. from voice or scan callback)
        if let result = pendingResult {
            pendingResult = nil
            appendEntries(from: result)
        }
        if let result = pendingPurchaseResult {
            pendingPurchaseResult = nil
            appendEntries(fromPurchaseResult: result)
        }
        if entryMode == .manual && entries.isEmpty {
            entries.append(PurchaseEntry())
        }
        setupBackButton()
    }

    @objc private func handleTableTap(_ gesture: UITapGestureRecognizer) {
        if !suggestionsContainerView.isHidden {
            let location = gesture.location(in: suggestionsContainerView)
            if !suggestionsContainerView.bounds.contains(location) {
                dismissSuggestions()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dismissSuggestions()
    }

    deinit {
        suggestionsContainerView.removeFromSuperview()
        suggestionsTableView.removeFromSuperview()
    }

    private func setupBackButton() {
        self.navigationItem.hidesBackButton = true
        let newBackButton = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: self, action: #selector(backButtonTapped))
        self.navigationItem.leftBarButtonItem = newBackButton
        
        self.navigationController?.interactivePopGestureRecognizer?.addTarget(self, action: #selector(handleSwipeGesture))
    }

    @objc private func handleSwipeGesture(gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            if !entries.isEmpty {
                gesture.isEnabled = false
                backButtonTapped()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    gesture.isEnabled = true
                }
            }
        }
    }

    @objc private func backButtonTapped() {
        dismissSuggestions()
        if !entries.isEmpty {
            let alert = UIAlertController(title: "Unsaved Changes", message: "You have an ongoing purchase. Going back will erase this purchase. Are you sure?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Go Back", style: .destructive, handler: { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            }))
            present(alert, animated: true, completion: nil)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    private func setupSuggestionsTableView() {
        suggestionsContainerView.isHidden = true
        suggestionsContainerView.backgroundColor = .clear
        suggestionsContainerView.layer.shadowColor = UIColor.black.cgColor
        suggestionsContainerView.layer.shadowOpacity = 0.15
        suggestionsContainerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        suggestionsContainerView.layer.shadowRadius = 8
        suggestionsContainerView.layer.masksToBounds = false

        suggestionsTableView.backgroundColor = .secondarySystemGroupedBackground
        suggestionsTableView.layer.cornerRadius = 12
        suggestionsTableView.layer.cornerCurve = .continuous
        suggestionsTableView.layer.masksToBounds = true
        suggestionsTableView.clipsToBounds = true
        suggestionsTableView.layer.borderWidth = 1
        suggestionsTableView.layer.borderColor = UIColor.systemGray4.cgColor
        suggestionsTableView.rowHeight = 44
        suggestionsTableView.dataSource = self
        suggestionsTableView.delegate = self
        suggestionsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "PurchaseSuggestionCell")
        suggestionsTableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        suggestionsTableView.sectionHeaderTopPadding = 0

        suggestionsContainerView.addSubview(suggestionsTableView)
        suggestionsTableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            suggestionsTableView.leadingAnchor.constraint(equalTo: suggestionsContainerView.leadingAnchor),
            suggestionsTableView.trailingAnchor.constraint(equalTo: suggestionsContainerView.trailingAnchor),
            suggestionsTableView.topAnchor.constraint(equalTo: suggestionsContainerView.topAnchor),
            suggestionsTableView.bottomAnchor.constraint(equalTo: suggestionsContainerView.bottomAnchor)
        ])
    }

    private func dismissSuggestions() {
        suggestionsContainerView.isHidden = true
        suggestionsContainerView.removeFromSuperview()
        suggestionsTableView.isHidden = true
        currentSuggestions = []
        currentUnitSuggestions = []
        isSuggestingUnits = false
    }

    private func presentSuggestionsDropdown(below field: UIView, desiredHeight: CGFloat) {
        guard let window = view.window else {
            dismissSuggestions()
            return
        }

        let fieldRect = field.convert(field.bounds, to: window)
        let horizontalPadding: CGFloat = 16
        let dropdownWidth = window.bounds.width - (horizontalPadding * 2)

        let spaceBelow = window.bounds.height - fieldRect.maxY - 20
        let yPosition: CGFloat
        if spaceBelow >= desiredHeight {
            yPosition = fieldRect.maxY + 4
        } else {
            yPosition = max(fieldRect.minY - desiredHeight - 4, 60)
        }

        suggestionsContainerView.frame = CGRect(
            x: horizontalPadding,
            y: yPosition,
            width: dropdownWidth,
            height: desiredHeight
        )

        if suggestionsContainerView.superview != window {
            suggestionsContainerView.removeFromSuperview()
            window.addSubview(suggestionsContainerView)
        }

        suggestionsTableView.reloadData()
        suggestionsContainerView.isHidden = false
        suggestionsTableView.isHidden = false
        window.bringSubviewToFront(suggestionsContainerView)
    }

    private func updateSuggestions(for query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            dismissSuggestions()
            return
        }

        if inventoryCache.isEmpty {
            inventoryCache = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        }
        currentSuggestions = InventoryMatcher.shared.getSuggestions(for: normalized, against: inventoryCache)
        guard !currentSuggestions.isEmpty, let field = activeNameField else {
            dismissSuggestions()
            return
        }
        isSuggestingUnits = false

        let rowHeight: CGFloat = 44
        suggestionsTableView.rowHeight = rowHeight
        let maxRows = max(1, min(4, Int((view.bounds.height * 0.45) / rowHeight)))
        let visibleRows = min(currentSuggestions.count, maxRows)
        let desiredHeight = CGFloat(visibleRows) * rowHeight
        presentSuggestionsDropdown(below: field, desiredHeight: desiredHeight)
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
            let scanVC = PurchaseScanCameraViewController.instantiate()
            scanVC.onPurchaseResult = { [weak self] result in
                guard let self = self else { return }
                self.appendEntries(fromPurchaseResult: result)
            }
            scanVC.modalPresentationStyle = .fullScreen
            present(scanVC, animated: true)
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
            
            // Extract numeric quantity from unit if fused (e.g. "500g" -> 500.0, "g")
            if let extracted = UnitConversionService.shared.extractQuantityAndUnit(from: finalUnit) {
                inputQty *= extracted.0
                finalUnit = extracted.1
            }
            
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
            
            // Force mapping of any extracted selling price to cost price for purchases if cost price is missing
            if finalCostPrice == 0 && finalSellingPrice > 0 {
                finalCostPrice = finalSellingPrice
                finalSellingPrice = 0
            }
            
            var finalQty = inputQty == 0 ? 1.0 : inputQty
            
            let matchedItem = product.itemID.flatMap { id in inventoryItems.first { $0.id == id } }
            
            // Apply unit conversion if matched
            if let inv = matchedItem {
                print("[PurchaseLog] Item=\(inv.name), invUnit=\(inv.unit), reqUnit=\(finalUnit), reqQty=\(inputQty), invCost=\(inv.defaultCostPrice)")
                if let conversion = UnitConversionService.shared.calculateProrated(
                    requestedQty: inputQty,
                    requestedUnit: finalUnit,
                    inventoryPrice: inv.defaultCostPrice,
                    inventoryUnit: inv.unit,
                    alternateUnitName: inv.alternateUnitName,
                    alternateUnitFactor: inv.alternateUnitFactor
                ) {
                    finalQty = conversion.quantity
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
            
            if let extracted = UnitConversionService.shared.extractQuantityAndUnit(from: finalUnit) {
                inputQty *= extracted.0
                finalUnit = extracted.1
            }
            
            if floor(inputQty) != inputQty {
                let nUnit = UnitConversionService.shared.normalizeUnit(finalUnit)
                if nUnit == "kg" { inputQty *= 1000.0; finalUnit = "g" }
                else if nUnit == "l" { inputQty *= 1000.0; finalUnit = "ml" }
            }
            
            var finalCostPrice: Double = Double(item.costPrice ?? "") ?? 0
            var finalSellingPrice: Double = Double(item.sellingPrice ?? "") ?? 0
            
            // Force mapping of any extracted price to cost price for purchases if cost price is missing
            if finalCostPrice == 0 && finalSellingPrice > 0 {
                finalCostPrice = finalSellingPrice
                finalSellingPrice = 0
            }
            
            var finalQty = inputQty == 0 ? 1.0 : inputQty
            
            let matchedItem = inventoryItems.first(where: { $0.name.lowercased() == item.name.lowercased() })
            
            if let inv = matchedItem {
                if let conversion = UnitConversionService.shared.calculateProrated(
                    requestedQty: inputQty,
                    requestedUnit: finalUnit,
                    inventoryPrice: inv.defaultCostPrice,
                    inventoryUnit: inv.unit,
                    alternateUnitName: inv.alternateUnitName,
                    alternateUnitFactor: inv.alternateUnitFactor
                ) {
                    finalQty = conversion.quantity
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
        
        
        
        tableView.reloadData()
    }

    @IBAction func saveButtonTapped(_ sender: UIBarButtonItem) {
        if entries.isEmpty {
            let alert = UIAlertController(
                title: "Incomplete Details",
                message: "Please fill all necessary fields.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        for (index, entry) in entries.enumerated() {
            let itemName = (entry.selectedItemName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = (entry.selectedUnitName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if itemName.isEmpty || unit.isEmpty || entry.quantity <= 0 || entry.costPrice <= 0 {
                let alert = UIAlertController(
                    title: "Incomplete Details",
                    message: "Please fill all necessary fields.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                    guard let self = self else { return }
                    self.expandedItemIndex = index
                    self.tableView.reloadData()
                    let targetRow = index < self.entries.count ? index : 0
                    let indexPath = IndexPath(row: targetRow, section: Section.items.rawValue)
                    self.tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
                })
                present(alert, animated: true)
                return
            }
        }

        if isPayLaterEnabled {
            let name = (supplierName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                let alert = UIAlertController(
                    title: "Supplier Required",
                    message: "Please select a supplier for credit purchases.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Select Supplier", style: .default) { _ in
                    let supplierIndexPath = IndexPath(row: 0, section: Section.supplier.rawValue)
                    self.tableView.scrollToRow(at: supplierIndexPath, at: .top, animated: true)
                    if let vc = self.storyboard?.instantiateViewController(withIdentifier: "SupplierSelectionViewController") as? SupplierSelectionViewController {
                        vc.delegate = self
                        self.navigationController?.pushViewController(vc, animated: true)
                    }
                })
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                present(alert, animated: true)
                return
            }
        }

        let supplier = supplierName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSupplier = (supplier?.isEmpty == true) ? nil : supplier
        let capturedEntries = entries
        let capturedGSTIN = supplierGSTIN
        let payLater = isPayLaterEnabled
        let dm = AppDataModel.shared.dataModel
        let db = dm.db

        sender.isEnabled = false
        setSaveInProgress(true)

        LedgerIO.run({
            let allItems = try db.getAllItems()
            var nameToItem: [String: Item] = [:]
            for item in allItems {
                nameToItem[item.name.lowercased()] = item
            }

            var purchaseItems: [(itemID: UUID, quantity: Double, costPrice: Double, sellingPrice: Double, expiryDate: Date?)] = []

            for entry in capturedEntries {
                guard let itemNameRaw = entry.selectedItemName else { continue }
                let itemName = itemNameRaw.trimmingCharacters(in: .whitespaces)
                if itemName.isEmpty { continue }

                let key = itemName.lowercased()
                // Services are not stocked — treat as a single line amount (qty 1).
                let quantity = entry.quantity
                let costPrice = entry.costPrice
                let sellingPrice = entry.sellingPrice
                let barcode = entry.barcode?.trimmingCharacters(in: .whitespacesAndNewlines)
                let barcodeValue = (barcode?.isEmpty == false) ? barcode : nil

                if quantity <= 0 { continue }

                let itemID: UUID

                if var existing = nameToItem[key] {
                    itemID = existing.id
                    var needsUpdate = false
                    if existing.hsnCode == nil, let hsn = entry.hsnCode {
                        existing.hsnCode = hsn
                        needsUpdate = true
                    }
                    if existing.gstRate == nil, let rate = entry.gstRate {
                        existing.gstRate = rate
                        needsUpdate = true
                    }
                    if existing.barcode == nil || existing.barcode?.isEmpty == true, let barcodeValue {
                        existing.barcode = barcodeValue
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
                        barcode: barcodeValue,
                        defaultCostPrice: costPrice,
                        defaultSellingPrice: sellingPrice,
                        defaultPriceUpdatedAt: Date(),
                        lowStockThreshold: entry.lowStockThreshold,
                        currentStock: 0,
                        createdDate: Date(),
                        lastRestockDate: nil,
                        isActive: true
                    )
                    newItem.hsnCode = entry.hsnCode
                    newItem.gstRate = entry.gstRate


                    try db.insertItem(newItem)
                    nameToItem[key] = newItem
                    itemID = newItem.id
                }

                purchaseItems.append((
                    itemID: itemID,
                    quantity: quantity,
                    costPrice: costPrice,
                    sellingPrice: sellingPrice,
                    expiryDate: entry.expiryDate
                ))
            }

            guard !purchaseItems.isEmpty else {
                throw DataModelError.custom("Please fill all necessary fields.")
            }

            let transaction = try dm.addMultiItemPurchase(
                items: purchaseItems,
                supplierName: finalSupplier,
                invoiceNumber: nil,
                supplierGSTIN: capturedGSTIN
            )

            if let name = finalSupplier, !name.isEmpty {
                CreditStore.shared.ensureSupplier(named: name, defaultName: "Supplier", gstin: capturedGSTIN)
            }

            if payLater, transaction.totalAmount > 0 {
                // A credit purchase without a supplier name is not recorded -
                // the amount cannot be attributed to anybody.
                CreditStore.shared.addCreditPurchase(
                    amount: transaction.totalAmount,
                    supplierName: finalSupplier,
                    note: "Credit purchase \(transaction.invoiceNumber)"
                )
            }
        }) { [weak self] result in
            guard let self else { return }
            self.setSaveInProgress(false)
            sender.isEnabled = true
            switch result {
            case .success:
                self.dismiss(animated: true)
                self.navigationController?.popViewController(animated: true)
            case .failure(let error):
                let alert = UIAlertController(
                    title: "Error",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func setSaveInProgress(_ saving: Bool) {
        view.isUserInteractionEnabled = !saving
        if saving {
            if saveSpinnerOverlay == nil {
                let overlay = UIView(frame: view.bounds)
                overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                overlay.backgroundColor = UIColor.black.withAlphaComponent(0.25)
                let spinner = UIActivityIndicatorView(style: .large)
                spinner.translatesAutoresizingMaskIntoConstraints = false
                spinner.startAnimating()
                overlay.addSubview(spinner)
                NSLayoutConstraint.activate([
                    spinner.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                    spinner.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
                ])
                view.addSubview(overlay)
                saveSpinnerOverlay = overlay
            }
            saveSpinnerOverlay?.isHidden = false
        } else {
            saveSpinnerOverlay?.removeFromSuperview()
            saveSpinnerOverlay = nil
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
            return isSuggestingUnits ? currentUnitSuggestions.count : currentSuggestions.count
        }
        switch Section(rawValue: section)! {
        case .supplier:
            let isGST = (try? AppDataModel.shared.dataModel.db.getSettings().isGSTRegistered) ?? false
            return isGST ? 2 : 1

        case .items:
            if entries.isEmpty {
                return 1  // "Add Item" row
            } else {
                var count = entries.count + 1
                if let expanded = expandedItemIndex, expanded < entries.count {
                    count += detailRowCount()
                }
                return count
            }

        case .summary:
            return 2
        case .paymentType:
            return 1
        }
    }
    
    
    private func detailRowCount() -> Int {
        guard let expanded = expandedItemIndex, expanded < entries.count else { return 0 }
        return detailRowTypes(for: expanded).count
    }
    
    
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
            cell.backgroundColor = .secondarySystemGroupedBackground
            var content = cell.defaultContentConfiguration()
            if isSuggestingUnits {
                content.text = currentUnitSuggestions[indexPath.row]
            } else {
                content.text = currentSuggestions[indexPath.row].name
            }
            content.textProperties.font = .systemFont(ofSize: 13, weight: .regular)
            content.textProperties.numberOfLines = 1
            cell.contentConfiguration = content
            cell.accessoryType = .none
            return cell
        }

        switch Section(rawValue: indexPath.section)! {

        case .supplier:
            if indexPath.row == 0 {
                let identifier = "supplierNameCell"
                let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .value1, reuseIdentifier: identifier)
                var config = UIListContentConfiguration.valueCell()
                let personConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
                config.image = UIImage(systemName: "person", withConfiguration: personConfig)
                config.imageProperties.tintColor = .label
                config.text = "Supplier Name"
                config.textProperties.font = .preferredFont(forTextStyle: .body)
                config.textProperties.color = .label
                config.secondaryText = supplierName ?? "Tap to select"
                config.secondaryTextProperties.font = .preferredFont(forTextStyle: .body)
                config.secondaryTextProperties.color = supplierName != nil ? .label : .secondaryLabel
                cell.contentConfiguration = config
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                cell.titleLabel.text = "Supplier GSTIN"
                cell.titleLabel.font = .preferredFont(forTextStyle: .body)
                cell.titleLabel.textColor = UIColor(named: "Onyx") ?? .label
                cell.textField.text = supplierGSTIN
                cell.textField.placeholder = "Enter GSTIN"
                cell.textField.font = .preferredFont(forTextStyle: .body)
                cell.textField.textColor = UIColor(named: "Onyx") ?? .label
                cell.textField.autocapitalizationType = .allCharacters
                cell.textField.removeTarget(self, action: nil, for: .allEvents)
                cell.textField.addTarget(self, action: #selector(supplierGSTINChanged(_:)), for: .editingChanged)
                return cell
            }

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
                cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
                cell.backgroundColor = .clear
                cell.contentView.backgroundColor = .clear
                cell.separatorInset = UIEdgeInsets(top: 0, left: 10000, bottom: 0, right: 0)
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
            let isService = false
            let qty = entry.quantity > 0 ? String(format: "%g", entry.quantity) : "Qty"
            let cost = entry.costPrice > 0 ? "₹\(entry.costPrice)" : "Cost"

            cell.titleLabel?.text = name
            if isService {
                cell.detailLabel?.text = cost
            } else {
                cell.detailLabel?.text = "\(qty) × \(cost)"
            }

            let lineQty = isService ? max(entry.quantity, 1) : entry.quantity
            let total = Money.line(quantity: lineQty, rate: entry.costPrice)
            cell.priceLabel?.text = String(format: "₹%.2f", total)

            cell.accessoryView = nil
            cell.accessoryType = .none
            cell.configureExpansion(isExpanded: isExpanded)
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.separatorInset = UIEdgeInsets(top: 0, left: 10000, bottom: 0, right: 0)

            return cell

        case .paymentType:
            let identifier = "payLaterToggleCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
            cell.selectionStyle = .none
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }

            let lime = UIColor(named: "Lime Moss") ?? .systemGreen

            let iconView = UIImageView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            iconView.image = UIImage(systemName: "creditcard", withConfiguration: iconConfig)
            iconView.tintColor = lime
            iconView.contentMode = .scaleAspectFit

            let titleLabel = UILabel()
            titleLabel.text = "Credit Purchase"
            titleLabel.font = .preferredFont(forTextStyle: .body)
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let toggle = UISwitch()
            toggle.isOn = isPayLaterEnabled
            toggle.onTintColor = lime
            toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
            toggle.addTarget(self, action: #selector(payLaterToggleChanged(_:)), for: .valueChanged)

            let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, toggle])
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = 14

            cell.contentView.backgroundColor = .cell
            cell.contentView.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 28),
                iconView.heightAnchor.constraint(equalToConstant: 24),
                stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
                stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16)
            ])

            return cell
        case .summary:
            if indexPath.row == 0 {
                let identifier = "summarySubtotalCell"
                let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .value1, reuseIdentifier: identifier)
                var config = UIListContentConfiguration.valueCell()
                config.text = "Subtotal"
                config.textProperties.font = .preferredFont(forTextStyle: .body)
                config.textProperties.color = .label
                config.secondaryText = String(format: "₹ %.2f", subTotal)
                config.secondaryTextProperties.font = .preferredFont(forTextStyle: .body)
                config.secondaryTextProperties.color = .label
                cell.contentConfiguration = config
                cell.selectionStyle = .none
                return cell
            }

            let identifier = "summaryTotalCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .value1, reuseIdentifier: identifier)
            var config = UIListContentConfiguration.valueCell()
            config.text = "Total (INR)"
            config.textProperties.font = .systemFont(ofSize: 17, weight: .bold)
            config.textProperties.color = .label
            config.secondaryText = String(format: "₹ %.2f", subTotal)
            config.secondaryTextProperties.font = .systemFont(ofSize: 17, weight: .bold)
            config.secondaryTextProperties.color = .label
            cell.contentConfiguration = config
            cell.selectionStyle = .none
            return cell
        
        }
    }
    
    // MARK: - Build Detail Cell for Expanded Item
    
    /// Logical detail row types
    private enum DetailRowType {
        case itemName, unit, quantity, costPrice, sellingPrice
        case hsnCode, gstRate   // GST-only
        case lowStock, expiryToggle, expiry, barcode, deleteItem
    }


    private func detailRowTypes(for entryIndex: Int) -> [DetailRowType] {
        let isGST = (try? AppDataModel.shared.dataModel.db.getSettings())?.isGSTRegistered ?? false
        let isService = false
        var rows: [DetailRowType] = [.itemName, .unit]
        if !isService {
            rows.append(.quantity)
        }
        rows.append(contentsOf: [.costPrice, .sellingPrice])
        if isGST {
            rows.append(contentsOf: [.hsnCode, .gstRate])
        }
        if !isService {
            rows.append(contentsOf: [.lowStock, .expiryToggle])
            if entries[entryIndex].expiryDate != nil {
                rows.append(.expiry)
            }
            rows.append(contentsOf: [.barcode, .deleteItem])
        }
        return rows
    }

    /// Resets a freshly dequeued `LabelTextFieldTableViewCell` so state left over from a
    /// previous row type (most importantly the Unit row's editing handlers) cannot leak into
    /// the row being configured.
    ///
    /// Only targets owned by this view controller are removed — the cell's own
    /// `#selector(textChanged)` target is registered by the cell itself and must survive,
    /// otherwise every `onTextChanged` binding silently stops firing.
    private func resetDetailTextField(_ cell: LabelTextFieldTableViewCell) {
        cell.textField.removeTarget(self, action: nil, for: .allEvents)
        cell.textField.rightView = nil
        cell.textField.rightViewMode = .never
        cell.textField.keyboardType = .default
        cell.textField.isUserInteractionEnabled = true
        cell.textField.tag = 0
        cell.onTextChanged = nil
        cell.accessoryType = .none
    }

    private func buildDetailCell(for entryIndex: Int, detailRow: Int, at indexPath: IndexPath) -> UITableViewCell {
        let entry = entries[entryIndex]
        let rowTypes = detailRowTypes(for: entryIndex)
        guard detailRow < rowTypes.count else { return UITableViewCell() }
        let rowType = rowTypes[detailRow]

        switch rowType {

        case .itemName:
            // Item Name
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            resetDetailTextField(cell)
            cell.titleLabel.text = "  Item"
            cell.titleLabel.textColor = .systemRed
            cell.textField.placeholder = "Add Item"
            cell.textField.text = entry.selectedItemName ?? ""
            cell.textField.tag = entryIndex
            cell.textField.isUserInteractionEnabled = true
            cell.accessoryType = .none
            cell.textField.removeTarget(self, action: nil, for: .allEvents)
            cell.textField.addTarget(self, action: #selector(detailNameEditingDidBegin(_:)), for: .editingDidBegin)
            cell.textField.addTarget(self, action: #selector(detailNameEditingChanged(_:)), for: .editingChanged)
            cell.textField.addTarget(self, action: #selector(detailNameEditingDidEnd(_:)), for: .editingDidEnd)
            return cell
            
        case .unit:
            // Unit
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            resetDetailTextField(cell)
            cell.titleLabel.text = "  Unit"
            cell.titleLabel.textColor = .systemRed
            cell.textField.placeholder = "pcs, kg, etc."
            cell.textField.text = entry.selectedUnitName ?? ""
            cell.textField.isUserInteractionEnabled = true
            cell.accessoryType = .none
            cell.textField.tag = entryIndex
            cell.textField.removeTarget(self, action: nil, for: .allEvents)
            cell.textField.addTarget(self, action: #selector(detailUnitEditingDidBegin(_:)), for: .editingDidBegin)
            cell.textField.addTarget(self, action: #selector(detailUnitEditingChanged(_:)), for: .editingChanged)
            cell.textField.addTarget(self, action: #selector(detailUnitEditingDidEnd(_:)), for: .editingDidEnd)
            return cell
            
        case .quantity:
            // Quantity
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            resetDetailTextField(cell)
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
            resetDetailTextField(cell)
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
            resetDetailTextField(cell)
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
            let isService = false
            resetDetailTextField(cell)
            cell.titleLabel.text = isService ? "  SAC Code" : "  HSN Code"
            cell.textField.placeholder = isService ? "e.g. 9983" : "e.g. 1006"
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
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .systemBackground
            return cell

        case .lowStock:
            // Low Stock Alert — plain numeric threshold, so no item/unit suggestion handlers
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            resetDetailTextField(cell)
            cell.titleLabel.text = "  Low Stock Alert"
            cell.textField.placeholder = "Enter count"
            cell.textField.keyboardType = .numberPad
            cell.textField.text = entry.lowStockThreshold > 0 ? entry.lowStockThreshold.cleanString : ""
            cell.textField.isUserInteractionEnabled = true
            cell.textField.rightView = nil
            cell.textField.rightViewMode = .never
            cell.accessoryType = .none
            cell.onTextChanged = { [weak self] text in
                self?.entries[entryIndex].lowStockThreshold = Double(text) ?? 0
            }
            return cell
            
        case .expiryToggle:
            let identifier = "expiryToggleCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
            cell.selectionStyle = .none
            cell.accessoryView = nil
            cell.accessoryType = .none
            cell.backgroundConfiguration = nil
            cell.backgroundColor = .systemBackground
            cell.contentView.backgroundColor = .systemBackground
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "  Has Expiry Date?"
            label.font = .systemFont(ofSize: 17)
            label.textColor = .label
            
            let toggle = UISwitch()
            toggle.translatesAutoresizingMaskIntoConstraints = false
            toggle.isOn = (entry.expiryDate != nil)
            let lime = UIColor(named: "Lime Moss") ?? .systemGreen
            toggle.onTintColor = lime
            toggle.tag = entryIndex
            toggle.addTarget(self, action: #selector(expiryToggleChanged(_:)), for: .valueChanged)
            
            cell.contentView.addSubview(label)
            cell.contentView.addSubview(toggle)
            
            NSLayoutConstraint.activate([
                cell.contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
                label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),
                
                toggle.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                toggle.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
            ])
            
            return cell
            
        case .expiry:
            // Expiry Date Row
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelDatePickerTableViewCell", for: indexPath) as! LabelDatePickerTableViewCell
            cell.titleLabel.text = "  Expiry"
            cell.datePicker.date = entry.expiryDate ?? Date()
            cell.datePicker.tag = entryIndex
            cell.onDateChanged = { [weak self] date in
                self?.entries[entryIndex].expiryDate = date
            }
            return cell
            
        case .barcode:
            // Barcode
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            resetDetailTextField(cell)
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
            scanBtn.tintColor = UIColor(named: "Lime Moss") ?? .systemGreen
            scanBtn.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
            scanBtn.tag = entryIndex
            scanBtn.addTarget(self, action: #selector(scanBarcodeTapped(_:)), for: .touchUpInside)
            
            cell.textField.rightView = scanBtn
            cell.textField.rightViewMode = .always
            return cell
            
        case .deleteItem:
            let cell = UITableViewCell()
            cell.selectionStyle = .none
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .systemBackground

            cell.contentView.layer.cornerRadius = 14
            cell.contentView.layer.cornerCurve = .continuous
            cell.contentView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            cell.contentView.layer.masksToBounds = true
            cell.contentView.clipsToBounds = true

            cell.layer.cornerRadius = 14
            cell.layer.cornerCurve = .continuous
            cell.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            cell.layer.masksToBounds = true
            cell.clipsToBounds = true
            cell.separatorInset = UIEdgeInsets(top: 0, left: 10000, bottom: 0, right: 0)

            let deleteBtn = UIButton(type: .system)
            let trashConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            deleteBtn.setImage(UIImage(systemName: "trash", withConfiguration: trashConfig), for: .normal)
            deleteBtn.setTitle(" Delete Item", for: .normal)
            deleteBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            deleteBtn.tintColor = .systemRed
            deleteBtn.setTitleColor(.systemRed, for: .normal)
            deleteBtn.tag = entryIndex
            deleteBtn.addTarget(self, action: #selector(deleteItem(_:)), for: .touchUpInside)
            deleteBtn.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(deleteBtn)

            NSLayoutConstraint.activate([
                deleteBtn.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 10),
                deleteBtn.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -10),
                deleteBtn.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16)
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

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if tableView == suggestionsTableView {
            cell.backgroundColor = .secondarySystemGroupedBackground
            return
        }

        guard Section(rawValue: indexPath.section) == .items else { return }

        let addItemRow: Int
        if entries.isEmpty {
            addItemRow = 0
        } else if let expanded = expandedItemIndex, expanded < entries.count {
            addItemRow = entries.count + detailRowCount()
        } else {
            addItemRow = entries.count
        }

        if indexPath.row == addItemRow {
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.separatorInset = UIEdgeInsets(top: 0, left: 10000, bottom: 0, right: 0)
            return
        }

        let resolved = resolveItemRow(indexPath.row)

        if resolved.isDetailRow {
            let rowTypes = detailRowTypes(for: resolved.entryIndex)
            let isLastDetailRow = (resolved.detailRow == rowTypes.count - 1)

            if isLastDetailRow {
                cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
                cell.backgroundColor = .clear
                cell.contentView.backgroundColor = .systemBackground

                cell.contentView.layer.cornerRadius = 14
                cell.contentView.layer.cornerCurve = .continuous
                cell.contentView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                cell.contentView.layer.masksToBounds = true
                cell.contentView.clipsToBounds = true

                cell.layer.cornerRadius = 14
                cell.layer.cornerCurve = .continuous
                cell.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                cell.layer.masksToBounds = true
                cell.clipsToBounds = true

                cell.separatorInset = UIEdgeInsets(top: 0, left: 10000, bottom: 0, right: 0)
            } else {
                cell.backgroundConfiguration = nil
                cell.backgroundColor = .systemBackground
                cell.contentView.backgroundColor = .systemBackground
                cell.layer.cornerRadius = 0
                cell.contentView.layer.cornerRadius = 0
                cell.layer.maskedCorners = []
                cell.contentView.layer.maskedCorners = []
                cell.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
            }
        } else {
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.separatorInset = UIEdgeInsets(top: 0, left: 10000, bottom: 0, right: 0)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == suggestionsTableView {
            if isSuggestingUnits {
                let unit = currentUnitSuggestions[indexPath.row]
                guard let field = activeUnitField else { return }
                
                let index = field.tag
                guard index >= 0 && index < entries.count else { return }
                
                entries[index].selectedUnitName = unit
                field.text = unit
                
                dismissSuggestions()
                field.resignFirstResponder()
                
                self.tableView.reloadSections(IndexSet([Section.items.rawValue, Section.summary.rawValue]), with: .none)
                return
            } else {
                let selectedItem = currentSuggestions[indexPath.row]
                guard let field = activeNameField else { return }
                let index = field.tag
                guard index >= 0 && index < entries.count else { return }

                entries[index].selectedItemName = selectedItem.name
                entries[index].selectedItemID = selectedItem.id
                entries[index].selectedUnitName = selectedItem.unit

                entries[index].costPrice = selectedItem.defaultCostPrice
                entries[index].sellingPrice = selectedItem.defaultSellingPrice

                if let hsn = selectedItem.hsnCode { entries[index].hsnCode = hsn }
                if let rate = selectedItem.gstRate { entries[index].gstRate = rate }

                field.text = selectedItem.name
                dismissSuggestions()
                field.resignFirstResponder()
                tableView.deselectRow(at: indexPath, animated: true)
                self.tableView.reloadSections(IndexSet([Section.items.rawValue, Section.summary.rawValue]), with: .none)
                return
            }
        }

        if Section(rawValue: indexPath.section) == .supplier {
            if indexPath.row == 0 {
                if let vc = storyboard?.instantiateViewController(withIdentifier: "SupplierSelectionViewController") as? SupplierSelectionViewController {
                    vc.delegate = self
                    navigationController?.pushViewController(vc, animated: true)
                }
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
                let rowTypes = detailRowTypes(for: resolved.entryIndex)
                guard resolved.detailRow < rowTypes.count else { return }
                let rowType = rowTypes[resolved.detailRow]
                
                if rowType == .itemName {
                    return
                }
                
                // Detail row: unit row -> now inline
                if rowType == .unit {
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
                
                return  
            }
            
        
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
    

    private var expandedUnitEntryIndex: Int = 0

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            dismissSuggestions()
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
    
    @objc private func purchaseItemTypeChanged(_ sender: UISegmentedControl) {
        let index = sender.tag
        guard index < entries.count else { return }
        if false {
            entries[index].quantity = max(entries[index].quantity, 1)
            entries[index].lowStockThreshold = 0
            entries[index].expiryDate = nil
            entries[index].barcode = nil
        }
        tableView.reloadSections(IndexSet(integer: Section.items.rawValue), with: .automatic)
    }

    @objc private func expiryToggleChanged(_ sender: UISwitch) {
        let index = sender.tag
        guard index < entries.count else { return }

        guard let expanded = expandedItemIndex, expanded == index else {
            entries[index].expiryDate = sender.isOn ? Date() : nil
            return
        }

        let currentRows = detailRowTypes(for: index)
        guard let toggleDetailRow = currentRows.firstIndex(of: .expiryToggle) else {
            entries[index].expiryDate = sender.isOn ? Date() : nil
            tableView.reloadSections(IndexSet(integer: Section.items.rawValue), with: .automatic)
            return
        }

        let expiryDetailRow = toggleDetailRow + 1
        let targetIndexPath = IndexPath(row: expanded + 1 + expiryDetailRow, section: Section.items.rawValue)

        if sender.isOn {
            guard entries[index].expiryDate == nil else { return }
            entries[index].expiryDate = Date()
            tableView.insertRows(at: [targetIndexPath], with: .automatic)
        } else {
            guard entries[index].expiryDate != nil else { return }
            entries[index].expiryDate = nil
            tableView.deleteRows(at: [targetIndexPath], with: .automatic)
        }
    }
    
    @objc private func detailNameEditingDidBegin(_ sender: UITextField) {
        activeUnitField = nil
        isSuggestingUnits = false
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
            guard let self = self else { return }
            if self.isSuggestingUnits || self.activeUnitField != nil {
                return
            }
            if self.activeNameField == sender {
                self.activeNameField = nil
                self.dismissSuggestions()
            }
        }
    }
    
    @objc private func detailUnitEditingDidBegin(_ sender: UITextField) {
        sender.selectAll(nil)
        activeNameField = nil
        activeUnitField = sender
        isSuggestingUnits = true
        updateUnitSuggestions(for: "")
    }

    @objc private func detailUnitEditingChanged(_ sender: UITextField) {
        let index = sender.tag
        guard index >= 0 && index < entries.count else { return }
        entries[index].selectedUnitName = sender.text
        if activeUnitField == sender {
            updateUnitSuggestions(for: sender.text ?? "")
        }
    }

    @objc private func detailUnitEditingDidEnd(_ sender: UITextField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            if !self.isSuggestingUnits || self.activeNameField != nil {
                return
            }
            if self.activeUnitField == sender {
                self.activeUnitField = nil
                self.dismissSuggestions()
            }
        }
    }
    
    private func updateUnitSuggestions(for query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allUnits = UnitConversionService.standardUnits
        
        if normalized.isEmpty {
            currentUnitSuggestions = allUnits
        } else {
            currentUnitSuggestions = allUnits.filter { $0.lowercased().hasPrefix(normalized) }
        }
        
        guard !currentUnitSuggestions.isEmpty, let field = activeUnitField else {
            dismissSuggestions()
            return
        }
        isSuggestingUnits = true

        let rowHeight: CGFloat = 44
        suggestionsTableView.rowHeight = rowHeight
        let maxRows = max(1, min(4, Int((view.bounds.height * 0.45) / rowHeight)))
        let visibleRows = min(currentUnitSuggestions.count, maxRows)
        let desiredHeight = CGFloat(visibleRows) * rowHeight
        presentSuggestionsDropdown(below: field, desiredHeight: desiredHeight)
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
        scanVC.onBarcodeScanned = { [weak self, entryIndex] barcode in
            guard let self = self, entryIndex < self.entries.count else { return }
            self.entries[entryIndex].barcode = barcode

            // 1. Check if barcode already exists in local inventory
            if self.inventoryCache.isEmpty {
                self.inventoryCache = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            }
            if let matched = self.inventoryCache.first(where: { $0.barcode == barcode }) {
                self.entries[entryIndex].selectedItemID = matched.id
                self.entries[entryIndex].selectedItemName = matched.name
                self.entries[entryIndex].selectedUnitName = matched.unit
                if self.entries[entryIndex].costPrice <= 0 {
                    self.entries[entryIndex].costPrice = matched.defaultCostPrice
                }
                if self.entries[entryIndex].sellingPrice <= 0 {
                    self.entries[entryIndex].sellingPrice = matched.defaultSellingPrice
                }
                if self.entries[entryIndex].hsnCode == nil {
                    self.entries[entryIndex].hsnCode = matched.hsnCode
                }
                if self.entries[entryIndex].gstRate == nil {
                    self.entries[entryIndex].gstRate = matched.gstRate
                }

                if self.entries[entryIndex].quantity <= 0 {
                    self.entries[entryIndex].quantity = 1
                }
                DispatchQueue.main.async {
                    self.tableView.reloadSections(IndexSet([Section.items.rawValue, Section.summary.rawValue]), with: .none)
                }
                return
            }

        
            DispatchQueue.main.async {
                self.tableView.reloadSections(IndexSet([Section.items.rawValue, Section.summary.rawValue]), with: .none)
            }

            // 2. Unknown barcode -> lookup in Open Food Facts catalog
            OpenFoodFactsService.shared.lookupBarcode(barcode) { [weak self] productInfo in
                guard let self = self, entryIndex < self.entries.count, let info = productInfo else { return }

    
                let matches = BarcodeMatcher.shared.findMatches(for: info.displayName, in: self.inventoryCache)
                if let bestMatch = matches.first, bestMatch.confidence >= 0.70 {
                    // Match found in existing inventory! Map with it and link barcode
                    var updated = bestMatch.item
                    updated.barcode = barcode
                    try? AppDataModel.shared.dataModel.db.updateItem(updated)
                    if let idx = self.inventoryCache.firstIndex(where: { $0.id == updated.id }) {
                        self.inventoryCache[idx] = updated
                    }

                    self.entries[entryIndex].selectedItemID = updated.id
                    self.entries[entryIndex].selectedItemName = updated.name
                    self.entries[entryIndex].selectedUnitName = updated.unit
                    if self.entries[entryIndex].costPrice <= 0 {
                        self.entries[entryIndex].costPrice = updated.defaultCostPrice
                    }
                    if self.entries[entryIndex].sellingPrice <= 0 {
                        self.entries[entryIndex].sellingPrice = updated.defaultSellingPrice
                    }
                    if self.entries[entryIndex].hsnCode == nil {
                        self.entries[entryIndex].hsnCode = updated.hsnCode
                    }
                    if self.entries[entryIndex].gstRate == nil {
                        self.entries[entryIndex].gstRate = updated.gstRate
                    }

                    if self.entries[entryIndex].quantity <= 0 {
                        self.entries[entryIndex].quantity = 1
                    }
                } else {
                    // Not in local inventory: autofill with details from Open Food Facts
                    let currentName = (self.entries[entryIndex].selectedItemName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if currentName.isEmpty {
                        self.entries[entryIndex].selectedItemName = info.displayName
                    }

                    let currentUnit = (self.entries[entryIndex].selectedUnitName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if currentUnit.isEmpty || currentUnit.lowercased() == "pcs" {
                        self.entries[entryIndex].selectedUnitName = info.inferredUnit
                    }

                    if self.entries[entryIndex].quantity <= 0 {
                        self.entries[entryIndex].quantity = 1
                    }

                    // Map GST / HSN from HSNDatabase
                    if self.entries[entryIndex].hsnCode == nil || self.entries[entryIndex].gstRate == nil {
                        if let hsnMatch = HSNDatabase.shared.searchByName(query: info.displayName) {
                            if self.entries[entryIndex].hsnCode == nil {
                                self.entries[entryIndex].hsnCode = hsnMatch.code
                            }
                            if self.entries[entryIndex].gstRate == nil {
                                self.entries[entryIndex].gstRate = hsnMatch.gstRate
                            }
                        }
                    }

                    // Also check GlobalCatalogService for default prices if available
                    if self.entries[entryIndex].costPrice <= 0 || self.entries[entryIndex].sellingPrice <= 0 {
                        GlobalCatalogService.shared.search(query: info.displayName, limit: 1) { [weak self] catalogProducts in
                            guard let self = self, entryIndex < self.entries.count, let first = catalogProducts.first else { return }
                            if self.entries[entryIndex].costPrice <= 0, let cp = first.defaultCostPrice, cp > 0 {
                                self.entries[entryIndex].costPrice = cp
                            }
                            if self.entries[entryIndex].sellingPrice <= 0, let sp = first.defaultSellingPrice, sp > 0 {
                                self.entries[entryIndex].sellingPrice = sp
                            }
                            DispatchQueue.main.async {
                                self.tableView.reloadSections(IndexSet([Section.items.rawValue, Section.summary.rawValue]), with: .none)
                            }
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.tableView.reloadSections(IndexSet([Section.items.rawValue, Section.summary.rawValue]), with: .none)
                }
            }
        }
        let nav = UINavigationController(rootViewController: scanVC)
        present(nav, animated: true)
    }
}

// MARK: - SupplierSelectionDelegate

extension AddPurchaseViewController: SupplierSelectionDelegate {
    func didSelectSupplier(name: String) {
        supplierName = name
        supplierTextField.text = name
        
        // Auto-fill GSTIN from stored supplier profile
        let all = CreditStore.shared.getAllSuppliers()
        if let supplier = all.first(where: { $0.name == name }), let gstin = supplier.gstin, !gstin.isEmpty {
            supplierGSTIN = gstin
        }
        
        tableView.reloadSections(IndexSet(integer: Section.supplier.rawValue), with: .none)
    }
}

// MARK: - Supplier GSTIN

extension AddPurchaseViewController {
    @objc func supplierGSTINChanged(_ sender: UITextField) {
        let text = sender.text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        
        if sender.text != text {
            let cursorPos = sender.selectedTextRange
            sender.text = text
            sender.selectedTextRange = cursorPos
        }
        supplierGSTIN = text.isEmpty ? nil : text
        sender.textColor = UIColor(named: "Onyx") ?? .label
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
