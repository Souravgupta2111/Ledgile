// Live barcode scanner — continuous video stream with auto-detection,
// glassmorphism UI, scan-and-link item picker, and running bill.

import AVFoundation
import UIKit
import Vision

final class BarcodeScannerViewController: UIViewController {

    // MARK: - Callbacks
    var onSaleResult: ((ParsedResult) -> Void)?
    var onPurchaseResult: ((ParsedPurchaseResult) -> Void)?
    var mode: ScanMode = .sale

    // MARK: - Camera
     var captureSession: AVCaptureSession?
     var previewLayer: AVCaptureVideoPreviewLayer?
     let sessionQueue = DispatchQueue(label: "barcode.session")
     let processingQueue = DispatchQueue(label: "barcode.processing")

    // MARK: - Barcode Lookup
     var itemByBarcode: [String: Item] = [:]
     var allItems: [Item] = []

    // MARK: - Scanned Items Accumulation
     var scannedItems: [(item: Item, quantity: Int)] = []
     var seenBarcodes: Set<String> = []
     var lastScanTime: CFTimeInterval = 0
     let scanCooldown: CFTimeInterval = 1.5

    // MARK: - Item Picker State
     var isShowingPicker = false
     var pendingBarcode: String?
     var filteredItems: [Item] = []

    // MARK: - UI Elements
     let previewView = UIView()
     var toastContainer: UIVisualEffectView!
     let toastLabel = UILabel()
     let toastIcon = UILabel()
     var billPanel: UIVisualEffectView!
     let billTableView = UITableView(frame: .zero, style: .plain)
     let totalLabel = UILabel()
     let stopButton = UIButton(type: .system)
     let itemCountLabel = UILabel()
     var toastTimer: Timer?

    // Item picker overlay
     var pickerOverlay: UIView!
     var pickerBlur: UIVisualEffectView!
     var pickerContainer: UIVisualEffectView!
     var pickerSearchBar: UISearchBar!
     var pickerTableView: UITableView!
     var pickerTitleLabel: UILabel!
     var pickerBarcodeLabel: UILabel!
     var pickerCancelButton: UIButton!

    // Scan line animation
     var scanLineView: UIView!

    // MARK: - Lifecycle

    init(mode: ScanMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationController?.setNavigationBarHidden(true, animated: false)

        loadInventory()
        setupUI()
        setupItemPicker()
        checkCameraPermission()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
    }

    // MARK: - Inventory

     func loadInventory() {
        allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        rebuildBarcodeIndex()
        print("[BarcodeScanner] Loaded \(allItems.count) items, \(itemByBarcode.count) with barcodes")
    }

     func rebuildBarcodeIndex() {
        itemByBarcode = Dictionary(
            allItems.compactMap { item -> (String, Item)? in
                guard let code = item.barcode, !code.isEmpty else { return nil }
                return (code, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Glass UI Setup

     func setupUI() {
        // Camera preview
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        // Scan line animation
        scanLineView = UIView()
        scanLineView.backgroundColor = UIColor(named: "Lime Moss")!.withAlphaComponent(0.6)
        scanLineView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanLineView)

        // Close button (top-left glass pill)
        let closeBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        closeBlur.translatesAutoresizingMaskIntoConstraints = false
        closeBlur.layer.cornerRadius = 20
        closeBlur.clipsToBounds = true
        view.addSubview(closeBlur)

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        closeBlur.contentView.addSubview(closeBtn)

        // Title pill (top-center glass)
        let titleBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        titleBlur.translatesAutoresizingMaskIntoConstraints = false
        titleBlur.layer.cornerRadius = 18
        titleBlur.clipsToBounds = true
        view.addSubview(titleBlur)

        let titleLabel = UILabel()
        titleLabel.text = "  📷 Live Scan  "
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleBlur.contentView.addSubview(titleLabel)

        // Toast (center glass pill)
        toastContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        toastContainer.translatesAutoresizingMaskIntoConstraints = false
        toastContainer.layer.cornerRadius = 16
        toastContainer.clipsToBounds = true
        toastContainer.alpha = 0
        view.addSubview(toastContainer)

        toastIcon.translatesAutoresizingMaskIntoConstraints = false
        toastIcon.font = .systemFont(ofSize: 28)
        toastIcon.textAlignment = .center
        toastContainer.contentView.addSubview(toastIcon)

        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.textAlignment = .left
        toastLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        toastLabel.textColor = .white
        toastLabel.numberOfLines = 2
        toastContainer.contentView.addSubview(toastLabel)

        // Bill panel (bottom glass)
        billPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        billPanel.translatesAutoresizingMaskIntoConstraints = false
        billPanel.layer.cornerRadius = 24
        billPanel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        billPanel.clipsToBounds = true
        view.addSubview(billPanel)

        // Drag indicator
        let dragIndicator = UIView()
        dragIndicator.translatesAutoresizingMaskIntoConstraints = false
        dragIndicator.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        dragIndicator.layer.cornerRadius = 2.5
        billPanel.contentView.addSubview(dragIndicator)

        // Item count label
        itemCountLabel.translatesAutoresizingMaskIntoConstraints = false
        itemCountLabel.text = "Point camera at barcodes"
        itemCountLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        itemCountLabel.font = .systemFont(ofSize: 13, weight: .medium)
        itemCountLabel.textAlignment = .center
        billPanel.contentView.addSubview(itemCountLabel)

        // Bill table
        billTableView.translatesAutoresizingMaskIntoConstraints = false
        billTableView.backgroundColor = .clear
        billTableView.separatorColor = UIColor.white.withAlphaComponent(0.1)
        billTableView.dataSource = self
        billTableView.register(UITableViewCell.self, forCellReuseIdentifier: "BarcodeItemCell")
        billTableView.showsVerticalScrollIndicator = false
        billPanel.contentView.addSubview(billTableView)

        // Total label
        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        totalLabel.text = "₹0"
        totalLabel.textColor = .white
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        totalLabel.textAlignment = .center
        billPanel.contentView.addSubview(totalLabel)

        // Stop button (gradient green)
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.setTitle("Done", for: .normal)
        stopButton.setImage(UIImage(systemName: "stop.circle"), for: .normal)
        stopButton.tintColor = .white
        stopButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        stopButton.backgroundColor = UIColor(named: "Lime Moss")!
        stopButton.layer.cornerRadius = 25
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        billPanel.contentView.addSubview(stopButton)

        NSLayoutConstraint.activate([
            // Preview
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Scan line
            scanLineView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            scanLineView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            scanLineView.heightAnchor.constraint(equalToConstant: 2),
            scanLineView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -80),

            // Close button
            closeBlur.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeBlur.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeBlur.widthAnchor.constraint(equalToConstant: 40),
            closeBlur.heightAnchor.constraint(equalToConstant: 40),
            closeBtn.centerXAnchor.constraint(equalTo: closeBlur.centerXAnchor),
            closeBtn.centerYAnchor.constraint(equalTo: closeBlur.centerYAnchor),

            // Title pill
            titleBlur.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleBlur.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            titleBlur.heightAnchor.constraint(equalToConstant: 36),
            titleLabel.leadingAnchor.constraint(equalTo: titleBlur.contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: titleBlur.contentView.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: titleBlur.centerYAnchor),

            // Toast
            toastContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            toastContainer.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
            toastContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            toastIcon.leadingAnchor.constraint(equalTo: toastContainer.contentView.leadingAnchor, constant: 16),
            toastIcon.centerYAnchor.constraint(equalTo: toastContainer.centerYAnchor),
            toastIcon.widthAnchor.constraint(equalToConstant: 32),
            toastLabel.leadingAnchor.constraint(equalTo: toastIcon.trailingAnchor, constant: 8),
            toastLabel.trailingAnchor.constraint(equalTo: toastContainer.contentView.trailingAnchor, constant: -16),
            toastLabel.topAnchor.constraint(equalTo: toastContainer.contentView.topAnchor, constant: 12),
            toastLabel.bottomAnchor.constraint(equalTo: toastContainer.contentView.bottomAnchor, constant: -12),

            // Bill panel
            billPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            billPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            billPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Drag indicator
            dragIndicator.topAnchor.constraint(equalTo: billPanel.contentView.topAnchor, constant: 8),
            dragIndicator.centerXAnchor.constraint(equalTo: billPanel.centerXAnchor),
            dragIndicator.widthAnchor.constraint(equalToConstant: 36),
            dragIndicator.heightAnchor.constraint(equalToConstant: 5),

            // Item count
            itemCountLabel.topAnchor.constraint(equalTo: dragIndicator.bottomAnchor, constant: 10),
            itemCountLabel.leadingAnchor.constraint(equalTo: billPanel.contentView.leadingAnchor, constant: 16),
            itemCountLabel.trailingAnchor.constraint(equalTo: billPanel.contentView.trailingAnchor, constant: -16),

            // Bill table
            billTableView.topAnchor.constraint(equalTo: itemCountLabel.bottomAnchor, constant: 6),
            billTableView.leadingAnchor.constraint(equalTo: billPanel.contentView.leadingAnchor),
            billTableView.trailingAnchor.constraint(equalTo: billPanel.contentView.trailingAnchor),
            billTableView.heightAnchor.constraint(lessThanOrEqualToConstant: 140),

            // Total
            totalLabel.topAnchor.constraint(equalTo: billTableView.bottomAnchor, constant: 6),
            totalLabel.leadingAnchor.constraint(equalTo: billPanel.contentView.leadingAnchor, constant: 16),
            totalLabel.trailingAnchor.constraint(equalTo: billPanel.contentView.trailingAnchor, constant: -16),

            // Stop button
            stopButton.topAnchor.constraint(equalTo: totalLabel.bottomAnchor, constant: 10),
            stopButton.centerXAnchor.constraint(equalTo: billPanel.centerXAnchor),
            stopButton.heightAnchor.constraint(equalToConstant: 50),
            stopButton.leadingAnchor.constraint(equalTo: billPanel.contentView.leadingAnchor, constant: 24),
            stopButton.trailingAnchor.constraint(equalTo: billPanel.contentView.trailingAnchor, constant: -24),
            stopButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        startScanLineAnimation()
    }

    // MARK: - Scan Line Animation

     func startScanLineAnimation() {
        scanLineView.alpha = 0.8
        UIView.animate(withDuration: 1.8, delay: 0, options: [.repeat, .autoreverse, .curveEaseInOut]) {
            self.scanLineView.transform = CGAffineTransform(translationX: 0, y: 60)
            self.scanLineView.alpha = 0.3
        }
    }

    // MARK: - Item Picker Setup (Glass)

     func setupItemPicker() {
        // Full-screen overlay
        pickerOverlay = UIView()
        pickerOverlay.translatesAutoresizingMaskIntoConstraints = false
        pickerOverlay.alpha = 0
        pickerOverlay.isHidden = true
        view.addSubview(pickerOverlay)

        // Background blur
        pickerBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        pickerBlur.translatesAutoresizingMaskIntoConstraints = false
        pickerOverlay.addSubview(pickerBlur)

        // Glass card container
        pickerContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        pickerContainer.translatesAutoresizingMaskIntoConstraints = false
        pickerContainer.layer.cornerRadius = 24
        pickerContainer.clipsToBounds = true
        pickerContainer.layer.borderWidth = 0.5
        pickerContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        pickerOverlay.addSubview(pickerContainer)

        // Title
        pickerTitleLabel = UILabel()
        pickerTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        pickerTitleLabel.text = "Link Barcode to Item"
        pickerTitleLabel.textColor = .white
        pickerTitleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        pickerTitleLabel.textAlignment = .center
        pickerContainer.contentView.addSubview(pickerTitleLabel)

        // Barcode display
        pickerBarcodeLabel = UILabel()
        pickerBarcodeLabel.translatesAutoresizingMaskIntoConstraints = false
        pickerBarcodeLabel.textColor = UIColor(named: "Lime Moss")!
        pickerBarcodeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        pickerBarcodeLabel.textAlignment = .center
        pickerContainer.contentView.addSubview(pickerBarcodeLabel)

        // Search bar
        pickerSearchBar = UISearchBar()
        pickerSearchBar.translatesAutoresizingMaskIntoConstraints = false
        pickerSearchBar.placeholder = "Search items..."
        pickerSearchBar.searchBarStyle = .minimal
        pickerSearchBar.barTintColor = .clear
        pickerSearchBar.backgroundImage = UIImage()
        pickerSearchBar.tintColor = UIColor(named: "Lime Moss")!
        pickerSearchBar.searchTextField.textColor = .white
        pickerSearchBar.searchTextField.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        pickerSearchBar.delegate = self
        pickerContainer.contentView.addSubview(pickerSearchBar)

        // Item list
        pickerTableView = UITableView(frame: .zero, style: .plain)
        pickerTableView.translatesAutoresizingMaskIntoConstraints = false
        pickerTableView.backgroundColor = .clear
        pickerTableView.separatorColor = UIColor.white.withAlphaComponent(0.1)
        pickerTableView.dataSource = self
        pickerTableView.delegate = self
        pickerTableView.register(UITableViewCell.self, forCellReuseIdentifier: "PickerItemCell")
        pickerTableView.showsVerticalScrollIndicator = false
        pickerContainer.contentView.addSubview(pickerTableView)

        // Cancel button
        pickerCancelButton = UIButton(type: .system)
        pickerCancelButton.translatesAutoresizingMaskIntoConstraints = false
        pickerCancelButton.setTitle("Skip", for: .normal)
        pickerCancelButton.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .normal)
        pickerCancelButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        pickerCancelButton.addTarget(self, action: #selector(pickerCancelTapped), for: .touchUpInside)
        pickerContainer.contentView.addSubview(pickerCancelButton)

        NSLayoutConstraint.activate([
            pickerOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            pickerOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pickerOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pickerOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            pickerBlur.topAnchor.constraint(equalTo: pickerOverlay.topAnchor),
            pickerBlur.leadingAnchor.constraint(equalTo: pickerOverlay.leadingAnchor),
            pickerBlur.trailingAnchor.constraint(equalTo: pickerOverlay.trailingAnchor),
            pickerBlur.bottomAnchor.constraint(equalTo: pickerOverlay.bottomAnchor),

            pickerContainer.centerXAnchor.constraint(equalTo: pickerOverlay.centerXAnchor),
            pickerContainer.centerYAnchor.constraint(equalTo: pickerOverlay.centerYAnchor),
            pickerContainer.leadingAnchor.constraint(equalTo: pickerOverlay.leadingAnchor, constant: 20),
            pickerContainer.trailingAnchor.constraint(equalTo: pickerOverlay.trailingAnchor, constant: -20),
            pickerContainer.heightAnchor.constraint(lessThanOrEqualTo: pickerOverlay.heightAnchor, multiplier: 0.65),

            pickerTitleLabel.topAnchor.constraint(equalTo: pickerContainer.contentView.topAnchor, constant: 20),
            pickerTitleLabel.leadingAnchor.constraint(equalTo: pickerContainer.contentView.leadingAnchor, constant: 16),
            pickerTitleLabel.trailingAnchor.constraint(equalTo: pickerContainer.contentView.trailingAnchor, constant: -16),

            pickerBarcodeLabel.topAnchor.constraint(equalTo: pickerTitleLabel.bottomAnchor, constant: 6),
            pickerBarcodeLabel.leadingAnchor.constraint(equalTo: pickerContainer.contentView.leadingAnchor, constant: 16),
            pickerBarcodeLabel.trailingAnchor.constraint(equalTo: pickerContainer.contentView.trailingAnchor, constant: -16),

            pickerSearchBar.topAnchor.constraint(equalTo: pickerBarcodeLabel.bottomAnchor, constant: 10),
            pickerSearchBar.leadingAnchor.constraint(equalTo: pickerContainer.contentView.leadingAnchor, constant: 8),
            pickerSearchBar.trailingAnchor.constraint(equalTo: pickerContainer.contentView.trailingAnchor, constant: -8),

            pickerTableView.topAnchor.constraint(equalTo: pickerSearchBar.bottomAnchor, constant: 4),
            pickerTableView.leadingAnchor.constraint(equalTo: pickerContainer.contentView.leadingAnchor),
            pickerTableView.trailingAnchor.constraint(equalTo: pickerContainer.contentView.trailingAnchor),

            pickerCancelButton.topAnchor.constraint(equalTo: pickerTableView.bottomAnchor, constant: 8),
            pickerCancelButton.centerXAnchor.constraint(equalTo: pickerContainer.centerXAnchor),
            pickerCancelButton.heightAnchor.constraint(equalToConstant: 40),
            pickerCancelButton.bottomAnchor.constraint(equalTo: pickerContainer.contentView.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Camera

     func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupCamera() }
                    else { self?.showToast("Camera access denied", icon: "🚫", isError: true) }
                }
            }
        default:
            showToast("Enable camera in Settings", icon: "⚙️", isError: true)
        }
    }

     func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let session = AVCaptureSession()
            session.sessionPreset = .high

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                DispatchQueue.main.async {
                    self.showToast("Camera unavailable", icon: "📷", isError: true)
                }
                return
            }
            session.addInput(input)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true

            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            self.captureSession = session

            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.previewView.bounds
                self.previewView.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
            }

            session.startRunning()
        }
    }

    // MARK: - Barcode Processing

     func processBarcode(_ payload: String) {
        if seenBarcodes.contains(payload) { return }
        if isShowingPicker { return }

        let now = CACurrentMediaTime()
        guard now - lastScanTime > scanCooldown else { return }
        lastScanTime = now

        if let item = itemByBarcode[payload] {
            seenBarcodes.insert(payload)

            if let idx = scannedItems.firstIndex(where: { $0.item.id == item.id }) {
                scannedItems[idx].quantity += 1
            } else {
                scannedItems.append((item: item, quantity: 1))
            }

            print("[BarcodeScanner] ✓ Matched: \(item.name) (barcode: \(payload))")

            DispatchQueue.main.async {
                self.showToast(
                    "\(item.name)\n₹\(String(format: "%.0f", item.defaultSellingPrice))",
                    icon: "✅",
                    isError: false
                )
                self.updateBillUI()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } else {
            // Unknown barcode → try Open Food Facts lookup first
            print("[BarcodeScanner] ✗ Unknown barcode: \(payload) — looking up online...")

            DispatchQueue.main.async {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                self.showToast("Looking up barcode...", icon: "🔍", isError: false)
            }

            OpenFoodFactsService.shared.lookupBarcode(payload) { [weak self] productInfo in
                guard let self = self else { return }

                if let info = productInfo {
                    let displayName = [info.brand, info.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                    print("[BarcodeScanner] 🌐 Found online: \(displayName). Running matcher...")

                    // Run Inventory Matcher
                    let matches = BarcodeMatcher.shared.findMatches(for: info.name, in: self.allItems)
                    let highestConfidence = matches.first?.confidence ?? 0.0

                    if highestConfidence > 0.4 {
                        // MATCH FOUND (Clash / Variant)
                        print("[BarcodeScanner] 🔍 Match found (confidence: \(highestConfidence)). Handling clash.")
                        let bestMatchName = matches.first!.item.name

                        DispatchQueue.main.async {
                            self.showToast("Variant Found?", icon: "🔍", isWarning: true, isError: false)
                            self.showItemPicker(for: payload)
                            self.pickerBarcodeLabel.text = "Barcode: \(payload) • \(displayName)"
                            // Filter list to the best match
                            self.pickerSearchBar.text = bestMatchName
                            self.searchBar(self.pickerSearchBar, textDidChange: bestMatchName)
                        }

                    } else {
                        // NO LOCAL MATCH -> Auto-Create Temporary Item with Yellow Tick
                        print("[BarcodeScanner] ⚠️ No local match. Auto-creating temporary item...")
                        let newItem = Item(
                            id: UUID(),
                            name: displayName,
                            unit: (info.quantity?.isEmpty == false) ? info.quantity! : "pcs",
                            barcode: payload,
                            defaultCostPrice: 0,
                            defaultSellingPrice: 0,
                            defaultPriceUpdatedAt: Date(),
                            lowStockThreshold: 10,
                            currentStock: 0,
                            createdDate: Date(),
                            lastRestockDate: nil,
                            isActive: true,
                            salesCount: 0,
                            salesTier: 0
                        )

                        do {
                            try AppDataModel.shared.dataModel.db.insertItem(newItem)

                            self.allItems.append(newItem)
                            self.itemByBarcode[payload] = newItem
                            self.seenBarcodes.insert(payload)
                            self.scannedItems.append((item: newItem, quantity: 1))

                            DispatchQueue.main.async {
                                self.showToast(
                                    "\(info.name)\nPrice & Info Missing",
                                    icon: "",
                                    isWarning: true
                                )
                                self.updateBillUI()
                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            }
                        } catch {
                            DispatchQueue.main.async {
                                self.showToast(
                                    "Could not save barcode item",
                                    icon: "⚠️",
                                    isError: true
                                )
                            }
                        }
                    }

                } else {
                    // Not found online — show standard picker (Manual Mapping)
                    print("[BarcodeScanner] ✗ Not found anywhere — showing manual picker")
                    DispatchQueue.main.async {
                        self.showItemPicker(for: payload)
                    }
                }
            }
        }
    }

    // MARK: - Item Picker

     func showItemPicker(for barcode: String) {
        isShowingPicker = true
        pendingBarcode = barcode
        filteredItems = allItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        pickerBarcodeLabel.text = "Barcode: \(barcode)"
        pickerSearchBar.text = ""
        pickerTableView.reloadData()

        pickerOverlay.isHidden = false
        pickerContainer.transform = CGAffineTransform(scaleX: 0.9, y: 0.9).translatedBy(x: 0, y: 30)

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5) {
            self.pickerOverlay.alpha = 1
            self.pickerContainer.transform = .identity
        }
    }

     func hideItemPicker() {
        UIView.animate(withDuration: 0.25, animations: {
            self.pickerOverlay.alpha = 0
            self.pickerContainer.transform = CGAffineTransform(scaleX: 0.95, y: 0.95).translatedBy(x: 0, y: 20)
        }) { _ in
            self.pickerOverlay.isHidden = true
            self.isShowingPicker = false
            self.pendingBarcode = nil
            self.pickerSearchBar.resignFirstResponder()
        }
    }

     func linkBarcodeToItem(_ item: Item, barcode: String) {
        // Save barcode on the item in DB
        var updated = item
        updated.barcode = barcode
        try? AppDataModel.shared.dataModel.db.updateItem(updated)

        // Update local caches
        if let idx = allItems.firstIndex(where: { $0.id == item.id }) {
            allItems[idx] = updated
        }
        itemByBarcode[barcode] = updated

        // Add to bill
        seenBarcodes.insert(barcode)
        if let idx = scannedItems.firstIndex(where: { $0.item.id == item.id }) {
            scannedItems[idx].quantity += 1
        } else {
            scannedItems.append((item: updated, quantity: 1))
        }

        print("[BarcodeScanner] 🔗 Linked barcode '\(barcode)' → \(item.name)")

        hideItemPicker()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showToast(
                "🔗 Linked & added\n\(item.name)",
                icon: "✅"
            )
            self.updateBillUI()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    @objc func pickerCancelTapped() {
        hideItemPicker()
        showToast("Barcode skipped", icon: "")
    }

    // MARK: - Toast

     func showToast(_ message: String, icon: String, isWarning: Bool = false, isError: Bool = false) {
        toastTimer?.invalidate()

        toastIcon.text = icon
        toastLabel.text = message

        // Color tint on the glass border
        if isError {
            toastContainer.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.5).cgColor
        } else if isWarning {
            toastContainer.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.7).cgColor
        } else {
            toastContainer.layer.borderColor = UIColor(named: "Lime Moss")!.withAlphaComponent(0.5).cgColor
        }
        toastContainer.layer.borderWidth = 1

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            self.toastContainer.alpha = 1
            self.toastContainer.transform = .identity
        }

        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.4) {
                self?.toastContainer.alpha = 0
            }
        }
    }

    // MARK: - Bill UI Updates

     func updateBillUI() {
        let count = scannedItems.reduce(0) { $0 + $1.quantity }
        let total = scannedItems.reduce(0.0) { $0 + Double($1.quantity) * $1.item.defaultSellingPrice }

        itemCountLabel.text = count == 0
            ? "Point camera at barcodes"
            : "\(count) item\(count == 1 ? "" : "s") scanned"
        totalLabel.text = "₹\(String(format: "%.0f", total))"

        billTableView.reloadData()

        if !scannedItems.isEmpty {
            let lastRow = IndexPath(row: scannedItems.count - 1, section: 0)
            billTableView.scrollToRow(at: lastRow, at: .bottom, animated: true)
        }
    }

    // MARK: - Actions

    @objc  func cancelTapped() {
        dismiss(animated: true)
    }

    @objc  func stopTapped() {
        guard !scannedItems.isEmpty else {
            dismiss(animated: true)
            return
        }

        let products: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] =
            scannedItems.map { entry in
                (
                    name: entry.item.name,
                    quantity: "\(entry.quantity)",
                    unit: entry.item.unit,
                    price: String(format: "%.0f", entry.item.defaultSellingPrice),
                    costPrice: String(format: "%.0f", entry.item.defaultCostPrice)
                )
            }

        let itemIDs = scannedItems.map { $0.item.id }
        let confidences = scannedItems.map { _ in "high" }

        if mode == .sale {
            let result = ParsedResult(
                entities: [],
                products: products,
                customerName: nil,
                isNegation: false,
                isReference: false,
                productItemIDs: itemIDs,
                productConfidences: confidences
            )
            dismiss(animated: true) { [weak self] in
                self?.onSaleResult?(result)
            }
        } else {
            let items = scannedItems.map { entry in
                ParsedPurchaseItem(
                    name: entry.item.name,
                    quantity: "\(entry.quantity)",
                    unit: entry.item.unit,
                    costPrice: String(format: "%.0f", entry.item.defaultCostPrice),
                    sellingPrice: String(format: "%.0f", entry.item.defaultSellingPrice),
                    itemLikelihood: 1.0
                )
            }
            let result = ParsedPurchaseResult(supplierName: nil, items: items)
            dismiss(animated: true) { [weak self] in
                self?.onPurchaseResult?(result)
            }
        }
    }
}

// MARK: - Video Frame Processing

extension BarcodeScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self, error == nil else { return }
            guard let results = request.results as? [VNBarcodeObservation] else { return }

            for observation in results {
                guard let payload = observation.payloadStringValue, !payload.isEmpty else { continue }
                self.processBarcode(payload)
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}

// MARK: - Bill Table DataSource

extension BarcodeScannerViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == pickerTableView { return filteredItems.count }
        return scannedItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == pickerTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "PickerItemCell", for: indexPath)
            let item = filteredItems[indexPath.row]
            cell.backgroundColor = .clear
            cell.textLabel?.textColor = .white
            cell.textLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            cell.textLabel?.text = "\(item.name)  •  ₹\(String(format: "%.0f", item.defaultSellingPrice))"
            cell.detailTextLabel?.textColor = UIColor.white.withAlphaComponent(0.5)
            cell.selectionStyle = .default
            let selectedBg = UIView()
            selectedBg.backgroundColor = UIColor(named: "Lime Moss")!.withAlphaComponent(0.2)
            cell.selectedBackgroundView = selectedBg
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "BarcodeItemCell", for: indexPath)
        let entry = scannedItems[indexPath.row]
        cell.backgroundColor = .clear
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = .systemFont(ofSize: 15)
        cell.selectionStyle = .none

        let price = String(format: "%.0f", entry.item.defaultSellingPrice * Double(entry.quantity))
        cell.textLabel?.text = "\(entry.item.name)  ×\(entry.quantity)  ₹\(price)"
        return cell
    }
}

// MARK: - Item Picker TableView Delegate

extension BarcodeScannerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard tableView == pickerTableView else { return }
        tableView.deselectRow(at: indexPath, animated: true)

        let item = filteredItems[indexPath.row]
        guard let barcode = pendingBarcode else { return }
        linkBarcodeToItem(item, barcode: barcode)
    }
}

// MARK: - Search Bar Delegate

extension BarcodeScannerViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            filteredItems = allItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            filteredItems = allItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        pickerTableView.reloadData()
    }
}
