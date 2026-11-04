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
    var customerPhone: String?
    var notes: String?
    var transactionItems: [TransactionItem] = []
    var discountAmount: Double = 0
    var adjustmentAmount: Double = 0
    var isCreditEnabled = false
    

    var buyerGSTIN: String?
    var buyerStateCode: String?
    

    private let discountLabel = UILabel()
    private var discountTextField = UITextField()
    
    private let adjustmentLabel = UILabel()
    private var adjustmentTextField = UITextField()
    
    private var descriptionTextView: UITextView?

    private let editButton = UIButton(type: .system)
    

    var generatedInvoiceNumber: String = {
        AppDataModel.shared.dataModel.generateInvoiceNumber()
    }()
    
    /// The lines that carry an item name. Empty rows that were added with
    /// "Add new item" and never filled in are not part of the sale.
    var billableItems: [TransactionItem] {
        transactionItems.filter {
            !$0.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    var subTotal: Double {
        Money.round2(billableItems.reduce(0) { $0 + $1.totalRevenue })
    }
    var grandTotal: Double {
        Money.round2(subTotal - discountAmount + adjustmentAmount)
    }
    private var isEditingEnabled = true
    var customerNameField = UITextField()
    var inventoryCache: [Item] = []
    private var currentSuggestions: [Item] = []
    private let suggestionsContainerView = UIView()
    private let suggestionsTableView = UITableView(frame: .zero, style: .plain)
    private weak var activeNameField: UITextField?
    private weak var activeUnitField: UITextField?
    private var isSuggestingUnits = false
    private var currentUnitSuggestions: [String] = []
    
    /// Holds scan/voice result passed before viewDidLoad; consumed in viewDidLoad.
    var pendingResult: ParsedResult?
    var entryMode: EntryMode = .manual
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.rowHeight = UITableView.automaticDimension
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTableTap(_:)))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)

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
        tableView.register(InlineDiscountCell.self, forCellReuseIdentifier: InlineDiscountCell.reuseIdentifier)
        
        if inventoryCache.isEmpty {
            inventoryCache = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        }

        setupSuggestionsTableView()
        

        if let result = pendingResult {
            pendingResult = nil
            // entryMode is already set by the caller before pushing this VC
            appendItems(from: result)
        } else if entryMode == .manual && transactionItems.isEmpty {
            transactionItems.append(TransactionItem(id: UUID(), transactionID: transactionID, itemID: UUID(), itemName: "", unit: "pcs", quantity: 1.0, sellingPricePerUnit: nil, costPricePerUnit: 0.0, createdDate: Date()))
        }
        
        setupNavigationButtons()
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

    private func setupNavigationButtons() {
        navigationItem.title = "Add Sales"

        // Clean back button matching the rest of the app
        navigationItem.hidesBackButton = true
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            style: .plain,
            target: self,
            action: #selector(backButtonTapped)
        )
        backButton.tintColor = UIColor(named: "Onyx") ?? .label
        navigationItem.leftBarButtonItem = backButton

        // Save button tinted in app theme green
        let saveButton = UIBarButtonItem(
            title: "Save",
            style: .done,
            target: self,
            action: #selector(saveButtonTapped(_:))
        )
        saveButton.tintColor = UIColor(named: "Lime Moss") ?? .systemGreen
        navigationItem.rightBarButtonItem = saveButton

        navigationController?.interactivePopGestureRecognizer?.addTarget(self, action: #selector(handleSwipeGesture))
    }

    @objc private func handleSwipeGesture(gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            if !transactionItems.isEmpty && !billSaved {
                gesture.isEnabled = false
                backButtonTapped()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    gesture.isEnabled = true
                }
            }
        }
    }

    @objc private func backButtonTapped() {
        if !transactionItems.isEmpty && !billSaved {
            let alert = UIAlertController(title: "Unsaved Changes", message: "You have an ongoing sale. Going back will erase this sale. Are you sure?", preferredStyle: .alert)
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
        suggestionsTableView.rowHeight = 64
        suggestionsTableView.dataSource = self
        suggestionsTableView.delegate = self
        suggestionsTableView.register(SuggestionTableViewCell.self, forCellReuseIdentifier: SuggestionTableViewCell.reuseIdentifier)
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

    private func updateSuggestions(for query: String) {
        if inventoryCache.isEmpty {
            inventoryCache = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        }
        guard !inventoryCache.isEmpty else {
            dismissSuggestions()
            return
        }

        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches: [Item]
        if normalized.isEmpty {
            matches = inventoryCache
        } else {
            let filtered = InventoryMatcher.shared.getSuggestions(for: normalized, against: inventoryCache)
            matches = filtered.isEmpty ? inventoryCache.filter { $0.name.localizedCaseInsensitiveContains(normalized) } : filtered
        }

        guard !matches.isEmpty, let field = activeNameField else {
            dismissSuggestions()
            return
        }
        currentSuggestions = matches
        isSuggestingUnits = false

        let rowHeight = suggestionRowHeight(showsSubtitle: true)
        suggestionsTableView.rowHeight = rowHeight
        let maxRows = max(1, min(4, Int((view.bounds.height * 0.45) / rowHeight)))
        let visibleRows = min(currentSuggestions.count, maxRows)
        let desiredHeight = CGFloat(visibleRows) * rowHeight
        presentSuggestionsDropdown(below: field, desiredHeight: desiredHeight)
    }

    private func suggestionRowHeight(showsSubtitle: Bool) -> CGFloat {
        let titleHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        let subtitleHeight = UIFont.preferredFont(forTextStyle: .subheadline).lineHeight
        let contentHeight = titleHeight + (showsSubtitle ? subtitleHeight + 2 : 0)
        return max(44, ceil(contentHeight + 20))
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

    /// Matches the typed name against the inventory. Returns `true` when the
    /// selling price of the line changed, so the caller can refresh the totals.
    @discardableResult
    private func syncInventoryMatchForItem(at index: Int) -> Bool {
        guard index >= 0 && index < transactionItems.count else { return false }
        let old = transactionItems[index]
        let typedName = old.itemName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !typedName.isEmpty else { return false }
        guard let matched = inventoryCache.first(where: { $0.name.caseInsensitiveCompare(typedName) == .orderedSame }) else { return false }

        let resolvedPrice = ((old.sellingPricePerUnit ?? 0) > 0) ? old.sellingPricePerUnit : matched.defaultSellingPrice
        let priceChanged = (old.sellingPricePerUnit ?? 0) != (resolvedPrice ?? 0)
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
        return priceChanged
    }



    
    private func addNewItemByEntryMode() {
        dismissSuggestions()
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
            let scanVC = SalesScanCameraViewController.instantiate(mode: .sale)
            scanVC.onSaleResult = { [weak self] result in
                guard let self = self else { return }
                self.appendItems(from: result)
            }
            scanVC.modalPresentationStyle = .fullScreen
            present(scanVC, animated: true)
        case .manual:
            // End editing *before* reloading. If a text field is still the first
            // responder, reloading the table tears its cell down in the middle of
            // the update, and UIKit raises NSInternalInconsistencyException.
            view.endEditing(true)
            transactionItems.append(TransactionItem(id: UUID(), transactionID: transactionID, itemID: UUID(), itemName: "", unit: "pcs", quantity: 1.0, sellingPricePerUnit: nil, costPricePerUnit: 0.0, createdDate: Date()))
            tableView.reloadData()
        }
    }

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
            let matchedItem = product.itemID.flatMap { id in inventoryItems.first { $0.id == id } }
            

            var finalUnit = product.unit ?? matchedItem?.unit ?? "pcs"
            var finalSellingPrice: Double
            

            if let extracted = UnitConversionService.shared.extractQuantityAndUnit(from: finalUnit) {
                inputQty *= extracted.0
                finalUnit = extracted.1
            }
            

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
            
            var finalQty = inputQty == 0 ? 1.0 : inputQty

            // Apply conversions if matched
            if let inv = matchedItem {
                print("[VoiceSale] Item=\(inv.name), invUnit=\(inv.unit), reqUnit=\(finalUnit), reqQty=\(inputQty), invPrice=\(inv.defaultSellingPrice)")
                
                let normalizedReq = UnitConversionService.shared.normalizeUnit(finalUnit)
                let normalizedInv = UnitConversionService.shared.normalizeUnit(inv.unit)
                
                if normalizedReq != normalizedInv {
                    // Units differ — need prorated conversion
                    if let conversion = UnitConversionService.shared.calculateProrated(
                        requestedQty: inputQty,
                        requestedUnit: finalUnit,
                        inventoryPrice: inv.defaultSellingPrice,
                        inventoryUnit: inv.unit,
                        alternateUnitName: inv.alternateUnitName,
                        alternateUnitFactor: inv.alternateUnitFactor
                    ) {
                        finalQty = conversion.quantity
                        finalUnit = conversion.unit
                        
                      
                        finalSellingPrice = voicePrice ?? conversion.proratedPrice
                        print("[VoiceSale] ✓ Converted: qty=\(finalQty), unit=\(finalUnit), price=\(finalSellingPrice)")
                    } else {
                        finalSellingPrice = voicePrice ?? inv.defaultSellingPrice
                        finalUnit = inv.unit
                        print("[VoiceSale] ✗ Incompatible units, using defaults: price=\(finalSellingPrice), unit=\(finalUnit)")
                    }
                } else {
                    // Same unit — no conversion needed, use inventory price as default
                    finalSellingPrice = voicePrice ?? inv.defaultSellingPrice
                    finalUnit = inv.unit
                    print("[VoiceSale] ✗ Same unit, using price=\(finalSellingPrice), unit=\(finalUnit)")
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
                            finalQty = 1
                        } else if let newQty = Double(newQtyString) {
                            finalQty = newQty
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
                quantity: finalQty,
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

        view.endEditing(true)
        tableView.reloadData()
        processNextFuzzyMatch()
    }
    
    // Explicit confirmation UI loop
    private func processNextFuzzyMatch() {
        guard !pendingFuzzyMatches.isEmpty else {
            view.endEditing(true)
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

    @IBAction func saveButtonTapped(_ sender: Any) {
        // Price validation: each billable item must have a valid price > 0
        for item in billableItems {
            if (item.sellingPricePerUnit ?? 0) <= 0 {
                let itemName = item.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
                let alert = UIAlertController(
                    title: "Price Required",
                    message: "Please enter a valid price for \(itemName.isEmpty ? "item" : itemName).",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
        }

        // Credit validation: customer name is required for credit sales
        if isCreditEnabled {
            let name = (customerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                let alert = UIAlertController(
                    title: "Customer Required",
                    message: "Please select a customer for credit sales.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Select Customer", style: .default) { _ in
                    let customerIndexPath = IndexPath(row: 0, section: SalesSection.customer.rawValue)
                    self.tableView.scrollToRow(at: customerIndexPath, at: .top, animated: true)
                    self.performSegue(withIdentifier: "selectCustomer", sender: nil)
                })
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                present(alert, animated: true)
                return
            }
            if UPIWhatsAppShare.indianMobileDigits(customerPhone) == nil {
                let match = CreditStore.shared.getAllCustomers().first {
                    $0.name.caseInsensitiveCompare(name) == .orderedSame
                }
                customerPhone = match?.phone
            }
            if UPIWhatsAppShare.indianMobileDigits(customerPhone) == nil {
                let alert = UIAlertController(
                    title: "Mobile required",
                    message: "Credit needs a 10-digit number so you can send the UPI QR on WhatsApp.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Add number", style: .default) { _ in
                    self.performSegue(withIdentifier: "selectCustomer", sender: nil)
                })
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                present(alert, animated: true)
                return
            }
            let settings = try? AppDataModel.shared.dataModel.db.getSettings()
            if !UPIWhatsAppShare.canCollect(with: settings) {
                let alert = UIAlertController(
                    title: "Add your UPI QR",
                    message: "Save your PhonePe, Paytm, or GPay UPI ID or QR in Account → UPI collection. There is no payment gateway fee.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
        }
        if let settings = try? AppDataModel.shared.dataModel.db.getSettings(),
           settings.isGSTRegistered, settings.gstScheme != "composition" {
            let buyerCode = GSTEngine.buyerStateCode(
                explicit: buyerStateCode,
                gstin: buyerGSTIN,
                shopStateCode: nil
            )
            if GSTEngine.isInterStateSupply(
                sellerStateCode: settings.businessStateCode,
                buyerStateCode: buyerCode
            ) == nil {
                let alert = UIAlertController(
                    title: "Place of supply required",
                    message: "GST invoices need a place of supply. Unknown place is not treated as the shop state.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
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
            // A short bill does not need the bigger detent.
            let allowsExpansion = details.items.count > 2
            if let nav = segue.destination as? UINavigationController {
                billVC = nav.topViewController as? BillTableViewController
                configureBillSheet(nav, allowsExpansion: allowsExpansion)
            } else {
                billVC = segue.destination as? BillTableViewController
                if let billVC {
                    configureBillSheet(billVC, allowsExpansion: allowsExpansion)
                }
            }
            billVC?.receiveBilling(details: details)
                billVC?.delegate = self
        }
        if segue.identifier == "selectCustomer",
           let dest = segue.destination as? CustomerSelectionViewController {
            dest.delegate = self
        }
    }
    
    private func makeBillingDetails() -> BillingDetails {

        let name = customerNameField.text?.isEmpty == false ? customerNameField.text! : (customerName ?? "")
        
        // Compute tax breakup if GST is registered
        var taxBreakup: GSTBreakup? = nil
        var sellerGSTIN: String? = nil
        var sellerState: String? = nil
        var placeOfSupply: String? = nil
        var isInterState = false
        var isCompositionScheme = false
        
        // Lines without a name are empty rows that were added with "Add new
        // item" and never filled in. They are left out of the bill so no empty
        // item ends up on the invoice or in the stock list.
        var finalTxItems = billableItems
        
        if let settings = try? AppDataModel.shared.dataModel.db.getSettings(),
           settings.isGSTRegistered, settings.gstScheme != "composition" {
            sellerGSTIN = settings.gstNumber
            sellerState = settings.businessState
            
            let buyerCode = GSTEngine.buyerStateCode(
                explicit: buyerStateCode,
                gstin: buyerGSTIN,
                shopStateCode: nil
            )
            if let supplyFlag = GSTEngine.isInterStateSupply(
                sellerStateCode: settings.businessStateCode,
                buyerStateCode: buyerCode
            ) {
            isInterState = supplyFlag
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
            }
        } else if let settings = try? AppDataModel.shared.dataModel.db.getSettings(),
                  settings.isGSTRegistered, settings.gstScheme == "composition" {
            isCompositionScheme = true
            sellerGSTIN = settings.gstNumber
            sellerState = settings.businessState
        }
        
        return BillingDetails(
            customerName: name,
            customerPhone: customerPhone,
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
    
    @objc private func discountChanged(_ sender: UITextField) {
        discountAmount = Double(sender.text ?? "") ?? 0
        // The summary section has 3 rows (Subtotal / Discount / Total); row 3
        // does not exist and reloading it raises NSInternalInconsistencyException.
        let indexPath = IndexPath(row: 2, section: SalesSection.summary.rawValue)
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    @objc private func adjustmentChanged(_ sender: UITextField) {
        adjustmentAmount = Double(sender.text ?? "") ?? 0
        let indexPath = IndexPath(row: 2, section: SalesSection.summary.rawValue)
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
        let priceChanged = syncInventoryMatchForItem(at: index)
        if sender.isFirstResponder {
            activeNameField = sender
            updateSuggestions(for: sender.text ?? "")
        }
        // The totals are refreshed here (and not on editingDidEnd) because
        // editingDidEnd also fires while a cell is torn down inside a table
        // update - reloading the table from there crashes the app.
        if priceChanged {
            tableView.reloadSections(
                IndexSet(integer: SalesSection.summary.rawValue),
                with: .none
            )
        }
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

    @objc private func itemQuantityChanged(_ sender: UITextField) {
        let index = sender.tag
        guard index >= 0 && index < transactionItems.count else { return }

        let text = sender.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let newQty = Double(text) ?? 0.0
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

        tableView.reloadSections(
            IndexSet(integer: SalesSection.summary.rawValue),
            with: .none
        )
    }

    @objc private func itemQuantityEditingDidEnd(_ sender: UITextField) {
        let index = sender.tag
        guard index >= 0 && index < transactionItems.count else { return }

        let text = sender.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsedQty = Double(text) ?? 0.0
        let finalQty = parsedQty > 0 ? parsedQty : 1.0

        let old = transactionItems[index]
        let updated = TransactionItem(
            id: old.id,
            transactionID: old.transactionID,
            itemID: old.itemID,
            itemName: old.itemName,
            unit: old.unit,
            quantity: finalQty,
            sellingPricePerUnit: old.sellingPricePerUnit,
            costPricePerUnit: old.costPricePerUnit,
            createdDate: old.createdDate
        )
        transactionItems[index] = updated
        sender.text = finalQty.cleanString

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
            return isSuggestingUnits ? currentUnitSuggestions.count : currentSuggestions.count
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
            return 2
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == suggestionsTableView {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SuggestionTableViewCell.reuseIdentifier,
                for: indexPath
            ) as! SuggestionTableViewCell

            if isSuggestingUnits {
                guard indexPath.row < currentUnitSuggestions.count else { return cell }
                cell.configure(title: currentUnitSuggestions[indexPath.row], subtitle: nil)
            } else {
                guard indexPath.row < currentSuggestions.count else { return cell }
                let item = currentSuggestions[indexPath.row]

                var details: [String] = []
                if item.defaultSellingPrice > 0 {
                    details.append(String(format: "₹%.2f", item.defaultSellingPrice))
                }
                if !item.unit.isEmpty {
                    details.append(item.unit)
                }
                cell.configure(
                    title: item.name,
                    subtitle: details.isEmpty ? nil : details.joined(separator: " / ")
                )
            }
            return cell
        }
        
        switch SalesSection(rawValue: indexPath.section)! {
        case .customer:
            if indexPath.row == 0 {
                let identifier = "customerNameCell"
                let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .value1, reuseIdentifier: identifier)
                var config = UIListContentConfiguration.valueCell()
                let personConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
                config.image = UIImage(systemName: "person", withConfiguration: personConfig)
                config.imageProperties.tintColor = .label
                config.text = "Customer Name"
                config.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
                config.textProperties.color = .label
                config.secondaryText = customerName ?? "Tap to select"
                config.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .body)
                config.secondaryTextProperties.color = customerName != nil ? .label : .secondaryLabel
                cell.contentConfiguration = config
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
                return cell
            } else if indexPath.row == 1 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                cell.titleLabel.text = "Buyer GSTIN"
                cell.titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
                cell.titleLabel.textColor = UIColor(named: "Onyx") ?? .label
                cell.textField.text = buyerGSTIN
                cell.textField.placeholder = "Enter GSTIN"
                cell.textField.font = UIFont.preferredFont(forTextStyle: .body)
                cell.textField.textColor = UIColor(named: "Onyx") ?? .label
                cell.textField.autocapitalizationType = .allCharacters
                cell.textField.removeTarget(self, action: nil, for: .allEvents)
                cell.textField.addTarget(self, action: #selector(buyerGSTINChanged(_:)), for: .editingChanged)
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "TwoLabelsTableViewCell", for: indexPath) as! TwoLabelsTableViewCell
                cell.titleLabel.text = "Place of Supply"
                cell.titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
                cell.titleLabel.textColor = UIColor(named: "Onyx") ?? .label
                let stateName = IndianStates.stateByCode(buyerStateCode ?? "")?.name
                cell.detailLabel.text = stateName ?? "Auto"
                cell.detailLabel.font = UIFont.preferredFont(forTextStyle: .body)
                cell.detailLabel.textColor = stateName != nil ? (UIColor(named: "Onyx") ?? .label) : .secondaryLabel
                cell.accessoryType = .disclosureIndicator
                return cell
            }
            
        case .items:
            if transactionItems.isEmpty || indexPath.row == transactionItems.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: "AddNewItemTableViewCell", for: indexPath) as! AddNewItemTableViewCell
                cell.selectionStyle = .none
                cell.onAddTapped = { [weak self] in
                    guard let self = self else { return }
                    self.addNewItemByEntryMode()
                }
                return cell
            }
            guard indexPath.row < transactionItems.count else { return UITableViewCell() }
            let item = transactionItems[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "EditSalesItemTableViewCell", for: indexPath) as! EditSalesItemTableViewCell
            cell.selectionStyle = .none
            cell.nameLabel.text = item.itemName
            cell.unitLabel.text = "\(item.unit)"
            if let price = item.sellingPricePerUnit, price > 0 {
                cell.priceLabel.text = String(format: "%.2f", price)
            } else {
                cell.priceLabel.text = nil
            }
            cell.priceLabel.placeholder = "Price (₹)"
            cell.quantityLabel.text = item.quantity.cleanString

            cell.nameLabel.tag = indexPath.row
            cell.unitLabel.tag = indexPath.row
            cell.priceLabel.tag = indexPath.row
            cell.quantityLabel.tag = indexPath.row
            cell.deleteButton.tag = indexPath.row

            // Clear prior targets before adding
            cell.nameLabel.removeTarget(self, action: nil, for: .allEvents)
            cell.unitLabel.removeTarget(self, action: nil, for: .allEvents)
            cell.priceLabel.removeTarget(self, action: nil, for: .allEvents)
            cell.quantityLabel.removeTarget(self, action: nil, for: .allEvents)
            cell.deleteButton.removeTarget(self, action: nil, for: .allEvents)

            cell.nameLabel.addTarget(self, action: #selector(clearTextField(_:)), for: .editingDidBegin)
            cell.nameLabel.addTarget(self, action: #selector(itemNameEditingDidBegin(_:)), for: .editingDidBegin)
            cell.nameLabel.addTarget(self, action: #selector(itemNameChanged(_:)), for: .editingChanged)
            cell.nameLabel.addTarget(self, action: #selector(itemNameEditingDidEnd(_:)), for: .editingDidEnd)
            cell.deleteButton.addTarget(self, action: #selector(deleteItemTapped(_:)), for: .touchUpInside)
            cell.unitLabel.addTarget(self, action: #selector(itemUnitEditingDidBegin(_:)), for: .editingDidBegin)
            cell.unitLabel.addTarget(self, action: #selector(itemUnitChanged(_:)), for: .editingChanged)
            cell.unitLabel.addTarget(self, action: #selector(itemUnitEditingDidEnd(_:)), for: .editingDidEnd)
            cell.priceLabel.addTarget(self, action: #selector(clearTextField(_:)), for: .editingDidBegin)
            cell.priceLabel.addTarget(self, action: #selector(itemPriceChanged(_:)), for: .editingChanged)
            cell.quantityLabel.addTarget(self, action: #selector(clearTextField(_:)), for: .editingDidBegin)
            cell.quantityLabel.addTarget(self, action: #selector(itemQuantityChanged(_:)), for: .editingChanged)
            cell.quantityLabel.addTarget(self, action: #selector(itemQuantityEditingDidEnd(_:)), for: .editingDidEnd)

            cell.priceLabel.keyboardType = .decimalPad
            cell.quantityLabel.keyboardType = .decimalPad

            return cell

        case .summary:
            switch indexPath.row {
            case 0:
                let identifier = "summarySubtotalCell"
                let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .value1, reuseIdentifier: identifier)
                var config = UIListContentConfiguration.valueCell()
                config.text = "Subtotal"
                config.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
                config.textProperties.color = .label
                config.secondaryText = String(format: "₹ %.2f", subTotal)
                config.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .body)
                config.secondaryTextProperties.color = .label
                cell.contentConfiguration = config
                cell.selectionStyle = .none
                return cell

            case 1:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: InlineDiscountCell.reuseIdentifier,
                    for: indexPath
                ) as! InlineDiscountCell
                cell.textField.text = discountAmount > 0 ? String(format: "%.2f", discountAmount) : ""
                cell.onTextChanged = { [weak self] text in
                    guard let self = self else { return }
                    self.discountAmount = Double(text) ?? 0
                    UIView.performWithoutAnimation {
                        self.tableView.reloadRows(
                            at: [IndexPath(row: 2, section: SalesSection.summary.rawValue)],
                            with: .none
                        )
                    }
                }
                return cell

            case 2:
                let identifier = "summaryTotalCell"
                let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .value1, reuseIdentifier: identifier)
                var config = UIListContentConfiguration.valueCell()
                config.text = "Total (INR)"
                config.textProperties.font = .systemFont(ofSize: 17, weight: .bold)
                config.textProperties.color = .label
                config.secondaryText = String(format: "₹ %.2f", grandTotal)
                config.secondaryTextProperties.font = .systemFont(ofSize: 17, weight: .bold)
                config.secondaryTextProperties.color = .label
                cell.contentConfiguration = config
                cell.selectionStyle = .none
                return cell
            default:
                return UITableViewCell()
            }

        case .transactionTypeSlider:
            let identifier = "creditToggleCardCell"
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
            titleLabel.text = "Credit"
            titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
            titleLabel.textColor = .label

            let subtitleLabel = UILabel()
            subtitleLabel.text = "Enable when the customer will pay later."
            subtitleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
            subtitleLabel.textColor = .secondaryLabel
            subtitleLabel.numberOfLines = 0
            subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

            let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
            textStack.axis = .vertical
            textStack.spacing = 2
            textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let toggle = UISwitch()
            toggle.isOn = isCreditEnabled
            toggle.onTintColor = lime
            toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
            toggle.addTarget(self, action: #selector(creditToggleChanged(_:)), for: .valueChanged)

            let mainStack = UIStackView(arrangedSubviews: [iconView, textStack, toggle])
            mainStack.translatesAutoresizingMaskIntoConstraints = false
            mainStack.axis = .horizontal
            mainStack.alignment = .center
            mainStack.spacing = 14

            cell.contentView.addSubview(mainStack)
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 28),
                iconView.heightAnchor.constraint(equalToConstant: 24),

                mainStack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                mainStack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                mainStack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                mainStack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
            ])

            return cell

        case .invoice:
            let identifier = indexPath.row == 0 ? "invoiceDateCell" : "invoiceNumberCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .value1, reuseIdentifier: identifier)

            var config = UIListContentConfiguration.valueCell()
            let symConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)

            if indexPath.row == 0 {
                config.image = UIImage(systemName: "calendar", withConfiguration: symConfig)
                config.imageProperties.tintColor = .label
                config.text = "Invoice Date"
                config.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
                config.textProperties.color = .label

                let df = DateFormatter()
                df.dateFormat = "d MMM yyyy"
                config.secondaryText = df.string(from: Date())
                config.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .body)
                config.secondaryTextProperties.color = .secondaryLabel

                cell.contentConfiguration = config
                cell.accessoryType = .none
                cell.selectionStyle = .none
            } else {
                config.image = UIImage(systemName: "number", withConfiguration: symConfig)
                config.imageProperties.tintColor = .label
                config.text = "Invoice Number"
                config.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
                config.textProperties.color = .label

                config.secondaryText = generatedInvoiceNumber
                config.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .body)
                config.secondaryTextProperties.color = .secondaryLabel

                cell.contentConfiguration = config
                cell.accessoryType = .none
                cell.selectionStyle = .none
            }
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if tableView == suggestionsTableView {
            cell.backgroundColor = .secondarySystemGroupedBackground
            return
        }

        if SalesSection(rawValue: indexPath.section) == .items {
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == suggestionsTableView {
            if isSuggestingUnits {
                guard indexPath.row < currentUnitSuggestions.count else { return }
                let unit = currentUnitSuggestions[indexPath.row]
                guard let field = activeUnitField else { return }
                
                let index = field.tag
                guard index >= 0 && index < transactionItems.count else { return }
                let old = transactionItems[index]
                let updated = TransactionItem(
                    id: old.id,
                    transactionID: old.transactionID,
                    itemID: old.itemID,
                    itemName: old.itemName,
                    unit: unit,
                    quantity: old.quantity,
                    sellingPricePerUnit: old.sellingPricePerUnit,
                    costPricePerUnit: old.costPricePerUnit,
                    createdDate: old.createdDate
                )
                transactionItems[index] = updated
                field.text = unit
                dismissSuggestions()
                field.resignFirstResponder()
                self.tableView.reloadSections(IndexSet([SalesSection.items.rawValue, SalesSection.summary.rawValue]), with: .none)
                return
            } else {
                guard indexPath.row < currentSuggestions.count else { return }
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
                dismissSuggestions()
                field.resignFirstResponder()
                tableView.deselectRow(at: indexPath, animated: true)
                self.tableView.reloadSections(IndexSet([SalesSection.items.rawValue, SalesSection.summary.rawValue]), with: .none)
                return
            }
        }

        if SalesSection(rawValue: indexPath.section) == .customer {
            if indexPath.row == 0 {
                performSegue(withIdentifier: "selectCustomer", sender: nil)
            } else if indexPath.row == 2 {
                tableView.deselectRow(at: indexPath, animated: true)
                promptForState()
            }
        } else if SalesSection(rawValue: indexPath.section) == .summary {
            if indexPath.row == 1 {
                tableView.deselectRow(at: indexPath, animated: true)
                if let cell = tableView.cellForRow(at: indexPath) as? InlineDiscountCell {
                    cell.textField.becomeFirstResponder()
                }
            }
        }
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            dismissSuggestions()
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if tableView == suggestionsTableView {
            return nil
        }
        guard SalesSection(rawValue: section) != .items else { return nil }
        return SalesSection(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if tableView == suggestionsTableView { return nil }
        guard SalesSection(rawValue: section) == .items else { return nil }

        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = "Item Details"
        titleLabel.textColor = .secondaryLabel
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)

        container.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
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
        if activeUnitField == sender {
            updateUnitSuggestions(for: sender.text ?? "")
        }
        
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
    }

    @objc private func clearTextField(_ sender: UITextField) {
        sender.selectAll(nil)
    }

    @objc private func itemNameEditingDidBegin(_ sender: UITextField) {
        isSuggestingUnits = false
        activeUnitField = nil
        activeNameField = sender
        updateSuggestions(for: sender.text ?? "")
    }

    @objc private func itemNameEditingDidEnd(_ sender: UITextField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            if self?.activeNameField == sender {
                self?.dismissSuggestions()
            }
        }
    }
    
    @objc private func itemUnitEditingDidBegin(_ sender: UITextField) {
        sender.selectAll(nil)
        isSuggestingUnits = true
        activeNameField = nil
        activeUnitField = sender
        updateUnitSuggestions(for: "")
    }

    @objc private func itemUnitEditingDidEnd(_ sender: UITextField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            if self?.activeUnitField == sender {
                self?.dismissSuggestions()
            }
        }
    }
    
    private func updateUnitSuggestions(for query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allUnits = UnitConversionService.standardUnits
        
        if normalized.isEmpty {
            currentUnitSuggestions = allUnits
        } else {
            let filtered = allUnits.filter { $0.lowercased().hasPrefix(normalized) }
            currentUnitSuggestions = filtered.isEmpty ? allUnits : filtered
        }
        
        guard !currentUnitSuggestions.isEmpty, let field = activeUnitField else {
            dismissSuggestions()
            return
        }
        isSuggestingUnits = true

        let rowHeight = suggestionRowHeight(showsSubtitle: false)
        suggestionsTableView.rowHeight = rowHeight
        let maxRows = max(1, min(5, Int((view.bounds.height * 0.45) / rowHeight)))
        let visibleRows = min(currentUnitSuggestions.count, maxRows)
        let desiredHeight = CGFloat(visibleRows) * rowHeight
        presentSuggestionsDropdown(below: field, desiredHeight: desiredHeight)
    }
    
    @objc private func customerNameChanged(_ sender: UITextField) {
        customerName = sender.text
    }
    
    @objc private func buyerGSTINChanged(_ sender: UITextField) {
        let text = sender.text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        
        // Write uppercased text back so it displays correctly
        if sender.text != text {
            let cursorPos = sender.selectedTextRange
            sender.text = text
            sender.selectedTextRange = cursorPos
        }
        
        buyerGSTIN = text.isEmpty ? nil : text
        sender.textColor = UIColor(named: "Onyx") ?? .label
        
        // Auto-fill state if valid GSTIN
        if let gstin = buyerGSTIN, gstin.count >= 2, let state = IndianStates.stateFromGSTIN(gstin) {
            if buyerStateCode != state.code {
                buyerStateCode = state.code
                // The customer section only has a "Place of Supply" row when the
                // shop is GST registered - reloading row 2 of a one row section
                // raises NSInternalInconsistencyException.
                let stateRow = IndexPath(row: 2, section: SalesSection.customer.rawValue)
                guard tableView.numberOfRows(inSection: SalesSection.customer.rawValue) > stateRow.row else { return }
                UIView.performWithoutAnimation {
                    self.tableView.reloadRows(at: [stateRow], with: .none)
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
    func didSelectCustomer(name: String, phone: String?) {
        customerName = name
        customerPhone = phone
        customerNameField.text = name
        
        let all = CreditStore.shared.getAllCustomers()
        if let customer = all.first(where: { $0.name == name }),
           let gstin = customer.gstin, !gstin.isEmpty {
            buyerGSTIN = gstin
            if gstin.count >= 2, let state = IndianStates.stateFromGSTIN(gstin) {
                buyerStateCode = state.code
            }
        } else {
            // Do not keep the GSTIN/state of a previously selected customer.
            buyerGSTIN = nil
            buyerStateCode = nil
        }
        
        tableView.reloadSections(IndexSet(integer: SalesSection.customer.rawValue), with: .none)
    }
}

extension SalesEntryTableViewController: ItemInformationDelegate {

    func itemInformation(
        _ controller: ItemInformationTableViewController,
        item: Item,
        quantity: Double,
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
        if isSaved {
            billSaved = true
            navigationController?.popViewController(animated: true)
        } else {
            // The sale was not saved (e.g. not enough stock). Go back to the
            // sales list, but ask first so the sale is not dropped silently.
            backButtonTapped()
        }
    }
   
}

/// Suggestion row for the item/unit dropdown. The labels are laid out with
/// explicit padding so the text is never clipped by the cell bounds.
private final class SuggestionTableViewCell: UITableViewCell {
    static let reuseIdentifier = "InventorySuggestionCell"

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        selectionStyle = .default
        backgroundColor = .secondarySystemGroupedBackground
        contentView.backgroundColor = .clear

        titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail

        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    func configure(title: String, subtitle: String?) {
        titleLabel.text = title
        let hasSubtitle = !(subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        subtitleLabel.text = hasSubtitle ? subtitle : nil
        subtitleLabel.isHidden = !hasSubtitle
    }
}

/// Summary row with an always-visible discount field, styled like the item
/// cells so it is obvious that the value can be edited.
private final class InlineDiscountCell: UITableViewCell {
    static let reuseIdentifier = "inlineDiscountCell"

    let titleLabel = UILabel()
    let textField = UITextField()
    var onTextChanged: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        selectionStyle = .none
        backgroundColor = .systemBackground

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Discount"
        titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        titleLabel.textColor = .label

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.textColor = .label
        textField.textAlignment = .right
        textField.keyboardType = .decimalPad
        textField.placeholder = "₹ 0.00"
        textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)

        contentView.addSubview(titleLabel)
        contentView.addSubview(textField)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textField.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            textField.widthAnchor.constraint(equalToConstant: 140)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTextChanged = nil
    }

    @objc private func editingChanged() {
        onTextChanged?(textField.text ?? "")
    }
}
