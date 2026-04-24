import UIKit

protocol saveDelegate: AnyObject {
    func save(isSaved: Bool)
}

class BillTableViewController: UITableViewController, UIDocumentPickerDelegate {
    weak var delegate: saveDelegate?
    
    enum Row {
        case header
        case customer
        case itemsHeader
        case item(Int)
        case tax(type: String, amount: Double)
        case total
    }
    var rows: [Row] = []

    private let sheetView = UIView()
    var details: BillingDetails?
    private let bottomBar = UIView()
    var isReadOnly = false


    private enum Section: Int, CaseIterable {
        case headerCard, customer, itemsHeader, itemsList, total
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.isScrollEnabled = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.separatorStyle = .none
        tableView.register(UINib(nibName: "BillLabelTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "BillLabelTableViewCell")
        tableView.register(UINib(nibName: "TwoLabelsTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "TwoLabelsTableViewCell")
        tableView.register(UINib(nibName: "BillItemTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "BillItemTableViewCell")
        
        tableView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16)
        tableView.cellLayoutMarginsFollowReadableWidth = false
        
        setupBottomBar()

        // Ensure rows are built and table is refreshed if data was received early
        if details != nil {
            buildRows()
            tableView.reloadData()
        }
    }
    private func setupBottomBar() {
        bottomBar.backgroundColor = .clear
        bottomBar.layer.cornerRadius = 16
        bottomBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        view.addSubview(bottomBar)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: tableView.frameLayoutGuide.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: tableView.frameLayoutGuide.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 64)
        ])
        let printButton = makeActionButton(title: "Print", action: #selector(didTapPrint))
        let shareButton = makeActionButton(title: "Share", action: #selector(didTapShare))
        let saveButton  = makeActionButton(title: "Save", action: #selector(didTapSave))
        saveButton.isHidden = isReadOnly

        let stack = UIStackView(arrangedSubviews: [printButton, shareButton, saveButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        stack.alignment = .fill

        bottomBar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16)
        ])


        tableView.contentInset.bottom = 80
        tableView.verticalScrollIndicatorInsets.bottom = 80

    }
    
    private func makeActionButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        button.backgroundColor = .systemGray5
        button.layer.cornerRadius = 20
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    func receiveBilling(details: BillingDetails) {
        self.details = details
        buildRows()
        tableView.isScrollEnabled = details.items.count > 3
        if isViewLoaded {
            tableView.reloadData()
        }
    }

    private func buildRows() {
        guard let details else { return }

        rows = []
        rows.append(.header)
        rows.append(.customer)
        rows.append(.itemsHeader)

        for index in details.items.indices {
            rows.append(.item(index))
        }

        if let taxBreakup = details.taxBreakup {
            if taxBreakup.totalCGST > 0 { rows.append(.tax(type: "CGST", amount: taxBreakup.totalCGST)) }
            if taxBreakup.totalSGST > 0 { rows.append(.tax(type: "SGST", amount: taxBreakup.totalSGST)) }
            if taxBreakup.totalIGST > 0 { rows.append(.tax(type: "IGST", amount: taxBreakup.totalIGST)) }
            if taxBreakup.totalCess > 0 { rows.append(.tax(type: "CESS", amount: taxBreakup.totalCess)) }
        }

        rows.append(.total)
    }
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        
        let isFirst = indexPath.row == 0
        let isLast = indexPath.row == rows.count - 1
        
        // Use a tag to prevent duplicate bgViews on reuse
        let bgView: UIView
        if let existing = cell.viewWithTag(888) {
            bgView = existing
        } else {
            bgView = UIView()
            bgView.tag = 888
            bgView.translatesAutoresizingMaskIntoConstraints = false
            cell.insertSubview(bgView, at: 0)
            
            NSLayoutConstraint.activate([
                bgView.topAnchor.constraint(equalTo: cell.topAnchor),
                bgView.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
                bgView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16),
                bgView.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -16)
            ])
        }
        
        bgView.backgroundColor = UIColor(named: "Beige") ?? .systemGray5
        
        bgView.layer.cornerRadius = 16
        if isFirst && isLast {
            bgView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else if isFirst {
            bgView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        } else if isLast {
            bgView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else {
            bgView.layer.maskedCorners = []
        }
        
        
        let row = rows[indexPath.row]
        var addSeparator = false
        switch row {
        case .header, .customer, .itemsHeader, .item, .tax:
            addSeparator = true
        case .total:
            addSeparator = false
        }
        
        // Remove existing separator to avoid duplication on reuse
        cell.viewWithTag(999)?.removeFromSuperview()
        
        if addSeparator {
            let separator = UIView()
            separator.tag = 999
            separator.backgroundColor = UIColor.black.withAlphaComponent(0.12)
            separator.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(separator)
            NSLayoutConstraint.activate([
                separator.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 32),
                separator.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -32),
                separator.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
                separator.heightAnchor.constraint(equalToConstant: 0.5)
            ])
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {

        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let details else { return UITableViewCell() }

        switch rows[indexPath.row] {
            case .header:
                let cell = tableView.dequeueReusableCell(withIdentifier: "BillLabelTableViewCell", for: indexPath) as! BillLabelTableViewCell
                cell.selectionStyle = .none
                cell.titleLabel.text = "Invoice #\(details.invoiceNumber)"
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .short
                cell.dateLabel.text = f.string(from: details.invoiceDate)
                return cell
                
            case .customer:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TwoLabelsTableViewCell", for: indexPath) as! TwoLabelsTableViewCell
                cell.selectionStyle = .none
                let isPurchase = details.transactionType == .purchase
                cell.titleLabel.text = isPurchase ? "Supplier" : "Customer"
                cell.detailLabel?.text = details.customerName
                return cell
                
            case .itemsHeader:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TwoLabelsTableViewCell", for: indexPath) as! TwoLabelsTableViewCell
                cell.selectionStyle = .none
                cell.titleLabel.text = "Items"
                cell.detailLabel?.text = "\(details.items.count) items"
                return cell

            case .item(let index):
                let cell = tableView.dequeueReusableCell(withIdentifier: "BillItemTableViewCell", for: indexPath) as! BillItemTableViewCell
                cell.selectionStyle = .none
                let item = details.items[index]
                let isPurchase = details.transactionType == .purchase
                let rate = isPurchase ? (item.costPricePerUnit ?? 0) : (item.sellingPricePerUnit ?? 0)
                let totalPrice = Double(item.quantity) * rate
                
                cell.titleLabel.text = item.itemName
                cell.priceLabel.text = String(format: "₹ %.2f", totalPrice)
                cell.detailLabel.text = String(format: "₹ %d × %.2f", item.quantity, rate)
                return cell
                
            case .tax(let type, let amount):
                let cell = tableView.dequeueReusableCell(withIdentifier: "TwoLabelsTableViewCell", for: indexPath) as! TwoLabelsTableViewCell
                cell.selectionStyle = .none
                cell.titleLabel.text = type
                cell.detailLabel?.text = String(format: "₹ %.2f", amount)
                return cell
            case .total:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TwoLabelsTableViewCell", for: indexPath) as! TwoLabelsTableViewCell
                cell.selectionStyle = .none

                let isPurchase = details.transactionType == .purchase
                let subTotal = details.items.reduce(0.0) { $0 + (isPurchase ? $1.totalCost : $1.totalRevenue) }
                let grand = subTotal - details.discount + details.adjustment
                
                cell.titleLabel.text = "Total"
                cell.detailLabel?.text = String(format: "₹ %.2f", grand)
                cell.detailLabel?.font = .systemFont(ofSize:17, weight: .semibold)
                return cell
        }
    }
    
    @objc private func didTapPrint() {
        guard details != nil else { return }
        let pdfData = renderBillAsPDF()

        guard UIPrintInteractionController.isPrintingAvailable else {
            let alert = UIAlertController(title: "Printing Unavailable",
                                          message: "No AirPrint printers were found.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "Invoice #\(details!.invoiceNumber)"
        printInfo.outputType = .general
        printController.printInfo = printInfo
        printController.printingItem = pdfData
        printController.present(animated: true)
    }

    @objc private func didTapShare() {
        guard let details = details else { return }
        let pdfData = renderBillAsPDF()

        // Write to a temporary file so share extensions display a proper filename
        let fileName = "Invoice_\(details.invoiceNumber).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? pdfData.write(to: tempURL)

        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

        // iPad popover positioning
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 80, width: 0, height: 0)
            popover.permittedArrowDirections = .down
        }

        present(activityVC, animated: true)
    }
    @objc private func didTapSave() {
        guard let details = details else { return }

        // ── Read-only mode: export bill as PDF to Files ──
        if isReadOnly {
            let pdfData = renderBillAsPDF()
            let fileName = "Invoice_\(details.invoiceNumber).pdf"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? pdfData.write(to: tempURL)

            let picker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
            return
        }

        let dm = AppDataModel.shared.dataModel
        let db = dm.db

        // Resolve items BEFORE do/catch so saleItems is accessible in catch blocks
        var saleItems: [(itemID: UUID, quantity: Int, sellingPrice: Double)] = []

        do {
            // 1) Load all existing items for fast lookup by name (case-insensitive)
            let existingItems = try db.getAllItems()
            var nameToItem: [String: Item] = [:]
            for item in existingItems {
                nameToItem[item.name.lowercased()] = item
            }
            
            // 2) Resolve each bill line to a real Item.id, creating items when missing
            let now = Date()
            
            for txItem in details.items {
                let key = txItem.itemName.lowercased()
                let quantity = txItem.quantity
                let sellingPrice = txItem.sellingPricePerUnit ?? 0
                
                if let matched = nameToItem[key] {
                    saleItems.append((itemID: matched.id, quantity: quantity, sellingPrice: sellingPrice))
                } else {
                    let newItem = Item(
                        id: UUID(),
                        name: txItem.itemName,
                        unit: txItem.unit,
                        defaultCostPrice: 0,
                        defaultSellingPrice: sellingPrice,
                        defaultPriceUpdatedAt: now,
                        lowStockThreshold: 0,
                        currentStock: 0,
                        createdDate: now,
                        lastRestockDate: nil,
                        isActive: true
                    )
                    
                    try db.insertItem(newItem)
                    nameToItem[key] = newItem
                    saleItems.append((itemID: newItem.id, quantity: quantity, sellingPrice: sellingPrice))
                }
            }
            
            // 3) Persist the multi-item sale using resolved item IDs
            let stateCode = IndianStates.stateByName(details.buyerState ?? "")?.code
            _ = try dm.addMultiItemSale(
                items: saleItems,
                customerName: details.customerName.isEmpty ? nil : details.customerName,
                customerPhone: nil,
                discount: details.discount,
                adjustment: details.adjustment,
                invoiceNumber: details.invoiceNumber,
                buyerGSTIN: details.buyerGSTIN,
                buyerStateCode: stateCode
            )

            recordCreditSaleIfNeeded(for: details)
            
            // 4) Dismiss the bill sheet after saving
            dismiss(animated: true)
            navigationController?.popViewController(animated: true)
            delegate?.save(isSaved: true)
        }
        
        catch DataModelError.insufficientStock(let available, let requested) {
            // Still record the sale transaction (without stock deduction)
            // so it appears in transactions and analytics
            let stateCode = IndianStates.stateByName(details.buyerState ?? "")?.code
            do {
                _ = try dm.recordSaleWithoutStockCheck(
                    items: saleItems,
                    customerName: details.customerName.isEmpty ? nil : details.customerName,
                    customerPhone: nil,
                    discount: details.discount,
                    adjustment: details.adjustment,
                    invoiceNumber: details.invoiceNumber,
                    buyerGSTIN: details.buyerGSTIN,
                    buyerStateCode: stateCode
                )
                recordCreditSaleIfNeeded(for: details)
            } catch {
            }

            let alert = UIAlertController(
                title: "Insufficient Stock",
                message: "Sale recorded, but stock is insufficient.\nAvailable: \(available), Requested: \(requested)\n\nPlease go to Stock tab to purchase more inventory.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.dismiss(animated: true)
            })
            alert.addAction(UIAlertAction(title: "Go to Stock", style: .default) { [weak self] _ in
                self?.dismiss(animated: true) {
                    if let tabBarController = UIApplication.shared.keyWindow?.rootViewController as? UITabBarController {
                        tabBarController.selectedIndex = 2
                    }
                }
            })
            present(alert, animated: true)
        } catch {
            let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.dismiss(animated: true)
            })
            present(alert, animated: true)
        }
    }

    private func recordCreditSaleIfNeeded(for details: BillingDetails) {
        guard details.isCreditSale else { return }

        let totalAmount = details.items.reduce(0.0) { $0 + $1.totalRevenue } - details.discount + details.adjustment
        guard totalAmount > 0 else { return }

        let rawName = details.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = rawName.isEmpty ? "Customer" : rawName

        CreditStore.shared.addCreditSale(
            amount: totalAmount,
            customerName: resolvedName,
            note: "Credit sale \(details.invoiceNumber)"
        )
    }

    // MARK: - PDF Rendering

    private func renderBillAsPDF() -> Data {
        guard let details = details else { return Data() }

        let pageWidth: CGFloat = 595.0
        let pageHeight: CGFloat = 842.0
        let margin: CGFloat = 36.0
        let contentWidth = pageWidth - margin * 2
        let isGST = details.sellerGSTIN != nil && details.taxBreakup != nil
        let isComposition = details.isCompositionScheme

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            let titleFont = UIFont.systemFont(ofSize: 20, weight: .bold)
            let subtitleFont = UIFont.systemFont(ofSize: 10, weight: .regular)
            let headingFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
            let boldBody = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let smallFont = UIFont.systemFont(ofSize: 9, weight: .regular)
            let totalFont = UIFont.systemFont(ofSize: 14, weight: .bold)

            func drawText(_ text: String, font: UIFont, color: UIColor = .black, rect: CGRect, alignment: NSTextAlignment = .left) {
                let style = NSMutableParagraphStyle()
                style.alignment = alignment
                style.lineBreakMode = .byTruncatingTail
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
                (text as NSString).draw(in: rect, withAttributes: attrs)
            }

            func drawLine(at yPos: CGFloat, weight: CGFloat = 0.5) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: yPos))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: yPos))
                UIColor.darkGray.setStroke()
                path.lineWidth = weight
                path.stroke()
            }

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > pageHeight - margin { context.beginPage(); y = margin }
            }

            func drawRow(label: String, value: String, labelWidth: CGFloat = contentWidth * 0.75) {
                let valW = contentWidth - labelWidth
                drawText(label, font: bodyFont, rect: CGRect(x: margin, y: y, width: labelWidth, height: 14), alignment: .right)
                drawText(value, font: bodyFont, rect: CGRect(x: margin + labelWidth, y: y, width: valW, height: 14), alignment: .right)
                y += 16
            }

            // ═══════════════════════════════════════════
            // TITLE
            // ═══════════════════════════════════════════
            let isPurchase = details.transactionType == .purchase

            if isGST || isComposition {
                let title = isComposition ? "BILL OF SUPPLY" : "TAX INVOICE"
                drawText(title, font: titleFont, rect: CGRect(x: margin, y: y, width: contentWidth, height: 24), alignment: .center)
                y += 22
                if isComposition {
                    drawText("(Composition Scheme u/s 10 of CGST Act)", font: subtitleFont, color: .darkGray,
                             rect: CGRect(x: margin, y: y, width: contentWidth, height: 14), alignment: .center)
                    y += 14
                }
            } else {
                drawText("INVOICE", font: titleFont, rect: CGRect(x: margin, y: y, width: contentWidth, height: 24), alignment: .center)
                y += 24
            }

            y += 4
            drawLine(at: y, weight: 1.0); y += 10

            // ═══════════════════════════════════════════
            // SELLER + INVOICE INFO (side by side)
            // ═══════════════════════════════════════════
            let halfW = contentWidth * 0.5
            let leftX = margin
            let rightX = margin + halfW + 8
            let rhW = halfW - 8
            let blockTop = y

            // Left: Seller info
            let settings = try? AppDataModel.shared.dataModel.db.getSettings()
            let bizName = settings?.businessName ?? "My Business"
            drawText(bizName, font: headingFont, rect: CGRect(x: leftX, y: y, width: halfW, height: 14))
            y += 14
            if let addr = settings?.businessAddress, !addr.isEmpty {
                drawText(addr, font: smallFont, color: .darkGray, rect: CGRect(x: leftX, y: y, width: halfW, height: 12))
                y += 12
            }
            if let phone = settings?.businessPhone, !phone.isEmpty {
                drawText("Ph: \(phone)", font: smallFont, color: .darkGray, rect: CGRect(x: leftX, y: y, width: halfW, height: 12))
                y += 12
            }
            if let gstin = details.sellerGSTIN {
                drawText("GSTIN: \(gstin)", font: boldBody, rect: CGRect(x: leftX, y: y, width: halfW, height: 14))
                y += 14
            }
            if let state = details.sellerState {
                drawText("State: \(state)", font: smallFont, rect: CGRect(x: leftX, y: y, width: halfW, height: 12))
                y += 12
            }
            let leftBottom = y

            // Right: Invoice details
            var ry = blockTop
            drawText("Invoice #: \(details.invoiceNumber)", font: boldBody, rect: CGRect(x: rightX, y: ry, width: rhW, height: 14))
            ry += 14
            let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
            drawText("Date: \(df.string(from: details.invoiceDate))", font: bodyFont, rect: CGRect(x: rightX, y: ry, width: rhW, height: 14))
            ry += 14
            if let pos = details.placeOfSupply ?? details.buyerState {
                drawText("Place of Supply: \(pos)", font: bodyFont, rect: CGRect(x: rightX, y: ry, width: rhW, height: 14))
                ry += 14
            }
            if isGST {
                drawText("Reverse Charge: No", font: smallFont, rect: CGRect(x: rightX, y: ry, width: rhW, height: 12))
                ry += 12
            }

            y = max(leftBottom, ry) + 6
            drawLine(at: y); y += 8

            // ═══════════════════════════════════════════
            // BUYER INFO
            // ═══════════════════════════════════════════
            let partyLabel = isPurchase ? "Supplier" : "Buyer"
            drawText("\(partyLabel): \(details.customerName)", font: headingFont,
                     rect: CGRect(x: margin, y: y, width: contentWidth, height: 14))
            y += 14
            if let bGSTIN = details.buyerGSTIN, !bGSTIN.isEmpty {
                drawText("GSTIN: \(bGSTIN)", font: bodyFont, rect: CGRect(x: margin, y: y, width: contentWidth, height: 14))
                y += 14
            }
            y += 4
            drawLine(at: y); y += 6

            // ═══════════════════════════════════════════
            // ITEM TABLE
            // ═══════════════════════════════════════════
            if isGST {
                // GST table: # | Item | HSN | Qty | Rate | Taxable | Tax | Amount
                let cols: [(String, CGFloat, NSTextAlignment)] = [
                    ("#", 20, .center), ("Item", contentWidth * 0.25, .left), ("HSN", 52, .center),
                    ("Qty", 32, .center), ("Rate", 52, .right), ("Taxable", 60, .right),
                    ("GST%", 36, .center), ("Tax", 52, .right), ("Amount", 62, .right)
                ]
                // Adjust last column to fill remaining
                var cx = margin
                for (title, w, align) in cols {
                    drawText(title, font: headingFont, rect: CGRect(x: cx, y: y, width: w, height: 14), alignment: align)
                    cx += w + 2
                }
                y += 16; drawLine(at: y); y += 4

                for (idx, item) in details.items.enumerated() {
                    ensureSpace(18)
                    let rate = isPurchase ? (item.costPricePerUnit ?? 0) : (item.sellingPricePerUnit ?? 0)
                    let amount = Double(item.quantity) * rate
                    let taxable = item.taxableValue ?? amount
                    let hsn = item.hsnCode ?? "—"
                    let gstPct = item.gstRate != nil ? String(format: "%g%%", item.gstRate!) : "—"
                    let taxAmt = (item.cgstAmount ?? 0) + (item.sgstAmount ?? 0) + (item.igstAmount ?? 0) + (item.cessAmount ?? 0)

                    cx = margin
                    let vals: [(String, CGFloat, NSTextAlignment)] = [
                        ("\(idx+1)", 20, .center), (item.itemName, contentWidth * 0.25, .left), (hsn, 52, .center),
                        ("\(item.quantity)", 32, .center), (String(format: "₹%.2f", rate), 52, .right),
                        (String(format: "₹%.2f", taxable), 60, .right), (gstPct, 36, .center),
                        (String(format: "₹%.2f", taxAmt), 52, .right), (String(format: "₹%.2f", amount), 62, .right)
                    ]
                    for (val, w, align) in vals {
                        drawText(val, font: bodyFont, rect: CGRect(x: cx, y: y, width: w, height: 14), alignment: align)
                        cx += w + 2
                    }
                    y += 16
                }
            } else {
                // Simple table: Item | Qty | Rate | Amount
                drawText("Item", font: headingFont, rect: CGRect(x: margin, y: y, width: contentWidth * 0.5, height: 14))
                drawText("Qty", font: headingFont, rect: CGRect(x: margin + contentWidth * 0.5, y: y, width: contentWidth * 0.15, height: 14), alignment: .center)
                drawText("Rate", font: headingFont, rect: CGRect(x: margin + contentWidth * 0.65, y: y, width: contentWidth * 0.15, height: 14), alignment: .right)
                drawText("Amount", font: headingFont, rect: CGRect(x: margin + contentWidth * 0.8, y: y, width: contentWidth * 0.2, height: 14), alignment: .right)
                y += 16; drawLine(at: y); y += 4

                for item in details.items {
                    ensureSpace(18)
                    let rate = isPurchase ? (item.costPricePerUnit ?? 0) : (item.sellingPricePerUnit ?? 0)
                    let amount = Double(item.quantity) * rate
                    drawText(item.itemName, font: bodyFont, rect: CGRect(x: margin, y: y, width: contentWidth * 0.5, height: 14))
                    drawText("\(item.quantity)", font: bodyFont, rect: CGRect(x: margin + contentWidth * 0.5, y: y, width: contentWidth * 0.15, height: 14), alignment: .center)
                    drawText(String(format: "₹%.2f", rate), font: bodyFont, rect: CGRect(x: margin + contentWidth * 0.65, y: y, width: contentWidth * 0.15, height: 14), alignment: .right)
                    drawText(String(format: "₹%.2f", amount), font: bodyFont, rect: CGRect(x: margin + contentWidth * 0.8, y: y, width: contentWidth * 0.2, height: 14), alignment: .right)
                    y += 16
                }
            }

            y += 4; drawLine(at: y, weight: 1.0); y += 8

            // ═══════════════════════════════════════════
            // TOTALS
            let subTotal = details.items.reduce(0.0) { $0 + (isPurchase ? $1.totalCost : $1.totalRevenue) }

            if details.discount != 0 {
                drawRow(label: "Discount:", value: String(format: "- ₹%.2f", details.discount))
            }
            if details.adjustment != 0 {
                drawRow(label: "Adjustment:", value: String(format: "₹%.2f", details.adjustment))
            }

            // ═══════════════════════════════════════════
            // RATE-WISE TAX BREAKUP TABLE (GST only)
            // ═══════════════════════════════════════════
            if let taxBreakup = details.taxBreakup, !taxBreakup.rateWiseSummary.isEmpty {
                ensureSpace(60)
                y += 4
                drawText("Tax Breakup", font: headingFont, rect: CGRect(x: margin, y: y, width: contentWidth, height: 14))
                y += 16

                // Header
                let tCols: [CGFloat] = [60, 72, 60, 60, 60, 60, 60]
                let tHdrs = ["Rate", "Taxable", "CGST", "SGST", "IGST", "Cess", "Total Tax"]
                var tx = margin
                for (i, hdr) in tHdrs.enumerated() {
                    drawText(hdr, font: boldBody, rect: CGRect(x: tx, y: y, width: tCols[i], height: 14), alignment: i == 0 ? .left : .right)
                    tx += tCols[i] + 4
                }
                y += 14; drawLine(at: y); y += 4

                for entry in taxBreakup.rateWiseSummary {
                    ensureSpace(16)
                    tx = margin
                    let rowTax = entry.cgst + entry.sgst + entry.igst + entry.cess
                    let vals = [
                        String(format: "%g%%", entry.gstRate),
                        String(format: "₹%.2f", entry.taxableValue),
                        String(format: "₹%.2f", entry.cgst),
                        String(format: "₹%.2f", entry.sgst),
                        String(format: "₹%.2f", entry.igst),
                        String(format: "₹%.2f", entry.cess),
                        String(format: "₹%.2f", rowTax)
                    ]
                    for (i, val) in vals.enumerated() {
                        drawText(val, font: bodyFont, rect: CGRect(x: tx, y: y, width: tCols[i], height: 14), alignment: i == 0 ? .left : .right)
                        tx += tCols[i] + 4
                    }
                    y += 14
                }
                y += 4; drawLine(at: y); y += 8

                // Summary totals
                if taxBreakup.totalCGST > 0 { drawRow(label: "Total CGST:", value: String(format: "₹%.2f", taxBreakup.totalCGST)) }
                if taxBreakup.totalSGST > 0 { drawRow(label: "Total SGST:", value: String(format: "₹%.2f", taxBreakup.totalSGST)) }
                if taxBreakup.totalIGST > 0 { drawRow(label: "Total IGST:", value: String(format: "₹%.2f", taxBreakup.totalIGST)) }
                if taxBreakup.totalCess > 0 { drawRow(label: "Total Cess:", value: String(format: "₹%.2f", taxBreakup.totalCess)) }
            }

            // ═══════════════════════════════════════════
            // GRAND TOTAL
            // ═══════════════════════════════════════════
            ensureSpace(30)
            drawLine(at: y, weight: 1.0); y += 8
            let grandTotal = subTotal - details.discount + details.adjustment
            let roundedTotal = round(grandTotal)
            drawText("GRAND TOTAL", font: totalFont, rect: CGRect(x: margin, y: y, width: contentWidth * 0.7, height: 20), alignment: .right)
            drawText(String(format: "₹%.2f", roundedTotal), font: totalFont, rect: CGRect(x: margin + contentWidth * 0.7, y: y, width: contentWidth * 0.3, height: 20), alignment: .right)
            y += 24

            // Amount in words
            ensureSpace(20)
            let words = NumberToWords.convert(roundedTotal)
            drawText("Amount in words: \(words)", font: smallFont, color: .darkGray,
                     rect: CGRect(x: margin, y: y, width: contentWidth, height: 14))
            y += 20

            // ═══════════════════════════════════════════
            // FOOTER
            // ═══════════════════════════════════════════
            if isComposition {
                ensureSpace(30)
                drawLine(at: y); y += 8
                drawText("\"Composition taxable person, not eligible to collect tax on supplies\"",
                         font: smallFont, color: .darkGray,
                         rect: CGRect(x: margin, y: y, width: contentWidth, height: 14), alignment: .center)
                y += 16
            }

            ensureSpace(20)
            drawText("E. & O.E.  |  Generated by Ledgile", font: smallFont, color: .gray,
                     rect: CGRect(x: margin, y: y, width: contentWidth, height: 12), alignment: .center)
        }

        return data
    }
}
