import AVFoundation
import CoreImage
import UIKit
import Vision

enum ScanMode {
    case sale
    case purchase
}

enum SaleScanIntent {
    case bill
    case products
    case barcode
}

class SalesScanCameraViewController: UIViewController {

    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var shutterButton: UIButton!
    @IBOutlet weak var indicationLabel: UILabel!
    @IBOutlet weak var scanTypeControl: UISegmentedControl?
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    let mode: ScanMode
    var saleScanIntent: SaleScanIntent?
    var onSaleResult: ((ParsedResult) -> Void)?
    var onItemsParsed: ((ParsedResult) -> Void)?
    var onPurchaseResult: ((ParsedPurchaseResult) -> Void)?

    // MARK: - Camera
     var captureSession: AVCaptureSession?
     var photoOutput: AVCapturePhotoOutput?
     var videoDataOutput: AVCaptureVideoDataOutput?
     var previewLayer: AVCaptureVideoPreviewLayer?
     let sessionQueue = DispatchQueue(label: "camera.session")
     let videoQueue = DispatchQueue(label: "camera.video")

    // MARK: - Live Barcode Scanning State
     var isBarcodeScanning = false
     var barcodeItemLookup: [String: Item] = [:]
     var barcodeAllItems: [Item] = []
     var barcodeScannedItems: [(item: Item, quantity: Double)] = []
     var barcodeSeenCodes: Set<String> = []
     var barcodeLastScanTime: CFTimeInterval = 0
     let barcodeScanCooldown: CFTimeInterval = 1.5
     var barcodePickerShowing = false
     var barcodePendingCode: String?
     var barcodeFilteredItems: [Item] = []

    // MARK: - Barcode UI (overlaid on same screen)
     var barcodeToastView: UIVisualEffectView?
     var barcodeToastIcon: UILabel?
     var barcodeToastLabel: UILabel?
     var barcodeToastTimer: Timer?
     var barcodePickerOverlay: UIView?
     var barcodePickerContainer: UIVisualEffectView?
     var barcodePickerSearch: UISearchBar?
     var barcodePickerTable: UITableView?
     var barcodePickerBarcodeLabel: UILabel?

    // MARK: - Live Product Scanning State (offline mode)
     var isProductScanning = false
     var productCandidates: [UUID: (item: Item, score: Float, frameCount: Int)] = [:]
     var productConfirmedItems: [(item: Item, quantity: Double)] = []
     var productConfirmedIDs: Set<UUID> = []
     var productLastProcessTime: CFTimeInterval = 0
     let productScanInterval: CFTimeInterval = 0.33  // ~3 FPS
     var productIsProcessingFrame = false  // prevent overlap
     var productOverlayContainer: UIView?
     var productAmbiguousPickerShowing = false
     var productAmbiguousShown: Set<String> = []
     var lastProductFrame: CGImage?
     var lastProductFrameSize: CGSize = .zero
     var liveDetectionBoxes: [(rect: CGRect, hasMask: Bool)] = []
     private var pinnedMarks: [PinnedScanMark] = []
     var liveMatchOverlays: [(rect: CGRect, label: String)] = []

    private struct PinnedScanMark {
        let id: UUID
        var imageRect: CGRect
        let crop: CGImage
    }

    private static let storyboardIdentifier = "SalesScanCameraViewController"

    init?(coder: NSCoder, mode: ScanMode) {
        self.mode = mode
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        self.mode = .sale
        super.init(coder: coder)
    }

    static func instantiate(mode: ScanMode, storyboard: UIStoryboard? = nil) -> SalesScanCameraViewController {
        let storyboard = storyboard ?? UIStoryboard(name: "Main", bundle: nil)
        return storyboard.instantiateViewController(identifier: storyboardIdentifier) { coder in
            SalesScanCameraViewController(coder: coder, mode: mode)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureStoryboardUI()
        indicationLabel.textColor = .white
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(embeddingsRebuildFinished),
            name: ProductFingerprintManager.embeddingsDidRebuildNotification,
            object: nil
        )
        checkCameraPermission()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func embeddingsRebuildFinished() {
        guard isProductScanning else { return }
        updateProductScanStatus()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePreviewLayerLayout()

        sessionQueue.async { [weak self] in
            guard let self = self,
                  let captureSession = self.captureSession,
                  !captureSession.isRunning else { return }
            captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreviewLayerLayout()
        productOverlayContainer?.frame = previewView.bounds
        bringCameraControlsToFront()
    }

     func configureStoryboardUI() {
        if let btn = closeButton {
            UIButton.applyGlassStyle(to: btn)
        }
        updateStatusLabel()
         updateShutterButton(symbolName: "camera.fill", color: UIColor(named: "Lime Moss") ?? .systemGreen)
        activityIndicator.hidesWhenStopped = true
        scanTypeControl?.isHidden = mode == .purchase || saleScanIntent != nil
        let lime = UIColor(named: "Lime Moss") ?? .systemGreen
        scanTypeControl?.selectedSegmentTintColor = lime
        scanTypeControl?.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }

     func updateStatusLabel() {
        if mode == .purchase {
            indicationLabel.text = "Point at the bill to scan"
            return
        }

        if let intent = saleScanIntent {
            switch intent {
            case .bill: indicationLabel.text = "Point at the bill"
            case .products: indicationLabel.text = "Point at products"
            case .barcode: indicationLabel.text = "Point at the barcode"
            }
            return
        }

        switch scanTypeControl?.selectedSegmentIndex {
        case 0: indicationLabel.text = "Point at a bill, then capture"
        case 1: indicationLabel.text = "Point at products, then capture"
        case 2: indicationLabel.text = "Point at the barcode, then capture"
        default: indicationLabel.text = "Choose an option above, then capture"
        }
    }

    func updateShutterButton(symbolName: String, color: UIColor) {
        if var configuration = shutterButton.configuration {
            configuration.image = UIImage(systemName: symbolName)
            configuration.baseBackgroundColor = color
            configuration.baseForegroundColor = .white
            shutterButton.configuration = configuration
        } else {
            shutterButton.setImage(UIImage(systemName: symbolName), for: .normal)
            shutterButton.backgroundColor = color
        }
    }

    private func updateProductScanStatus() {
        if ProductFingerprintManager.shared.isRebuildingEmbeddings {
            indicationLabel.isHidden = false
            indicationLabel.text = "Updating product index…"
            return
        }
        let count = productConfirmedItems.reduce(0) { $0 + $1.quantity }
        indicationLabel.isHidden = false
        indicationLabel.text = count == 0
            ? "Tap objects to mark them"
            : "\(count) product\(count == 1 ? "" : "s") marked"
    }

    @objc  func scanIntentChanged() {
        updateStatusLabel()
        // If switching away from active modes, stop them
        if currentSaleIntent() != .barcode && isBarcodeScanning {
            stopBarcodeScanning()
        }
        if currentSaleIntent() != .products && isProductScanning {
            stopProductScanning()
        }
    }

     func currentSaleIntent() -> SaleScanIntent {
        if let intent = saleScanIntent { return intent }
        let idx = scanTypeControl?.selectedSegmentIndex ?? 0
        switch idx {
        case 0: return .bill
        case 2: return .barcode
        default: return .products
        }
    }

     func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupCamera() }
                    else { self?.showPermissionAlert() }
                }
            }
        default:
            showPermissionAlert()
        }
    }

     func showPermissionAlert() {
        let alert = UIAlertController(title: "Camera Access", message: "Enable camera in Settings to scan.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

     func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let session = AVCaptureSession()
            session.sessionPreset = self.mode == .sale ? .high : .photo

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                DispatchQueue.main.async {
                    self.indicationLabel.text = "Camera unavailable"
                }
                return
            }
            session.addInput(input)

            let output = AVCapturePhotoOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                self.photoOutput = output
            }
            // Video output for live camera view
            let videoOut = AVCaptureVideoDataOutput()
            videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOut.alwaysDiscardsLateVideoFrames = true
            videoOut.setSampleBufferDelegate(self, queue: self.videoQueue)
            if session.canAddOutput(videoOut) {
                session.addOutput(videoOut)
                self.videoDataOutput = videoOut
            }

            self.captureSession = session

            DispatchQueue.main.async {
                self.syncCaptureOrientation()
                self.attachPreviewLayer(for: session)
            }
            session.startRunning()
        }
    }

    private func attachPreviewLayer(for session: AVCaptureSession) {
        previewLayer?.removeFromSuperlayer()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewView.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        updatePreviewLayerLayout()
        ensureProductOverlayContainer()
        bringCameraControlsToFront()
    }

    private func updatePreviewLayerLayout() {
        previewLayer?.frame = previewView.bounds
        syncCaptureOrientation()
    }

    private func syncCaptureOrientation() {
        let orientation = AVCaptureVideoOrientation.portrait
        if let connection = previewLayer?.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
        if let connection = videoDataOutput?.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
        if let connection = photoOutput?.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
    }

    @objc  func cancelTapped() {
        dismiss(animated: true)
    }

    @IBAction func closeTapped(_ sender: UIButton) {
        dismiss(animated: true)
    }

    @objc  func captureTapped() {
        // Barcode mode
        if currentSaleIntent() == .barcode {
            if isBarcodeScanning {
                finishBarcodeScanning()
            } else {
                startBarcodeScanning()
            }
            return
        }

        // Products mode
        if currentSaleIntent() == .products {
            if isProductScanning {
                finishProductScanning()
            } else {
                startProductScanning()
            }
            return
        }

        shutterButton.isEnabled = false
        activityIndicator.startAnimating()

        // Bill mode
        indicationLabel.text = "Processing..."
        guard let output = photoOutput else {
            shutterButton.isEnabled = true
            activityIndicator.stopAnimating()
            return
        }
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    @IBAction private func captureButtonTapped(_ sender: UIButton) {
        captureTapped()
    }

    @IBAction private func scanTypeValueChanged(_ sender: UISegmentedControl) {
        scanIntentChanged()
    }

     func processImage(_ image: UIImage) {
        guard let cgImage = image.cgImage else {
            finishWithError("Could not process image")
            return
        }

        if mode == .sale {
            switch currentSaleIntent() {
            case .bill: processBill(image: image, cgImage: cgImage)
            case .products: break
            case .barcode: break
            }
        } else {
            processBill(image: image, cgImage: cgImage)
        }
    }



     func processBill(image: UIImage, cgImage: CGImage) {
        print("\n[ScanCamera] ═══════════════════════════════════════")
        print("[ScanCamera] processBill called | mode=\(mode == .sale ? "SALE" : "PURCHASE")")
        print("[ScanCamera] Gemini status: isConfigured=\(GeminiService.shared.isConfigured(for: .camera)), hasAPIKey=\(GeminiService.shared.hasAPIKey), isLimitReached=\(GeminiService.shared.isLimitReached)")
        
        // Try Gemini first for superior OCR + parsing in one call
        if GeminiService.shared.isConfigured(for: .camera) {
            print("[ScanCamera] ✅ Using Gemini for bill OCR...")
            if self.mode == .sale {
                GeminiService.shared.parseBillForSale(image: image) { [weak self] result in
                    guard let self = self else { return }
                    if let result = result, !result.products.isEmpty {
                        print("[ScanCamera] ✅ Gemini bill SALE succeeded: \(result.products.count) items")
                        for (i, p) in result.products.enumerated() {
                            print("[ScanCamera]   \(i+1). \(p.name) | qty=\(p.quantity) | price=\(p.price ?? "nil") | costPrice=\(p.costPrice ?? "nil") | unit=\(p.unit ?? "nil")")
                        }
                        self.finishWithSaleResult(result)
                    } else {
                        print("[ScanCamera] ❌ Gemini bill sale returned nil or empty, falling back to on-device OCR")
                        self.processBillOnDevice(image: image, cgImage: cgImage)
                    }
                }
            } else {
                GeminiService.shared.parseBillForPurchase(image: image) { [weak self] result in
                    guard let self = self else { return }
                    if let result = result, !result.items.isEmpty {
                        print("[ScanCamera] ✅ Gemini bill PURCHASE succeeded: \(result.items.count) items")
                        for (i, p) in result.items.enumerated() {
                            print("[ScanCamera]   \(i+1). \(p.name) | qty=\(p.quantity) | costPrice=\(p.costPrice ?? "nil") | sellingPrice=\(p.sellingPrice ?? "nil") | unit=\(p.unit ?? "nil")")
                        }
                        self.finishWithPurchaseResult(result)
                    } else {
                        print("[ScanCamera] ❌ Gemini bill purchase returned nil or empty, falling back to on-device OCR")
                        self.processBillOnDevice(image: image, cgImage: cgImage)
                    }
                }
            }
        } else {
            print("[ScanCamera] ⚠️ Gemini NOT configured — using on-device OCR only")
            // Show one-time alert if user just hit their Gemini limit
            if GeminiService.shared.hasAPIKey && !UsageTracker.shared.canUse(.camera) {
                print("[ScanCamera] ⚠️ Reason: camera AI limit reached")
                showFreemiumLimitAlertIfNeeded()
            }
            processBillOnDevice(image: image, cgImage: cgImage)
        }
        print("[ScanCamera] ═══════════════════════════════════════\n")
    }

    /// Shows a one-time alert per app session when the user exhausts their free Gemini scans.
    private static var didShowFreemiumAlert = false
    private func showFreemiumLimitAlertIfNeeded() {
        guard !Self.didShowFreemiumAlert else { return }
        Self.didShowFreemiumAlert = true

        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: UsageTracker.shared.isProUser ? "Camera AI limit reached" : "Free AI Scans Used Up",
                message: UsageTracker.shared.limitReachedMessage(for: .camera),
                preferredStyle: .alert
            )
            if !UsageTracker.shared.isProUser {
                alert.addAction(UIAlertAction(title: "See Pro", style: .default) { [weak self] _ in
                    guard let self else { return }
                    ProBenefitsViewController.present(from: self)
                })
            }
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            self.present(alert, animated: true)
        }
    }

     func processBillOnDevice(image: UIImage, cgImage: CGImage) {
        BillOCRService.shared.recognizeTextFromBill(image: image) { [weak self] (boxes: [OCRTextBox]) in
            guard let self = self else { return }
            if self.mode == .sale {
                let parsed = BillParser.shared.parseForSale(boxes: boxes)
                DispatchQueue.main.async {
                    self.finishWithSaleResult(parsed)
                }
            } else {
                let parsed = BillParser.shared.parseForPurchase(boxes: boxes)
                DispatchQueue.main.async {
                    self.finishWithPurchaseResult(parsed)
                }
            }
        }
    }

     func finishWithSaleResult(_ result: ParsedResult) {
        activityIndicator.stopAnimating()
        shutterButton.isEnabled = true
        if result.printedTotalMismatch {
            let alert = UIAlertController(
                title: "Printed total does not match",
                message: "The bill total \(result.printedGrandTotal ?? "") does not match the line items. Review before saving.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Review", style: .default) { [weak self] _ in
                self?.deliverSaleResult(result)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                self?.dismiss(animated: true)
            })
            present(alert, animated: true)
            return
        }
        deliverSaleResult(result)
    }

    private func deliverSaleResult(_ result: ParsedResult) {
        let callback = onSaleResult
        dismiss(animated: true) {
            callback?(result)
        }
    }

     func finishWithPurchaseResult(_ result: ParsedPurchaseResult) {
        activityIndicator.stopAnimating()
        shutterButton.isEnabled = true
        let callback = onPurchaseResult
        dismiss(animated: true) {
            callback?(result)
        }
    }

     func finishWithError(_ message: String) {
        activityIndicator.stopAnimating()
        shutterButton.isEnabled = true
        indicationLabel.text = message
    }
}

extension SalesScanCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.finishWithError(error.localizedDescription)
            }
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async {
                self.finishWithError("Could not get image")
            }
            return
        }
        processImage(image)
    }
}

extension SalesScanCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Live barcode scanning
        if isBarcodeScanning && !barcodePickerShowing {
            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            let ctx = CIContext()
            guard let cgImage = ctx.createCGImage(ci, from: ci.extent) else { return }
            let request = VNDetectBarcodesRequest { [weak self] req, err in
                guard let self = self, err == nil else { return }
                guard let results = req.results as? [VNBarcodeObservation] else { return }
                for obs in results {
                    guard let payload = obs.payloadStringValue, !payload.isEmpty else { continue }
                    self.handleBarcodeDetected(payload)
                }
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            return
        }

        // Live product scanning (CLIP + Barcode + OCR via video frames)
        if isProductScanning && !productIsProcessingFrame && !productAmbiguousPickerShowing {
            let now = CACurrentMediaTime()
            guard now - productLastProcessTime >= productScanInterval else { return }
            productLastProcessTime = now
            productIsProcessingFrame = true

            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            let ctx = CIContext()
            guard let cgImage = ctx.createCGImage(ci, from: ci.extent) else {
                productIsProcessingFrame = false
                return
            }

            // Run all three detection strategies in parallel on this frame:
            //   1. CLIP matching (product recognition via trained embeddings)
            //   2. Barcode scanning (instant match if barcode found in inventory)
            //   3. OCR label reading (extract weight, variant from packaging text)
            let group = DispatchGroup()

            var clipOutcome = ProductScanOutcome(matches: [], overlays: [], ambiguous: [], allDetections: [])
            var barcodeMatches: [(Item, String)] = []  // (item, barcode)
            var ocrLabels: [String] = []

            // ── Strategy 1: CLIP matching ──
            group.enter()
            ProductFingerprintManager.shared.matchObjectsWithOutcome(in: cgImage) { outcome in
                clipOutcome = outcome
                group.leave()
            }

            // ── Strategy 2: Barcode scanning (parallel) ──
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                defer { group.leave() }
                guard let self = self else { return }
                let request = VNDetectBarcodesRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                guard let results = request.results as? [VNBarcodeObservation] else { return }
                for obs in results {
                    guard let payload = obs.payloadStringValue, !payload.isEmpty else { continue }
                    // Look up barcode in inventory
                    if let item = self.barcodeItemLookup[payload] {
                        barcodeMatches.append((item, payload))
                    }
                }
            }

            // ── Strategy 3: OCR label read (parallel) ──
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .fast
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                if let results = request.results as? [VNRecognizedTextObservation] {
                    for obs in results {
                        if let text = obs.topCandidates(1).first?.string {
                            ocrLabels.append(text)
                        }
                    }
                }
            }

            // ── Combine results ──
            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                self.productIsProcessingFrame = false

                let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
                self.lastProductFrame = cgImage
                self.lastProductFrameSize = imageSize
                self.liveDetectionBoxes = clipOutcome.allDetections
                self.liveMatchOverlays = clipOutcome.overlays
                self.redrawProductBoxes()

                for (item, barcode) in barcodeMatches {
                    self.confirmOrRaiseQuantity(item: item, quantity: 1, score: 1.0)
                    print("[ProductScanner] Barcode match: \(barcode) → \(item.name)")
                }

                for (item, score, count) in clipOutcome.matches {
                    self.handleProductDetected(item: item, score: score, quantity: max(1, count))
                }

                for pair in clipOutcome.ambiguous {
                    self.presentCloseSKUPickerIfNeeded(pair.0, pair.1)
                }

                if !ocrLabels.isEmpty {
                    self.processOCRLabels(ocrLabels)
                }
            }
            return
        }
    }
}

//Live Barcode Scanning

extension SalesScanCameraViewController: UISearchBarDelegate {

     func startBarcodeScanning() {
        barcodeAllItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        barcodeItemLookup = Dictionary(
            barcodeAllItems.compactMap { item -> (String, Item)? in
                guard let code = item.barcode, !code.isEmpty else { return nil }
                return (code, item)
            },
            uniquingKeysWith: { first, _ in first }
        )

        barcodeScannedItems = []
        barcodeSeenCodes = []
        isBarcodeScanning = true

        updateShutterButton(symbolName: "stop.fill", color: .systemRed)
        indicationLabel.text = "Scanning… point at barcodes"

        setupBarcodeToast()
        setupBarcodeItemPicker()

        print("[BarcodeScanner] Started live scanning. \(barcodeItemLookup.count) barcodes indexed.")
    }

     func stopBarcodeScanning() {
        isBarcodeScanning = false
        updateShutterButton(symbolName: "camera.fill", color: UIColor(named: "Lime Moss") ?? .systemGreen)
        updateStatusLabel()

        barcodeToastView?.removeFromSuperview()
        barcodePickerOverlay?.removeFromSuperview()
        barcodeToastView = nil
        barcodePickerOverlay = nil
    }

     func finishBarcodeScanning() {
        guard !barcodeScannedItems.isEmpty else {
            stopBarcodeScanning()
            return
        }

        let products: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] =
            barcodeScannedItems.map { entry in
                (
                    name: entry.item.name,
                    quantity: "\(entry.quantity)",
                    unit: entry.item.unit,
                    price: String(format: "%.0f", entry.item.defaultSellingPrice),
                    costPrice: String(format: "%.0f", entry.item.defaultCostPrice)
                )
            }

        let itemIDs = barcodeScannedItems.map { $0.item.id }
        let confidences = barcodeScannedItems.map { _ in "high" }

        stopBarcodeScanning()

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
            finishWithSaleResult(result)
        } else {
            let items = barcodeScannedItems.map { entry in
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
            finishWithPurchaseResult(result)
        }
    }

     func startProductScanning() {
        productCandidates = [:]
        productConfirmedItems = []
        productConfirmedIDs = []
        productIsProcessingFrame = false
        productAmbiguousPickerShowing = false
        productAmbiguousShown = []
        isProductScanning = true
        ProductFingerprintManager.shared.prepareEmbeddingsForCurrentExtractor()
        pinnedMarks = []
        liveDetectionBoxes = []
        liveMatchOverlays = []
        lastProductFrame = nil
        clearProductOverlays()
        productOverlayContainer?.isUserInteractionEnabled = true
        bringCameraControlsToFront()

        // Load barcode inventory for inline barcode matching
        barcodeAllItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        barcodeItemLookup = Dictionary(
            barcodeAllItems.compactMap { item -> (String, Item)? in
                guard let code = item.barcode, !code.isEmpty else { return nil }
                return (code, item)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Change button to "Stop" style
        updateShutterButton(symbolName: "stop.fill", color: .systemRed)
        updateProductScanStatus()

        print("[ProductScanner] Started live video-frame scanning.")
    }

     func stopProductScanning() {
        isProductScanning = false
        productIsProcessingFrame = false
        productAmbiguousPickerShowing = false
        pinnedMarks = []
        liveDetectionBoxes = []
        liveMatchOverlays = []
        lastProductFrame = nil
        productOverlayContainer?.isUserInteractionEnabled = false
        clearProductOverlays()
        bringCameraControlsToFront()
        updateShutterButton(symbolName: "camera.fill", color: UIColor(named: "Lime Moss") ?? .systemGreen)
        updateStatusLabel()
    }

    private func ensureProductOverlayContainer() {
        if productOverlayContainer == nil {
            let container = UIView()
            container.backgroundColor = .clear
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleProductOverlayTap(_:)))
            container.addGestureRecognizer(tap)
            previewView.addSubview(container)
            productOverlayContainer = container
        }
        productOverlayContainer?.frame = previewView.bounds
        productOverlayContainer?.isUserInteractionEnabled = isProductScanning
        bringCameraControlsToFront()
    }

    /// Keep Bill / Products / Barcode tappable above the full-screen detection overlay.
    private func bringCameraControlsToFront() {
        if let control = scanTypeControl, !control.isHidden {
            previewView.bringSubviewToFront(control)
        }
        previewView.bringSubviewToFront(indicationLabel)
        previewView.bringSubviewToFront(activityIndicator)
        if isProductScanning, let container = productOverlayContainer {
            // Overlay below segment control but above the live preview.
            if let control = scanTypeControl {
                previewView.insertSubview(container, belowSubview: control)
            }
        }
    }

    private func clearProductOverlays() {
        productOverlayContainer?.subviews.forEach { $0.removeFromSuperview() }
    }

    private func redrawProductBoxes() {
        ensureProductOverlayContainer()
        clearProductOverlays()
        guard isProductScanning, let container = productOverlayContainer else { return }
        container.frame = previewView.bounds
        let imageSize = lastProductFrameSize
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        for detection in liveDetectionBoxes {
            addBoxView(
                imageRect: detection.rect,
                imageSize: imageSize,
                in: container,
                color: detection.hasMask ? .systemGreen : .cyan,
                dashed: true,
                label: nil
            )
        }

        for mark in pinnedMarks {
            addBoxView(
                imageRect: mark.imageRect,
                imageSize: imageSize,
                in: container,
                color: UIColor(named: "Lime Moss") ?? .systemGreen,
                dashed: false,
                label: "Marked"
            )
        }

        for overlay in liveMatchOverlays {
            addBoxView(
                imageRect: overlay.rect,
                imageSize: imageSize,
                in: container,
                color: .systemYellow,
                dashed: false,
                label: overlay.label
            )
        }
    }

    private func addBoxView(
        imageRect: CGRect,
        imageSize: CGSize,
        in container: UIView,
        color: UIColor,
        dashed: Bool,
        label: String?
    ) {
        let viewRect = mapImageRect(imageRect, imageSize: imageSize, into: container.bounds.size)
        guard viewRect.width > 8, viewRect.height > 8,
              viewRect.intersects(container.bounds) else { return }

        let box = UIView(frame: viewRect)
        box.backgroundColor = color.withAlphaComponent(0.10)
        box.isUserInteractionEnabled = false

        if dashed {
            let dashedBorder = CAShapeLayer()
            dashedBorder.strokeColor = color.cgColor
            dashedBorder.fillColor = nil
            dashedBorder.lineDashPattern = [5, 3]
            dashedBorder.lineWidth = 2
            dashedBorder.frame = box.bounds
            dashedBorder.path = UIBezierPath(roundedRect: box.bounds, cornerRadius: 4).cgPath
            box.layer.addSublayer(dashedBorder)
        } else {
            box.layer.borderColor = color.cgColor
            box.layer.borderWidth = 2.5
            box.layer.cornerRadius = 4
        }

        if let label {
            let caption = UILabel()
            caption.text = " \(label) "
            caption.font = .systemFont(ofSize: 11, weight: .semibold)
            caption.textColor = .black
            caption.backgroundColor = color.withAlphaComponent(0.92)
            caption.sizeToFit()
            caption.frame = CGRect(
                x: 0,
                y: max(0, -18),
                width: max(box.bounds.width, caption.bounds.width + 6),
                height: 18
            )
            box.addSubview(caption)
        }
        container.addSubview(box)
    }

    @objc private func handleProductOverlayTap(_ gesture: UITapGestureRecognizer) {
        guard isProductScanning, lastProductFrameSize.width > 0 else { return }
        let point = gesture.location(in: productOverlayContainer)
        let imagePoint = mapViewPoint(point, imageSize: lastProductFrameSize, from: productOverlayContainer?.bounds.size ?? .zero)

        if let index = pinnedMarks.firstIndex(where: { $0.imageRect.insetBy(dx: -12, dy: -12).contains(imagePoint) }) {
            pinnedMarks.remove(at: index)
            redrawProductBoxes()
            updateProductScanStatus()
            return
        }

        let hitLive = liveDetectionBoxes.first(where: { $0.rect.contains(imagePoint) })
        let imageRect: CGRect
        if let hit = hitLive {
            imageRect = hit.rect
        } else {
            let side = min(lastProductFrameSize.width, lastProductFrameSize.height) * 0.28
            imageRect = CGRect(
                x: imagePoint.x - side / 2,
                y: imagePoint.y - side / 2,
                width: side,
                height: side
            ).intersection(CGRect(origin: .zero, size: lastProductFrameSize))
        }
        guard imageRect.width > 8, imageRect.height > 8, let frame = lastProductFrame else { return }

        indicationLabel.text = "Marking…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var box = DetectedObjectBox(rect: imageRect, confidence: 1, mask: nil)
            if MobileSAMService.isEnabled, let sam = MobileSAMService.shared, let encoding = sam.encodeImage(frame) {
                box = sam.generateMasks(encoding: encoding, boxes: [box]).first ?? box
            }
            guard let crop = self.cropCGImage(frame, to: box.rect) else { return }

            DispatchQueue.main.async {
                let mark = PinnedScanMark(id: UUID(), imageRect: box.rect, crop: crop)
                self.pinnedMarks.append(mark)
                self.redrawProductBoxes()
                self.indicationLabel.text = "Marked \(self.pinnedMarks.count) — matching…"

                ProductFingerprintManager.shared.matchMarkedCrop(crop) { [weak self] item, score in
                    guard let self else { return }
                    if let item {
                        self.confirmOrRaiseQuantity(item: item, quantity: 1, score: max(score, 0.88))
                        self.indicationLabel.text = "✓ \(item.name)"
                    } else if score >= 0.65 {
                        self.updateProductScanStatus()
                        self.indicationLabel.text = "Marked — looks different (score \(Int(score * 100))%)"
                    } else {
                        self.updateProductScanStatus()
                        self.indicationLabel.text = "Marked — not in stock yet"
                    }
                }
            }
        }
    }

    private func cropCGImage(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let clamped = rect.integral.standardized.intersection(
            CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        guard clamped.width > 1, clamped.height > 1 else { return nil }
        return image.cropping(to: clamped)
    }

    private func mapViewPoint(_ point: CGPoint, imageSize: CGSize, from viewSize: CGSize) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledW = imageSize.width * scale
        let scaledH = imageSize.height * scale
        let offsetX = (viewSize.width - scaledW) / 2
        let offsetY = (viewSize.height - scaledH) / 2
        return CGPoint(
            x: (point.x - offsetX) / scale,
            y: (point.y - offsetY) / scale
        )
    }

    private func mapImageRect(_ imageRect: CGRect, imageSize: CGSize, into viewSize: CGSize) -> CGRect {
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledW = imageSize.width * scale
        let scaledH = imageSize.height * scale
        let offsetX = (viewSize.width - scaledW) / 2
        let offsetY = (viewSize.height - scaledH) / 2
        return CGRect(
            x: imageRect.origin.x * scale + offsetX,
            y: imageRect.origin.y * scale + offsetY,
            width: imageRect.width * scale,
            height: imageRect.height * scale
        )
    }

    private func presentCloseSKUPickerIfNeeded(_ first: Item, _ second: Item) {
        let key = [first.id.uuidString, second.id.uuidString].sorted().joined(separator: "|")
        guard !productAmbiguousShown.contains(key), !productAmbiguousPickerShowing else { return }
        if productConfirmedIDs.contains(first.id) || productConfirmedIDs.contains(second.id) { return }

        productAmbiguousShown.insert(key)
        productAmbiguousPickerShowing = true

        let sheet = UIAlertController(
            title: "Which product?",
            message: "These look similar. Choose the item on the table.",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: first.name, style: .default) { [weak self] _ in
            self?.confirmOrRaiseQuantity(item: first, quantity: 1, score: 0.9)
            self?.productAmbiguousPickerShowing = false
        })
        sheet.addAction(UIAlertAction(title: second.name, style: .default) { [weak self] _ in
            self?.confirmOrRaiseQuantity(item: second, quantity: 1, score: 0.9)
            self?.productAmbiguousPickerShowing = false
        })
        sheet.addAction(UIAlertAction(title: "Neither", style: .cancel) { [weak self] _ in
            self?.productAmbiguousPickerShowing = false
        })
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = previewView
            popover.sourceRect = CGRect(x: previewView.bounds.midX, y: previewView.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    func handleProductDetected(item: Item, score: Float, quantity: Int = 1) {
        assert(Thread.isMainThread, "handleProductDetected must be called on main thread")

        // Live auto-add is stricter than marked-crop matching to avoid carpet / background FPs.
        guard score >= 0.86 else { return }
        let qty = Double(max(1, quantity))

        if productConfirmedIDs.contains(item.id) {
            confirmOrRaiseQuantity(item: item, quantity: qty, score: score)
            return
        }

        if var candidate = productCandidates[item.id] {
            candidate.frameCount += 1
            candidate.score = max(candidate.score, score)
            productCandidates[item.id] = candidate

            if candidate.frameCount >= 5 || score >= 0.93 {
                productCandidates.removeValue(forKey: item.id)
                confirmOrRaiseQuantity(item: item, quantity: qty, score: score)
                print("[ProductScanner] Confirmed: \(item.name) (score: \(String(format: "%.2f", score)), frames: \(candidate.frameCount), qty: \(qty))")
            }
        } else {
            productCandidates[item.id] = (item: item, score: score, frameCount: 1)
        }
    }

    private func confirmOrRaiseQuantity(item: Item, quantity: Double, score: Float) {
        if let idx = productConfirmedItems.firstIndex(where: { $0.item.id == item.id }) {
            let raised = max(productConfirmedItems[idx].quantity, quantity)
            if raised != productConfirmedItems[idx].quantity {
                productConfirmedItems[idx].quantity = raised
                updateProductScanStatus()
            }
            return
        }
        productConfirmedIDs.insert(item.id)
        productConfirmedItems.append((item: item, quantity: max(1, quantity)))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        updateProductScanStatus()
    }
     func processOCRLabels(_ labels: [String]) {
        let allText = labels.joined(separator: " ").lowercased()
        guard !allText.isEmpty else { return }

        // ── Step 1: Extract all weight/volume mentions from the label ──
        var detectedWeights: [(value: Double, unit: String, normalized: String)] = []
        let weightPattern = #"(\d+\.?\d*)\s*(g|gm|gms|gram|grams|kg|kgs|ml|l|ltr|litre|litres|liter|liters)\b"#
        if let regex = try? NSRegularExpression(pattern: weightPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: allText, range: NSRange(allText.startIndex..., in: allText))
            for match in matches {
                if let valueRange = Range(match.range(at: 1), in: allText),
                   let unitRange = Range(match.range(at: 2), in: allText),
                   let value = Double(allText[valueRange]) {
                    let unit = String(allText[unitRange]).lowercased()
                    // Normalize to base unit for comparison
                    let normalized = normalizeWeight(value: value, unit: unit)
                    detectedWeights.append((value: value, unit: unit, normalized: normalized))
                    print("[OCR] Detected weight: \(value) \(unit) → \(normalized)")
                }
            }
        }

        // ── Step 2: Extract MRP/price mentions ──
        var detectedPrices: [Double] = []
        let pricePattern = #"(?:mrp|rs\.?|₹|price|m\.r\.p)[\s.:]*(\d+\.?\d*)"#
        if let regex = try? NSRegularExpression(pattern: pricePattern, options: .caseInsensitive) {
            let matches = regex.matches(in: allText, range: NSRange(allText.startIndex..., in: allText))
            for match in matches {
                if let priceRange = Range(match.range(at: 1), in: allText),
                   let price = Double(allText[priceRange]), price > 0 {
                    detectedPrices.append(price)
                    print("[OCR] Detected price: ₹\(price)")
                }
            }
        }
        // Also catch standalone ₹ followed by number (e.g., "₹20" without MRP prefix)
        let standalonePrice = #"₹\s*(\d+\.?\d*)"#
        if let regex = try? NSRegularExpression(pattern: standalonePrice, options: []) {
            let matches = regex.matches(in: allText, range: NSRange(allText.startIndex..., in: allText))
            for match in matches {
                if let priceRange = Range(match.range(at: 1), in: allText),
                   let price = Double(allText[priceRange]), price > 0,
                   !detectedPrices.contains(price) {
                    detectedPrices.append(price)
                    print("[OCR] Detected standalone price: ₹\(price)")
                }
            }
        }

        // ── Step 3: Match OCR text against inventory with variant awareness ──
        let allItems = barcodeAllItems.isEmpty
            ? ((try? AppDataModel.shared.dataModel.db.getAllItems()) ?? [])
            : barcodeAllItems

        // Group items by base name (e.g., "Lays Classic" groups "Lays Classic 20g" and "Lays Classic 52g")
        var candidateMatches: [(item: Item, nameScore: Float, weightMatch: Bool, priceMatch: Bool)] = []

        for item in allItems {
            guard !productConfirmedIDs.contains(item.id) else { continue }

            let itemName = item.name.lowercased()
            let words = itemName.split(separator: " ").map(String.init)

            // Check how many product name words appear in OCR text
            let matchingWords = words.filter { word in
                word.count >= 4 && allText.contains(word)
            }
            let nameScore = words.isEmpty ? 0 : Float(matchingWords.count) / Float(words.count)

            guard nameScore >= 0.4 && matchingWords.count >= 1 else { continue }

            // Check if item name contains a weight that matches OCR weight
            var weightMatch = false
            if !detectedWeights.isEmpty {
                // Extract weight from item name (e.g., "Lays Classic 52g" → "52g")
                if let weightRegex = try? NSRegularExpression(pattern: weightPattern, options: .caseInsensitive) {
                    let nameMatches = weightRegex.matches(in: itemName, range: NSRange(itemName.startIndex..., in: itemName))
                    for nm in nameMatches {
                        if let vr = Range(nm.range(at: 1), in: itemName),
                           let ur = Range(nm.range(at: 2), in: itemName),
                           let itemValue = Double(itemName[vr]) {
                            let itemUnit = String(itemName[ur]).lowercased()
                            let itemNorm = normalizeWeight(value: itemValue, unit: itemUnit)

                            // Check if any detected weight matches this item's weight
                            for dw in detectedWeights {
                                if dw.normalized == itemNorm {
                                    weightMatch = true
                                    print("[OCR] Weight match: item '\(item.name)' (\(itemNorm)) = OCR (\(dw.normalized))")
                                    break
                                }
                            }
                        }
                    }
                }
            }

            // Check if OCR price matches item's selling price (±2 tolerance for rounding)
            var priceMatch = false
            if !detectedPrices.isEmpty {
                let itemPrice = item.defaultSellingPrice
                for ocrPrice in detectedPrices {
                    if abs(itemPrice - ocrPrice) <= 2.0 {
                        priceMatch = true
                        print("[OCR] Price match: item '\(item.name)' (₹\(itemPrice)) ≈ OCR (₹\(ocrPrice))")
                        break
                    }
                }
            }

            candidateMatches.append((item: item, nameScore: nameScore, weightMatch: weightMatch, priceMatch: priceMatch))
        }

        // ── Step 4: Resolve variants ──
        // Priority: weight+price match > weight only > price only > name score
        let sorted = candidateMatches.sorted { a, b in
            // Both weight and price match is strongest
            let aStrength = (a.weightMatch ? 2 : 0) + (a.priceMatch ? 1 : 0)
            let bStrength = (b.weightMatch ? 2 : 0) + (b.priceMatch ? 1 : 0)
            if aStrength != bStrength { return aStrength > bStrength }
            return a.nameScore > b.nameScore
        }

        var confirmedInThisPass = Set<UUID>()
        for match in sorted {
            let item = match.item
            guard !confirmedInThisPass.contains(item.id) else { continue }

            // Strong match: weight OR price match (or both), plus reasonable name score
            let isStrongMatch = match.weightMatch && match.nameScore >= 0.4

            if isStrongMatch {
                // Determine the confirmation method for toast
                var methods: [String] = []
                if match.weightMatch { methods.append("weight") }
                if match.priceMatch { methods.append("price") }
                if methods.isEmpty { methods.append("label") }
                let methodStr = methods.joined(separator: "+")

                // OCR confirms this specific variant
                if productCandidates[item.id] != nil {
                    productConfirmedIDs.insert(item.id)
                    productCandidates.removeValue(forKey: item.id)
                    productConfirmedItems.append((item: item, quantity: 1))
                    confirmedInThisPass.insert(item.id)

                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    updateProductScanStatus()
                    print("[ProductScanner] OCR confirmed: \(item.name) (method: \(methodStr), nameScore: \(match.nameScore))")
                } else {
                    productCandidates[item.id] = (item: item, score: 0.6, frameCount: 1)
                }
            }
        }
    }
     func normalizeWeight(value: Double, unit: String) -> String {
        let u = unit.lowercased()
        switch u {
        case "kg", "kgs":
            return "\(Int(value * 1000))g"  // Convert to grams
        case "g", "gm", "gms", "gram", "grams":
            return "\(Int(value))g"
        case "l", "ltr", "litre", "litres", "liter", "liters":
            return "\(Int(value * 1000))ml"  // Convert to ml
        case "ml":
            return "\(Int(value))ml"
        default:
            return "\(Int(value))\(u)"
        }
    }


     func finishProductScanning() {
        guard !productConfirmedItems.isEmpty else {
            stopProductScanning()
            indicationLabel.text = "No products detected"
            return
        }

        let products: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] =
            productConfirmedItems.map { entry in
                (
                    name: entry.item.name,
                    quantity: "\(entry.quantity)",
                    unit: entry.item.unit,
                    price: String(format: "%.0f", entry.item.defaultSellingPrice),
                    costPrice: String(format: "%.0f", entry.item.defaultCostPrice)
                )
            }

        let itemIDs = productConfirmedItems.map { $0.item.id }
        let confidences = productConfirmedItems.map { _ in "high" }

        stopProductScanning()

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
            finishWithSaleResult(result)
        } else {
            let items = productConfirmedItems.map { entry in
                ParsedPurchaseItem(
                    name: entry.item.name,
                    quantity: "\(entry.quantity)",
                    unit: entry.item.unit,
                    costPrice: String(format: "%.0f", entry.item.defaultCostPrice),
                    sellingPrice: String(format: "%.0f", entry.item.defaultSellingPrice),
                    itemLikelihood: 0.9
                )
            }
            let result = ParsedPurchaseResult(supplierName: nil, items: items)
            finishWithPurchaseResult(result)
        }
    }

     func handleBarcodeDetected(_ payload: String) {
        if barcodeSeenCodes.contains(payload) { return }
        if barcodePickerShowing { return }

        let now = CACurrentMediaTime()
        guard now - barcodeLastScanTime > barcodeScanCooldown else { return }
        barcodeLastScanTime = now

        if let item = barcodeItemLookup[payload] {
            barcodeSeenCodes.insert(payload)
            if let idx = barcodeScannedItems.firstIndex(where: { $0.item.id == item.id }) {
                barcodeScannedItems[idx].quantity += 1
            } else {
                barcodeScannedItems.append((item: item, quantity: 1))
            }

            DispatchQueue.main.async {
                self.showBarcodeToast(
                    "\(item.name) — ₹\(String(format: "%.0f", item.defaultSellingPrice))",
                    isError: false
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } else {
            DispatchQueue.main.async {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                self.showBarcodeItemPicker(for: payload)
            }
        }
    }

    //Barcode Toast

     func setupBarcodeToast() {
        let toast = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.layer.cornerRadius = 14
        toast.clipsToBounds = true
        toast.alpha = 0
        view.addSubview(toast)

        let icon = UILabel()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.font = .systemFont(ofSize: 24)
        toast.contentView.addSubview(icon)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.numberOfLines = 2
        toast.contentView.addSubview(label)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            icon.leadingAnchor.constraint(equalTo: toast.contentView.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: toast.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: toast.contentView.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: toast.contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: toast.contentView.bottomAnchor, constant: -10),
        ])

        barcodeToastView = toast
        barcodeToastIcon = icon
        barcodeToastLabel = label
    }

     func showBarcodeToast(_ message: String, isError: Bool) {
        barcodeToastTimer?.invalidate()
        barcodeToastLabel?.text = message
        barcodeToastIcon?.text = isError ? "⚠️" : ""
        barcodeToastView?.layer.borderWidth = 1
        barcodeToastView?.layer.borderColor = isError
            ? UIColor.systemRed.withAlphaComponent(0.5).cgColor
            : UIColor.systemGreen.withAlphaComponent(0.5).cgColor

        UIView.animate(withDuration: 0.25) { self.barcodeToastView?.alpha = 1 }
        barcodeToastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) { self?.barcodeToastView?.alpha = 0 }
        }
    }

     func setupBarcodeItemPicker() {
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.alpha = 0
        overlay.isHidden = true
        view.addSubview(overlay)

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(blur)

        let container = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = 20
        container.clipsToBounds = true
        container.layer.borderWidth = 0.5
        container.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        overlay.addSubview(container)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "🔗 Link Barcode to Item"
        title.textColor = .white
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textAlignment = .center
        container.contentView.addSubview(title)

        let bcodeLbl = UILabel()
        bcodeLbl.translatesAutoresizingMaskIntoConstraints = false
        bcodeLbl.textColor = .systemGreen
        bcodeLbl.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        bcodeLbl.textAlignment = .center
        container.contentView.addSubview(bcodeLbl)

        let searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = "Search items…"
        searchBar.searchBarStyle = .minimal
        searchBar.tintColor = .systemGreen
        searchBar.searchTextField.textColor = .white
        searchBar.searchTextField.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        searchBar.delegate = self
        container.contentView.addSubview(searchBar)

        let pickerTable = UITableView(frame: .zero, style: .plain)
        pickerTable.translatesAutoresizingMaskIntoConstraints = false
        pickerTable.backgroundColor = .clear
        pickerTable.separatorColor = UIColor.white.withAlphaComponent(0.1)
        pickerTable.dataSource = self
        pickerTable.delegate = self
        pickerTable.tag = 888
        pickerTable.register(UITableViewCell.self, forCellReuseIdentifier: "BarcodePickerCell")
        container.contentView.addSubview(pickerTable)

        let skipBtn = UIButton(type: .system)
        skipBtn.translatesAutoresizingMaskIntoConstraints = false
        skipBtn.setTitle("Skip", for: .normal)
        skipBtn.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .normal)
        skipBtn.addTarget(self, action: #selector(barcodePickerSkipTapped), for: .touchUpInside)
        container.contentView.addSubview(skipBtn)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            blur.topAnchor.constraint(equalTo: overlay.topAnchor),
            blur.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
            container.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            container.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -20),
            container.heightAnchor.constraint(equalTo: overlay.heightAnchor, multiplier: 0.55),
            title.topAnchor.constraint(equalTo: container.contentView.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor, constant: -16),
            bcodeLbl.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            bcodeLbl.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor, constant: 16),
            bcodeLbl.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor, constant: -16),
            searchBar.topAnchor.constraint(equalTo: bcodeLbl.bottomAnchor, constant: 8),
            searchBar.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor, constant: -8),
            pickerTable.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            pickerTable.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor),
            pickerTable.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor),
            skipBtn.topAnchor.constraint(equalTo: pickerTable.bottomAnchor, constant: 6),
            skipBtn.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            skipBtn.heightAnchor.constraint(equalToConstant: 36),
            skipBtn.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor, constant: -10),
        ])

        barcodePickerOverlay = overlay
        barcodePickerContainer = container
        barcodePickerSearch = searchBar
        barcodePickerTable = pickerTable
        barcodePickerBarcodeLabel = bcodeLbl
    }

     func showBarcodeItemPicker(for barcode: String) {
        barcodePickerShowing = true
        barcodePendingCode = barcode
        barcodeFilteredItems = barcodeAllItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        barcodePickerBarcodeLabel?.text = "Barcode: \(barcode)"
        barcodePickerSearch?.text = ""
        barcodePickerTable?.reloadData()

        barcodePickerOverlay?.isHidden = false
        barcodePickerContainer?.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5) {
            self.barcodePickerOverlay?.alpha = 1
            self.barcodePickerContainer?.transform = .identity
        }
    }

     func hideBarcodeItemPicker() {
        UIView.animate(withDuration: 0.2, animations: {
            self.barcodePickerOverlay?.alpha = 0
        }) { _ in
            self.barcodePickerOverlay?.isHidden = true
            self.barcodePickerShowing = false
            self.barcodePendingCode = nil
            self.barcodePickerSearch?.resignFirstResponder()
        }
    }

     func linkBarcode(_ barcode: String, toItem item: Item) {
        var updated = item
        updated.barcode = barcode
        try? AppDataModel.shared.dataModel.db.updateItem(updated)

        if let idx = barcodeAllItems.firstIndex(where: { $0.id == item.id }) {
            barcodeAllItems[idx] = updated
        }
        barcodeItemLookup[barcode] = updated

        barcodeSeenCodes.insert(barcode)
        if let idx = barcodeScannedItems.firstIndex(where: { $0.item.id == item.id }) {
            barcodeScannedItems[idx].quantity += 1
        } else {
            barcodeScannedItems.append((item: updated, quantity: 1))
        }

        hideBarcodeItemPicker()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.showBarcodeToast("🔗 Linked: \(item.name)", isError: false)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    @objc func barcodePickerSkipTapped() {
        hideBarcodeItemPicker()
    }

    // MARK: Search delegate

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            barcodeFilteredItems = barcodeAllItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            barcodeFilteredItems = barcodeAllItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        barcodePickerTable?.reloadData()
    }
}

// MARK: - Barcode Picker Support

extension SalesScanCameraViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView.tag == 888 { return barcodeFilteredItems.count }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView.tag == 888 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "BarcodePickerCell", for: indexPath)
            let item = barcodeFilteredItems[indexPath.row]
            cell.backgroundColor = .clear
            cell.textLabel?.textColor = .white
            cell.textLabel?.font = .systemFont(ofSize: 15)
            cell.textLabel?.text = "\(item.name)  •  ₹\(String(format: "%.0f", item.defaultSellingPrice))"
            let selectedBg = UIView()
            selectedBg.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.2)
            cell.selectedBackgroundView = selectedBg
            return cell
        }

        return UITableViewCell()
    }
}

extension SalesScanCameraViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard tableView.tag == 888 else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        let item = barcodeFilteredItems[indexPath.row]
        guard let barcode = barcodePendingCode else { return }
        linkBarcode(barcode, toItem: item)
    }
}
