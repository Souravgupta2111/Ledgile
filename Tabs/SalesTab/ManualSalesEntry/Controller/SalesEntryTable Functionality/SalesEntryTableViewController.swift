import UIKit

enum EntryMode {
    case manual
    case voice
    case camera
}

class SalesEntryTableViewController: UITableViewController, UITextFieldDelegate {
    var billSaved: Bool = false
    var transactionID = UUID()
    var customerName: String?
    var notes: String?
    var transactionItems: [TransactionItem] = []
    var discountAmount: Double = 0
    var adjustmentAmount: Double = 0
    var isCreditEnabled = false
    
    // New GST fields
    var buyerGSTIN: String?
    var buyerStateCode: String?
    
    // UI Elements
    private let discountLabel = UILabel()
    private var discountTextField = UITextField()
    
    private let adjustmentLabel = UILabel()
    private var adjustmentTextField = UITextField()
    
    private var descriptionTextView: UITextView?

    private let editButton = UIButton(type: .system)
    
    /// Generated once per entry session
    var generatedInvoiceNumber: String = {
        AppDataModel.shared.dataModel.generateInvoiceNumber()
    }()
    
    var subTotal: Double {
        transactionItems.reduce(0) { $0 + $1.totalRevenue }
    }
    var grandTotal: Double {
        subTotal - discountAmount + adjustmentAmount
    }
    private var isEditingEnabled = false {
        didSet {
            tableView.reloadData()
            editButton.setTitle(isEditingEnabled ? "Done" : "Edit", for: .normal)
        }
    }
    var customerNameField = UITextField()
    var inventoryCache: [Item] = []
    private var currentSuggestions: [Item] = []
    private let suggestionsTableView = UITableView(frame: .zero, style: .plain)
    private weak var activeNameField: UITextField?
    
    /// Holds scan/voice result passed before viewDidLoad; consumed in viewDidLoad.
    var pendingResult: ParsedResult?
    var entryMode: EntryMode = .manual
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = UIColor.systemGray6
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.rowHeight = UITableView.automaticDimension
        
        tableView.register(UINib(nibName: "SalesItemTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "SalesItemTableViewCell")
        tableView.register(UINib(nibName: "LabelTextFieldTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "LabelTextFieldTableViewCell")
        tableView.register(UINib(nibName: "AddNewItemTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "AddNewItemTableViewCell")
        tableView.register(UINib(nibName: "EditSalesItemTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "EditSalesItemTableViewCell")
        tableView.register(UINib(nibName: "TextViewTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "TextViewTableViewCell")
        tableView.register(UINib(nibName: "TwoLabelsTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "TwoLabelsTableViewCell")
        
        if inventoryCache.isEmpty {
            inventoryCache = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        }

        setupSuggestionsTableView()
        
        // Apply any data passed before viewDidLoad (e.g. from scan callback)
        if let result = pendingResult {
            pendingResult = nil
            // entryMode is already set by the caller before pushing this VC
            appendItems(from: result)
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
        suggestionsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "InventorySuggestionCell")
        
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
        
        // Convert the text field's frame to window coordinates
        let fieldRect = field.convert(field.bounds, to: window)
        
        let horizontalPadding: CGFloat = 16
        let dropdownWidth = window.bounds.width - (horizontalPadding * 2)
        let desiredHeight = min(CGFloat(currentSuggestions.count) * suggestionsTableView.rowHeight, 220)
        
        // Position below the text field, or above if not enough space below
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

    private func syncInventoryMatchForItem(at index: Int) {
        guard index >= 0 && index < transactionItems.count else { return }
        let old = transactionItems[index]
        let typedName = old.itemName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !typedName.isEmpty else { return }
        guard let matched = inventoryCache.first(where: { $0.name.caseInsensitiveCompare(typedName) == .orderedSame }) else { return }

        let resolvedPrice = ((old.sellingPricePerUnit ?? 0) > 0) ? old.sellingPricePerUnit : matched.defaultSellingPrice
        let updated = TransactionItem(
            id: old.id,
            transactionID: old.transactionID,
            itemID: matched.id,
            itemName: matched.name,
            unit: matched.unit,
            quantity: old.quantity,
            sellingPricePerUnit: resolvedPrice,
            costPricePerUnit: old.costPricePerUnit,
            createdDate: old.createdDate
        )
        transactionItems[index] = updated
    }

    // MARK: - Add New Item (re-open voice/camera if entry started that way)
    
    private func addNewItemByEntryMode() {
        switch entryMode {
        case .voice:
            if let sb = storyboard,
               let vc = sb.instantiateViewController(withIdentifier: "VoiceEntryViewController") as? VoiceEntryViewController {
                vc.onItemsParsed = { [weak self] result in
                    guard let self = self else { return }
                    self.appendItems(from: result)
                    self.navigationController?.popToViewController(self, animated: true)
                }
                navigationController?.pushViewController(vc, animated: true)
            }
        case .camera:
            let scanVC = ScanCameraViewController(mode: .sale)
            scanVC.onSaleResult = { [weak self] result in
                guard let self = self else { return }
                self.appendItems(from: result)
            }
            let nav = UINavigationController(rootViewController: scanVC)
            nav.modalPresentationStyle = .fullScreen
            present(nav, animated: true)
        case .manual:
            performSegue(withIdentifier: "item_information", sender: nil)
        }
    }

    // MARK: - Append Items from Voice/Scan
    
    // Temporary queue for fuzzy matches waiting for user confirmation
    private var pendingFuzzyMatches: [(product: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?, itemID: UUID?, matchConfidence: Double, originalName: String)].Element, transactionItem: TransactionItem)] = []
    
    func appendItems(from result: ParsedResult) {
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
            let voicePrice = Double(product.price ?? "")
            var finalUnit = product.unit ?? "pcs"
            var finalSellingPrice: Double
            
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
            
            var finalQtyInt = Int(round(inputQty)) == 0 ? 1 : Int(round(inputQty))
            
            let matchedItem = product.itemID.flatMap { id in inventoryItems.first { $0.id == id } }

            // Apply conversions if matched
            if let inv = matchedItem {
                print("[VoiceSale] Item=\(inv.name), invUnit=\(inv.unit), reqUnit=\(finalUnit), reqQty=\(inputQty), invPrice=\(inv.defaultSellingPrice)")
                // Determine if we need to pro-rate based on different units
                if let conversion = UnitConversionService.shared.calculateProrated(
                    requestedQty: inputQty,
                    requestedUnit: finalUnit,
                    inventoryPrice: inv.defaultSellingPrice,
                    inventoryUnit: inv.unit
                ) {
                    finalQtyInt = conversion.quantity
                    finalUnit = conversion.unit
                    
                    // If user explicitly stated a price, use it; otherwise pro-rate
                    if let vp = voicePrice {
                        finalSellingPrice = vp
                    } else {
                        finalSellingPrice = conversion.proratedPrice
                    }
                    print("[VoiceSale] ✓ Converted: qty=\(finalQtyInt), unit=\(finalUnit), price=\(finalSellingPrice)")
                } else {
                    // Same units or incompatible, just use default lookup
                    finalSellingPrice = voicePrice ?? inv.defaultSellingPrice
                    finalUnit = inv.unit
                    print("[VoiceSale] ✗ No conversion needed/possible, using price=\(finalSellingPrice), unit=\(finalUnit)")
                }
            } else {
                finalSellingPrice = voicePrice ?? 0
                print("[VoiceSale] ✗ No match found for '\(product.name)', price=\(finalSellingPrice)")
            }

            let matchedName = product.name
            let originalName = product.originalName
            let matchedParts = matchedName.components(separatedBy: .whitespaces)
            let originalParts = originalName.components(separatedBy: .whitespaces)

            if let firstWord = matchedParts.first, let firstDigit = Int(firstWord) {
                let originalStartsWithDigit = originalParts.first.flatMap { Int($0) } != nil
                if !originalStartsWithDigit {
                    if product.quantity.hasSuffix(String(firstDigit)) {
                        let newQtyString = String(product.quantity.dropLast())
                        if newQtyString.isEmpty {
                            finalQtyInt = 1
                        } else if let newQty = Int(newQtyString) {
                            finalQtyInt = newQty
                        }
                    }
                }
            }

            let transactionItem = TransactionItem(
                id: UUID(),
                transactionID: transactionID,
                itemID: matchedItem?.id ?? UUID(),
                itemName: product.name,
                unit: finalUnit,
                quantity: finalQtyInt,
                sellingPricePerUnit: finalSellingPrice,
                costPricePerUnit: nil, // filled later via FIFO
                createdDate: Date()
            )

            // Queue fuzzy matches for confirmation
            if matchedItem != nil && product.matchConfidence < 0.90 {
                pendingFuzzyMatches.append((product, transactionItem))
            } else {
                transactionItems.append(transactionItem)
            }
        }

        if let customer = result.customerName {
            customerName = customer
        }

        tableView.reloadData()
        
        // Present confirmation dialogs if any
        processNextFuzzyMatch()
    }
    
    // Explicit confirmation UI loop
    private func processNextFuzzyMatch() {
        guard !pendingFuzzyMatches.isEmpty else {
            tableView.reloadData()
            return
        }
        
        let pending = pendingFuzzyMatches.removeFirst()
        let prod = pending.product
        let txItem = pending.transactionItem
        
        let alert = UIAlertController(
            title: "Confirm Match",
            message: "We matched '\(prod.originalName)' to your inventory item '\(prod.name)'. Is this correct?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Yes, use '\(prod.name)'", style: .default, handler: { _ in
            self.transactionItems.append(txItem)
            self.processNextFuzzyMatch()
        }))
        
        alert.addAction(UIAlertAction(title: "No, keep '\(prod.originalName)'", style: .destructive, handler: { _ in
            let newTx = TransactionItem(
                id: txItem.id,
                transactionID: txItem.transactionID,
                itemID: UUID(), // detach from inventory
                itemName: prod.originalName,
                unit: txItem.unit,
                quantity: txItem.quantity,
                sellingPricePerUnit: txItem.sellingPricePerUnit,
                costPricePerUnit: txItem.costPricePerUnit,
                createdDate: txItem.createdDate
            )
            self.transactionItems.append(newTx)
            self.processNextFuzzyMatch()
        }))
        
        present(alert, animated: true)
    }

    @IBAction func saveButtonTapped(_ sender: UIBarButtonItem) {
        // Credit validation: customer name is required for credit sales
        if isCreditEnabled {
            let name = (customerNameField.text ?? customerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                let alert = UIAlertController(
                    title: "Customer Required",
                    message: "Customer name is required for credit sales.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    self.customerNameField.becomeFirstResponder()
                })
                present(alert, animated: true)
                return
            }
        }
        performSegue(withIdentifier: "show_bill", sender: nil)
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "item_information",
           let dest = segue.destination as? ItemInformationTableViewController {
            dest.delegate = self
        }
        if segue.identifier == "show_bill" {
            let details = makeBillingDetails()
            let billVC: BillTableViewController?
            if let nav = segue.destination as? UINavigationController {
                billVC = nav.topViewController as? BillTableViewController
                nav.modalPresentationStyle = .pageSheet
            } else {
                billVC = segue.destination as? BillTableViewController
                billVC?.modalPresentationStyle = .pageSheet
            }
            billVC?.receiveBilling(details: details)
            if let sheet = billVC?.sheetPresentationController {
                if details.items.count <= 2 {
                    sheet.detents = [.medium()]
                } else {
                    sheet.detents = [.medium(), .large()]
                }
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 20
            }
                billVC?.delegate = self
        }
        if segue.identifier == "selectCustomer",
           let dest = segue.destination as? CustomerSelectionViewController {
            dest.delegate = self
        }
    }
    
    private func makeBillingDetails() -> BillingDetails {
        // Prefer live text field value, fall back to synced model property
        let name = customerNameField.text?.isEmpty == false ? customerNameField.text! : (customerName ?? "")
        
        // Compute tax breakup if GST is registered
        var taxBreakup: GSTBreakup? = nil
        var sellerGSTIN: String? = nil
        var sellerState: String? = nil
        var placeOfSupply: String? = nil
        var isInterState = false
        var isCompositionScheme = false
        
        var finalTxItems = transactionItems
        
        if let settings = try? AppDataModel.shared.dataModel.db.getSettings(),
           settings.isGSTRegistered, settings.gstScheme != "composition" {
            sellerGSTIN = settings.gstNumber
            sellerState = settings.businessState
            
            let buyerCode = buyerStateCode ?? (buyerGSTIN != nil ? String(buyerGSTIN!.prefix(2)) : settings.businessStateCode)
            isInterState = GSTEngine.isInterStateSupply(
                sellerStateCode: settings.businessStateCode,
                buyerStateCode: buyerCode
            )
            placeOfSupply = IndianStates.stateByCode(buyerCode ?? "")?.name
            
            var itemResults: [(gstRate: Double, result: ItemTaxResult)] = []
            let allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            let nameToItem: [String: Item] = Dictionary(allItems.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
            
            for i in 0..<finalTxItems.count {
                let key = finalTxItems[i].itemName.lowercased()
                if let item = nameToItem[key], let gstRate = item.gstRate {
                    let price = finalTxItems[i].sellingPricePerUnit ?? 0
                    let taxResult = GSTEngine.calculateTax(
                        price: price,
                        quantity: finalTxItems[i].quantity,
                        gstRate: gstRate,
                        cessRate: item.cessRate ?? 0,
                        isInterState: isInterState,
                        pricesIncludeGST: settings.pricesIncludeGST
                    )
                    itemResults.append((gstRate: gstRate, result: taxResult))
                    
                    finalTxItems[i].hsnCode = item.hsnCode
                    finalTxItems[i].gstRate = gstRate
                    finalTxItems[i].taxableValue = taxResult.taxableValue
                    finalTxItems[i].cgstAmount = taxResult.cgst
                    finalTxItems[i].sgstAmount = taxResult.sgst
                    finalTxItems[i].igstAmount = taxResult.igst
                    finalTxItems[i].cessAmount = taxResult.cess
                }
            }
            
            if !itemResults.isEmpty {
                taxBreakup = GSTEngine.generateBreakup(itemResults: itemResults)
            }
        } else if let settings = try? AppDataModel.shared.dataModel.db.getSettings(),
                  settings.isGSTRegistered, settings.gstScheme == "composition" {
            isCompositionScheme = true
            sellerGSTIN = settings.gstNumber
            sellerState = settings.businessState
        }
        
        return BillingDetails(
            customerName: name,
            items: finalTxItems,
            discount: discountAmount,
            adjustment: adjustmentAmount,
            descriptionText: nil,
            invoiceDate: Date(),
            invoiceNumber: generatedInvoiceNumber,
            transactionType: .sale,
            isCreditSale: isCreditEnabled,
            sellerGSTIN: sellerGSTIN,
            sellerState: sellerState,
            buyerGSTIN: buyerGSTIN,
            buyerState: IndianStates.stateByCode(buyerStateCode ?? "")?.name,
            placeOfSupply: placeOfSupply,
            isInterState: isInterState,
            isCompositionScheme: isCompositionScheme,
            taxBreakup: taxBreakup
        )
    }
    
}

extension SalesEntryTableViewController {
    
    @objc private func itemEditingDidEnd(_ sender: UITextField) {
        tableView.reloadSections(
            IndexSet(integer: SalesSection.summary.rawValue),
            with: .none
        )
    }

    @objc private func discountChanged(_ sender: UITextField) {
        discountAmount = Double(sender.text ?? "") ?? 0
        let indexPath = IndexPath(row: 3, section: SalesSection.summary.rawValue)
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    @objc private func adjustmentChanged(_ sender: UITextField) {
        adjustmentAmount = Double(sender.text ?? "") ?? 0
        let indexPath = IndexPath(row: 3, section: SalesSection.summary.rawValue)
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    @objc private func creditToggleChanged(_ sender: UISwitch) {
        isCreditEnabled = sender.isOn
    }

    @objc private func itemNameChanged(_ sender: UITextField) {
        let index = sender.tag
        guard index >= 0 && index < transactionItems.count else { return }
        let old = transactionItems[index]
        let updated = TransactionItem(
            id: old.id,
            transactionID: old.transactionID,
            itemID: old.itemID,
            itemName: sender.text ?? "",
            unit: old.unit,
            quantity: old.quantity,
            sellingPricePerUnit: old.sellingPricePerUnit,
            costPricePerUnit: old.costPricePerUnit,
            createdDate: old.createdDate
        )
        transactionItems[index] = updated
        syncInventoryMatchForItem(at: index)
        if sender.isFirstResponder {
            activeNameField = sender
            updateSuggestions(for: sender.text ?? "")
        }
        // Removed reloadRows call here per instructions
    }
    
    @objc private func itemPriceChanged(_ sender: UITextField) {
        let index = sender.tag
        guard index >= 0 && index < transactionItems.count else { return }
        let old = transactionItems[index]
        let newPrice: Double? = Double(sender.text ?? "")
        let updated = TransactionItem(
            id: old.id,
            transactionID: old.transactionID,
            itemID: old.itemID,
            itemName: old.itemName,
            unit: old.unit,
            quantity: old.quantity,
            sellingPricePerUnit: newPrice,
            costPricePerUnit: old.costPricePerUnit,
            createdDate: old.createdDate
        )
        transactionItems[index] = updated
        
        tableView.reloadSections(
                IndexSet(integer: SalesSection.summary.rawValue),
                with: .none
        )
    }

    @objc private func itemQuantityStepped(_ sender: UIStepper) {
        let index = sender.tag
        guard index >= 0 && index < transactionItems.count else { return }

        let newQty = max(1, Int(sender.value))
        let old = transactionItems[index]

        let updated = TransactionItem(
            id: old.id,
            transactionID: old.transactionID,
            itemID: old.itemID,
            itemName: old.itemName,
            unit: old.unit,
            quantity: newQty,
            sellingPricePerUnit: old.sellingPricePerUnit,
            costPricePerUnit: old.costPricePerUnit,
            createdDate: old.createdDate
        )

        transactionItems[index] = updated

        if let cell = tableView.cellForRow(at: IndexPath(row: index, section: SalesSection.items.rawValue)) as? EditSalesItemTableViewCell {
            cell.quantityLabel.text = "\(newQty)"
        }

        tableView.reloadSections(
            IndexSet(integer: SalesSection.summary.rawValue),
            with: .none
        )
    }

    @objc private func deleteItemTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index >= 0 && index < transactionItems.count else { return }
        transactionItems.remove(at: index)

        tableView.reloadSections(
            IndexSet([
                SalesSection.items.rawValue,
                SalesSection.summary.rawValue
            ]),
            with: .automatic
        )
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        if tableView == suggestionsTableView {
            return 1
        }
        return SalesSection.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == suggestionsTableView {
            return currentSuggestions.count
        }
        switch SalesSection(rawValue: section)! {
        case .customer:
            let isGST = (try? AppDataModel.shared.dataModel.db.getSettings().isGSTRegistered) ?? false
            return isGST ? 3 : 1

        case .items:
            if transactionItems.isEmpty {
                return 1
            } else {
                return transactionItems.count + 1
            }
        case .summary:
            return 3

        case .transactionTypeSlider:
            return 1
        case .invoice:
            return 3
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == suggestionsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "InventorySuggestionCell", for: indexPath)
            let item = currentSuggestions[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.text = item.name
            content.textProperties.font = .systemFont(ofSize: 13, weight: .regular)
            content.textProperties.numberOfLines = 1
            cell.contentConfiguration = content
            cell.accessoryType = .none
            return cell
        }
        
        switch SalesSection(rawValue: indexPath.section)! {
        case .customer:
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "TwoLabelsTableViewCell", for: indexPath) as! TwoLabelsTableViewCell
                cell.titleLabel.text = "Customer Name"
                cell.titleLabel.textColor = .label
                cell.detailLabel.text = customerName ?? "Tap to select"
                cell.detailLabel.textColor = customerName != nil ? .label : .secondaryLabel
                cell.accessoryType = .disclosureIndicator
                return cell
            } else if indexPath.row == 1 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                cell.titleLabel.text = "    Buyer GSTIN"
                cell.titleLabel.font = .systemFont(ofSize: 17)
                cell.titleLabel.textColor = UIColor(named: "Onyx") ?? .label
                cell.textField.text = buyerGSTIN
                cell.textField.placeholder = "Enter GSTIN    "
                cell.textField.font = .systemFont(ofSize: 17)
                cell.textField.textColor = UIColor(named: "Onyx") ?? .label
                cell.textField.autocapitalizationType = .allCharacters
                cell.textField.addTarget(self, action: #selector(buyerGSTINChanged(_:)), for: .editingChanged)
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "TwoLabelsTableViewCell", for: indexPath) as! TwoLabelsTableViewCell
                cell.titleLabel.text = "Place of Supply"
                cell.titleLabel.textColor = UIColor(named: "Onyx") ?? .label
                let stateName = IndianStates.stateByCode(buyerStateCode ?? "")?.name
                cell.detailLabel.text = stateName ?? "Auto"
                cell.detailLabel.textColor = stateName != nil ? (UIColor(named: "Onyx") ?? .label) : .secondaryLabel
                cell.accessoryType = .disclosureIndicator
                return cell
            }
            
        case .items:
            if transactionItems.isEmpty || indexPath.row == transactionItems.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: "AddNewItemTableViewCell", for: indexPath) as! AddNewItemTableViewCell
                cell.onAddTapped = { [weak self] in
                    guard let self = self else { return }
                    self.addNewItemByEntryMode()
                }
                return cell
            }
            let item = transactionItems[indexPath.row]
            
            if !isEditingEnabled {
                let cell = tableView.dequeueReusableCell(withIdentifier: "SalesItemTableViewCell", for: indexPath) as! SalesItemTableViewCell
                cell.selectionStyle = .none
                cell.titleLabel.text = item.itemName
                cell.detailLabel.text = String(format: "%d × %.2f", item.quantity, item.sellingPricePerUnit ?? 0.0)
                cell.priceLabel.text = String(format: "₹ %.2f", item.totalRevenue)
                
                return cell
                }
            else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "EditSalesItemTableViewCell", for: indexPath) as! EditSalesItemTableViewCell
                cell.selectionStyle = .none
                cell.nameLabel.text = item.itemName
                cell.unitLabel.text = "\(item.unit)"
                cell.priceLabel.text = item.sellingPricePerUnit != nil ?
                        String(format: "%.2f", item.sellingPricePerUnit!) : nil
                cell.stepper.value = Double(item.quantity)
                cell.quantityLabel.text = "\(Int(cell.stepper.value))"

                cell.nameLabel.tag = indexPath.row
                cell.unitLabel.tag = indexPath.row
                cell.priceLabel.tag = indexPath.row
                cell.stepper.tag = indexPath.row
                cell.deleteButton.tag = indexPath.row
                
                cell.nameLabel.addTarget(self, action: #selector(clearTextField(_:)), for: .editingDidBegin)
                cell.nameLabel.addTarget(self, action: #selector(itemNameEditingDidBegin(_:)), for: .editingDidBegin)
                cell.nameLabel.addTarget(self, action: #selector(itemNameChanged(_:)), for: .editingChanged)
                cell.nameLabel.addTarget(self, action: #selector(itemNameEditingDidEnd(_:)), for: .editingDidEnd)
                cell.nameLabel.addTarget(self, action: #selector(itemEditingDidEnd(_:)), for: .editingDidEnd)
                cell.deleteButton.addTarget(self, action: #selector(deleteItemTapped(_:)), for: .touchUpInside)
                cell.unitLabel.addTarget(self, action: #selector(clearTextField(_:)), for: .editingDidBegin)
                cell.unitLabel.addTarget(self, action: #selector(itemUnitChanged(_:)), for: .editingChanged)
                cell.priceLabel.addTarget(self, action: #selector(clearTextField(_:)), for: .editingDidBegin)
                cell.priceLabel.addTarget(self, action: #selector(itemPriceChanged(_:)), for: .editingChanged)
                cell.priceLabel.addTarget(self, action: #selector(itemEditingDidEnd(_:)), for: .editingDidEnd)
                cell.stepper.addTarget(self, action: #selector(itemQuantityStepped(_:)), for: .valueChanged)
                
                cell.priceLabel.keyboardType = .decimalPad
                cell.nameLabel.borderStyle = .roundedRect
                cell.unitLabel.borderStyle = .roundedRect
                cell.priceLabel.borderStyle = .roundedRect
                
                return cell
            }
            
        case .summary:
            switch indexPath.row {
            case 0:
                let cell: UITableViewCell
                if let dequeued = tableView.dequeueReusableCell(withIdentifier: "rightDetail") {
                    cell = dequeued
                } else {
                    cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
                }
                cell.selectionStyle = .default
                cell.textLabel?.text = "Subtotal"
                cell.textLabel?.font = .preferredFont(forTextStyle: .body)
                cell.detailTextLabel?.font = .preferredFont(forTextStyle: .body)
                cell.detailTextLabel?.text = String(format: "₹ %.2f", subTotal)
                return cell

            case 1:
                if isEditingEnabled {
                    let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                    cell.selectionStyle = .none
                    cell.titleLabel.text = "Discount"
                    cell.textField.keyboardType = .decimalPad
                    cell.textField.text = discountAmount > 0 ? String(format: "%.2f", discountAmount) : ""
                    cell.textField.placeholder = "0.00"
                    cell.textField.addTarget(self, action: #selector(clearTextField(_:)), for: .editingDidBegin)
                    cell.textField.addTarget(self, action: #selector(discountChanged(_:)), for: .editingChanged)
                    cell.textField.addTarget(self, action: #selector(discountChanged(_:)), for: .editingDidEnd)
                    return cell
                }
                else {
                    let cell: UITableViewCell
                    if let dequeued = tableView.dequeueReusableCell(withIdentifier: "rightDetail") {
                        cell = dequeued
                    } else {
                        cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
                    }
                    cell.textLabel?.text = "Discount"
                    cell.detailTextLabel?.text = String(format: "₹ %.2f", discountAmount)
                    cell.textLabel?.font = .preferredFont(forTextStyle: .body)
                    cell.detailTextLabel?.font = .preferredFont(forTextStyle: .body)
                    cell.selectionStyle = .none
                    return cell
                }

            case 2:
                let cell: UITableViewCell
                if let dequeued = tableView.dequeueReusableCell(withIdentifier: "rightDetail") {
                    cell = dequeued
                } else {
                    cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
                }
                cell.textLabel?.text = "Total(INR)"
                cell.textLabel?.font = .systemFont(ofSize: 17, weight: .bold)
                cell.detailTextLabel?.font = .systemFont(ofSize: 17, weight: .bold)
                cell.detailTextLabel?.text = String(format: "₹ %.2f", grandTotal)
                cell.selectionStyle = .none
                return cell
            default:
                return UITableViewCell()
            }

        case .transactionTypeSlider:
            let identifier = "creditToggleCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
            cell.selectionStyle = .none
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }

            let titleLabel = UILabel()
            titleLabel.text = "Credit"
            titleLabel.font = .preferredFont(forTextStyle: .body)

            let subtitleLabel = UILabel()
            subtitleLabel.text = "Enable when the customer will pay later."
            subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
            subtitleLabel.textColor = .secondaryLabel

            let labelStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
            labelStack.axis = .vertical
            labelStack.spacing = 2

            let toggle = UISwitch()
            toggle.isOn = isCreditEnabled
            toggle.addTarget(self, action: #selector(creditToggleChanged(_:)), for: .valueChanged)

            let stack = UIStackView(arrangedSubviews: [labelStack, UIView(), toggle])
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = 12

            cell.contentView.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
                stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16)
            ])

            return cell

        case .invoice:
            let cell: UITableViewCell
            if let dequeued = tableView.dequeueReusableCell(withIdentifier: "rightDetail") {
                cell = dequeued
            } else {
                cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
            }
            cell.textLabel?.text = "Invoice Date"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.detailTextLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.detailTextLabel?.text = String(format: "₹ %.2f", grandTotal)
            cell.selectionStyle = .none
            
            if indexPath.row == 0 || indexPath.row == 1 {
                cell.textLabel?.text = indexPath.row == 0 ? "Invoice Date" : "Invoice Number"
                if indexPath.row == 0 {
                    let df = DateFormatter()
                    df.dateStyle = .medium
                    df.timeStyle = .none
                    cell.detailTextLabel?.text = df.string(from: Date())
                } else {
                    cell.detailTextLabel?.text = generatedInvoiceNumber
                }
                
            return cell
            }
            else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextViewTableViewCell", for: indexPath) as! TextViewTableViewCell
                return cell
            }
            
            
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if tableView == suggestionsTableView {
            return nil
        }
        return SalesSection(rawValue: section)?.title
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = .systemBackground
        cell.layer.cornerRadius = 12
        cell.layer.masksToBounds = true
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == suggestionsTableView {
            let item = currentSuggestions[indexPath.row]
            guard let field = activeNameField else { return }
            let index = field.tag
            guard index >= 0 && index < transactionItems.count else { return }

            let old = transactionItems[index]
            let updated = TransactionItem(
                id: old.id,
                transactionID: old.transactionID,
                itemID: item.id,
                itemName: item.name,
                unit: item.unit,
                quantity: old.quantity,
                sellingPricePerUnit: item.defaultSellingPrice,
                costPricePerUnit: item.defaultCostPrice,
                createdDate: old.createdDate
            )
            transactionItems[index] = updated
            field.text = item.name
            suggestionsTableView.isHidden = true
            suggestionsTableView.removeFromSuperview()
            field.resignFirstResponder()
            tableView.deselectRow(at: indexPath, animated: true)
            self.tableView.reloadSections(IndexSet([SalesSection.items.rawValue, SalesSection.summary.rawValue]), with: .none)
            return
        }

        if SalesSection(rawValue: indexPath.section) == .customer {
            if indexPath.row == 0 {
                performSegue(withIdentifier: "selectCustomer", sender: nil)
            } else if indexPath.row == 2 {
                tableView.deselectRow(at: indexPath, animated: true)
                promptForState()
            }
        }
        
        if SalesSection(rawValue: indexPath.section) == .items {
            if transactionItems.isEmpty || indexPath.row == transactionItems.count {
                addNewItemByEntryMode()
            }
        }
    }
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            suggestionsTableView.isHidden = true
            suggestionsTableView.removeFromSuperview()
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard SalesSection(rawValue: section) == .items else { return nil }

        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = "Item Details"
        titleLabel.textColor = .gray
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)

        let button = UIButton(type: .system)
        button.setTitle(isEditingEnabled ? "Done" : "Edit", for: .normal)
        button.addTarget(self, action: #selector(toggleEditing), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, UIView(), button])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8

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

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if tableView == suggestionsTableView {
            return 0.01
        }
        guard SalesSection(rawValue: section) == .items else { return UITableView.automaticDimension }
        return 44
    }

    @objc private func toggleEditing() {
        if let text = customerNameField.text, !text.isEmpty {
            customerName = text
        }
        isEditingEnabled.toggle()
    }
    
    @objc private func itemUnitChanged(_ sender: UITextField) {
        let index = sender.tag
        guard index >= 0 && index < transactionItems.count else { return }
        let old = transactionItems[index]
        let newUnit = sender.text ?? old.unit
        
        var newPrice = old.sellingPricePerUnit
        if let price = old.sellingPricePerUnit, price > 0 {
            if let converted = UnitConversionService.shared.convertPrice(from: old.unit, to: newUnit, price: price) {
                newPrice = converted
            }
        }
        
        let updated = TransactionItem(
            id: old.id,
            transactionID: old.transactionID,
            itemID: old.itemID,
            itemName: old.itemName,
            unit: newUnit,
            quantity: old.quantity,
            sellingPricePerUnit: newPrice,
            costPricePerUnit: old.costPricePerUnit,
            createdDate: old.createdDate
        )
        transactionItems[index] = updated
        
        tableView.reloadSections(
            IndexSet([SalesSection.items.rawValue, SalesSection.summary.rawValue]),
            with: .none
        )
    }

    @objc private func clearTextField(_ sender: UITextField) {
        sender.selectAll(nil)
    }

    @objc private func itemNameEditingDidBegin(_ sender: UITextField) {
        activeNameField = sender
        updateSuggestions(for: sender.text ?? "")
    }

    @objc private func itemNameEditingDidEnd(_ sender: UITextField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.suggestionsTableView.isHidden = true
            self?.suggestionsTableView.removeFromSuperview()
        }
    }
    
    @objc private func customerNameChanged(_ sender: UITextField) {
        customerName = sender.text
    }
    
    @objc private func buyerGSTINChanged(_ sender: UITextField) {
        let text = sender.text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        buyerGSTIN = text.isEmpty ? nil : text
        
        // Auto-fill state if valid GSTIN
        if let gstin = buyerGSTIN, gstin.count >= 2, let state = IndianStates.stateFromGSTIN(gstin) {
            if buyerStateCode != state.code {
                buyerStateCode = state.code
                UIView.performWithoutAnimation {
                    self.tableView.reloadRows(at: [IndexPath(row: 2, section: SalesSection.customer.rawValue)], with: .none)
                }
            }
        }
    }
    
    private func promptForState() {
        let alert = UIAlertController(title: "Place of Supply", message: "Select the state where the sale is happening.", preferredStyle: .actionSheet)
        
        for stateName in IndianStates.sortedNames {
            alert.addAction(UIAlertAction(title: stateName, style: .default, handler: { _ in
                if let state = IndianStates.stateByName(stateName) {
                    self.buyerStateCode = state.code
                    self.tableView.reloadRows(at: [IndexPath(row: 2, section: SalesSection.customer.rawValue)], with: .automatic)
                }
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            if let cell = tableView.cellForRow(at: IndexPath(row: 2, section: SalesSection.customer.rawValue)) {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            } else {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            }
        }
        
        present(alert, animated: true)
    }
}
extension SalesEntryTableViewController: CustomerSelectionDelegate {
    func didSelectCustomer(name: String) {
        customerName = name
        customerNameField.text = name
        tableView.reloadSections(IndexSet(integer: SalesSection.customer.rawValue), with: .none)
    }
}

extension SalesEntryTableViewController: ItemInformationDelegate {

    func itemInformation(
        _ controller: ItemInformationTableViewController,
        item: Item,
        quantity: Int,
        sellingPrice: Double
    ) {

        let transactionItem = TransactionItem(
            id: UUID(),
            transactionID: transactionID,
            itemID: item.id,
            itemName: item.name,
            unit: item.unit,
            quantity: quantity,
            sellingPricePerUnit: sellingPrice,
            costPricePerUnit: nil, // filled later via FIFO
            createdDate: Date()
        )

        transactionItems.append(transactionItem)

        tableView.reloadSections(
            IndexSet([
                SalesSection.items.rawValue,
                SalesSection.summary.rawValue
            ]),
            with: .automatic
        )
        
    }
    func incompleteItemEntered(_ controller: ItemInformationTableViewController, item: IncompleteSaleItem
    ) {
        let placeholderTransactionItem = TransactionItem(
            id: item.transactionItemID,
            transactionID: item.transactionID,
            itemID: UUID(), // Temporary placeholder; real item will be created when completed
            itemName: item.itemName,
            unit: item.unit ?? "-",
            quantity: item.quantity,
            sellingPricePerUnit: item.sellingPricePerUnit,
            costPricePerUnit: nil,
            createdDate: item.createdAt
        )
        transactionItems.append(placeholderTransactionItem)

        tableView.reloadSections(
            IndexSet([
                SalesSection.items.rawValue,
                SalesSection.summary.rawValue
            ]),
            with: .automatic
        )
    }
}

extension SalesEntryTableViewController: saveDelegate{
    func save(isSaved: Bool) {
        billSaved = true
        if  billSaved{
            navigationController?.popViewController(animated: true)
            // or dismiss(animated: true)
        }
    }
   
}
