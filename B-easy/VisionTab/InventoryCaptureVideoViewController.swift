//  Record 5–8s video for inventory capture; extract frames at 2 FPS, quality filter, diversity selection.

import AVFoundation
import UIKit
import Vision
import CoreImage

final class InventoryCaptureVideoViewController: UIViewController {

     var captureSession: AVCaptureSession?
     var movieOutput: AVCaptureMovieFileOutput?
     var videoDataOutput: AVCaptureVideoDataOutput?
     var previewLayer: AVCaptureVideoPreviewLayer?
     let sessionQueue = DispatchQueue(label: "inventory.video")
     let validationQueue = DispatchQueue(label: "inventory.validation")
     var recordingURL: URL?
     var recordingStartTime: CFTimeInterval = 0
     var lastValidationTime: CFTimeInterval = 0
     let validationInterval: CFTimeInterval = 0.4

     let previewView = UIView()
     let statusLabel = UILabel()
     let recordButton = UIButton(type: .system)
     let progressLabel = UILabel()
     let activityIndicator = UIActivityIndicatorView(style: .large)
     var overlayContainer: UIView?
     var lastFrame: CGImage?
     var lastFrameSize: CGSize = .zero
     var liveBoxes: [(rect: CGRect, hasMask: Bool)] = []
     var pinnedRect: CGRect?
     var isProcessingOverlay = false

    var onComplete: (([UIImage], String?) -> Void)?
    var onCancel: (() -> Void)?

     let minDuration: TimeInterval = 5
     let maxDuration: TimeInterval = 10
     let targetFPS: Double = 4  // extract at 4 FPS for more training data

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Record Product"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        setupUI()
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
        overlayContainer?.frame = previewView.bounds
    }

     func setupUI() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Tap the product, then record while turning it"
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        view.addSubview(statusLabel)

        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.textColor = .white
        progressLabel.textAlignment = .center
        progressLabel.isHidden = true
        view.addSubview(progressLabel)

        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.setTitle("Start Recording", for: .normal)
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.backgroundColor = .systemRed
        recordButton.layer.cornerRadius = 32
        recordButton.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)
        view.addSubview(recordButton)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -24),
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -8),
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            recordButton.widthAnchor.constraint(equalToConstant: 180),
            recordButton.heightAnchor.constraint(equalToConstant: 64),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc  func cancelTapped() {
        onCancel?()
        dismiss(animated: true)
    }

     func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupCamera() }
                    else { self?.statusLabel.text = "Camera access denied" }
                }
            }
        default:
            statusLabel.text = "Enable camera in Settings"
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
                DispatchQueue.main.async { self.statusLabel.text = "Camera unavailable" }
                return
            }
            session.addInput(input)

            let movieOut = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieOut) {
                session.addOutput(movieOut)
                self.movieOutput = movieOut
            }
            let videoOut = AVCaptureVideoDataOutput()
            videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOut.setSampleBufferDelegate(self, queue: self.validationQueue)
            if session.canAddOutput(videoOut) {
                session.addOutput(videoOut)
                self.videoDataOutput = videoOut
            }
            self.captureSession = session
            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.previewView.bounds
                self.previewView.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
                if let connection = layer.connection, connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if let connection = self.videoDataOutput?.connection(with: .video), connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                self.ensureOverlay()
            }
            session.startRunning()
        }
    }

    @objc  func recordTapped() {
        guard let movieOutput = movieOutput else { return }
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            recordButton.setTitle("Start Recording", for: .normal)
            recordButton.isEnabled = false
            return
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        recordingURL = temp
        recordingStartTime = CACurrentMediaTime()
        recordButton.setTitle("Stop (5–8s)", for: .normal)
        movieOutput.startRecording(to: temp, recordingDelegate: self)
        progressLabel.isHidden = false
        startProgressTimer()
    }

     func startProgressTimer() {
        func update() {
            let elapsed = CACurrentMediaTime() - recordingStartTime
            progressLabel.text = String(format: "%.1fs", elapsed)
            if elapsed < maxDuration {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: update)
            }
        }
        update()
    }

     func processVideo(url: URL) {
        activityIndicator.startAnimating()
        statusLabel.text = "Processing..."
        progressLabel.isHidden = true
        recordButton.isHidden = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let images = self?.extractAndFilterFrames(from: url) ?? []
            let barcode = self?.firstBarcode(in: images)
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                if images.isEmpty {
                    let alert = UIAlertController(
                        title: "Video not clear enough",
                        message: "Need at least 8 sharp frames. Hold the pack steady in good light and record for a few seconds.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                    self?.recordButton.isHidden = false
                    self?.statusLabel.text = "Try again"
                    return
                }
                self?.onComplete?(images, barcode)
                self?.dismiss(animated: true)
            }
        }
    }

     func extractAndFilterFrames(from url: URL) -> [UIImage] {
        let asset = AVURLAsset(url: url)
        let durationSec = CMTimeGetSeconds(asset.duration)
        guard durationSec >= 1 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        let frameCount = Int(durationSec * targetFPS)
        let step = durationSec / Double(max(1, frameCount))
        let times: [CMTime] = (0..<frameCount).map { CMTime(seconds: Double($0) * step, preferredTimescale: 600) }

        var cgImages: [CGImage] = []
        for t in times {
            if let cg = try? generator.copyCGImage(at: t, actualTime: nil) {
                cgImages.append(cg)
            }
        }

        print("[FrameExtract] Extracted \(cgImages.count) raw frames from \(String(format: "%.1f", durationSec))s video")

        // Phase 1: Quality filter — blur + brightness + edge density
        var passed: [(cg: CGImage, score: Double)] = []
        for cg in cgImages {
            if let score = qualityScore(cg), score > 0.35 {
                passed.append((cg, score))
            }
        }

        print("[FrameExtract] \(passed.count)/\(cgImages.count) passed quality filter")

        if passed.count < 8 {
            print("[FrameExtract] Rejected video: only \(passed.count) sharp frames")
            return []
        }

        // Phase 2: Sort by quality, then pick diverse frames using CLIP embeddings
        let sorted = passed.sorted { $0.score > $1.score }
        let candidates = sorted.map { $0.cg }

        // Phase 3: Diversity selection — uses CLIP cosine similarity to maximize angle coverage
        // The key insight: different viewing angles produce different CLIP vectors,
        // so maximizing cosine distance naturally captures diverse angles.
        let selection = selectDiverse(candidates, maxCount: 25)

        print("[FrameExtract] Selected \(selection.count) diverse frames for training")

        var isolated: [CGImage] = []
        var track = self.pinnedRect
        for cg in selection {
            let sem = DispatchSemaphore(value: 0)
            ProductFingerprintManager.shared.isolateProduct(in: cg, tapInImage: nil, previousRect: track) { crop, rect, _ in
                if let crop {
                    isolated.append(crop)
                    if let rect { track = rect }
                } else {
                    isolated.append(cg)
                }
                sem.signal()
            }
            sem.wait()
        }

        print("[FrameExtract] Isolated \(isolated.count) product crops")
        return isolated.compactMap { compressImage($0, maxDimension: 480) }
    }

    func firstBarcode(in images: [UIImage]) -> String? {
        for image in images.prefix(8) {
            guard let cg = image.cgImage else { continue }
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([request])
            if let payload = request.results?.compactMap({ $0.payloadStringValue }).first(where: { !$0.isEmpty }) {
                return payload
            }
        }
        return nil
    }

    /// Compress a CGImage to a small UIImage for training storage.
     func compressImage(_ cg: CGImage, maxDimension: CGFloat) -> UIImage? {
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let scale = min(maxDimension / max(w, h), 1.0)
        let newSize = CGSize(width: w * scale, height: h * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        // Re-compress as JPEG at 70% quality for small file size
        guard let data = resized?.jpegData(compressionQuality: 0.7),
              let compressed = UIImage(data: data) else { return resized }
        return compressed
    }

     func qualityScore(_ cg: CGImage) -> Double? {
        let ci = CIImage(cgImage: cg)
        let w = cg.width
        let h = cg.height
        guard w > 0, h > 0 else { return nil }
        let context = CIContext()
        // Fix Bug 13: Set inputImage on the filter before reading output
        let monoFilter = CIFilter(name: "CIPhotoEffectMono")
        monoFilter?.setValue(ci, forKey: kCIInputImageKey)
        guard let gray = context.createCGImage(monoFilter?.outputImage ?? ci, from: ci.extent) else { return nil }
        var lapVariance: Double = 0
        if let lap = laplacianVariance(gray) {
            lapVariance = lap
        }
        let brightness = averageBrightness(ci)
        var score: Double = 0

        // Sharpness: Laplacian variance > 100 means in-focus image
        // Slightly blurred (50-100) could still be usable = partial score
        if lapVariance > 100 { score += 0.35 }
        else if lapVariance > 50 { score += 0.15 }

        // Brightness: well-lit frames are more useful for training
        if brightness >= 80 && brightness <= 200 { score += 0.3 }
        else if brightness >= 60 && brightness <= 220 { score += 0.15 }

        // Edge density: different angles produce different edge patterns
        // This helps filter out near-identical static frames
        let edgeDensity = computeEdgeDensity(gray)
        if edgeDensity > 0.05 { score += 0.2 }  // Has meaningful structure
        else if edgeDensity > 0.02 { score += 0.1 }

        // Contrast: higher contrast frames show more detail
        if lapVariance > 200 { score += 0.15 }  // Very sharp = bonus

        return score
    }

    /// Compute edge density using simple gradient magnitude.
    /// Returns fraction of pixels that are "edges" (gradient above threshold).
     func computeEdgeDensity(_ gray: CGImage) -> Double {
        let w = gray.width
        let h = gray.height
        guard w > 2, h > 2 else { return 0 }
        guard let dataProvider = gray.dataProvider,
              let rawData = dataProvider.data else { return 0 }
        let ptr = CFDataGetBytePtr(rawData)!
        let bytesPerRow = gray.bytesPerRow

        var edgePixels = 0
        let total = (w - 2) * (h - 2)
        let threshold: Int = 30  // gradient magnitude threshold

        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let gx = Int(ptr[y * bytesPerRow + x + 1]) - Int(ptr[y * bytesPerRow + x - 1])
                let gy = Int(ptr[(y + 1) * bytesPerRow + x]) - Int(ptr[(y - 1) * bytesPerRow + x])
                let mag = abs(gx) + abs(gy)
                if mag > threshold { edgePixels += 1 }
            }
        }

        return total > 0 ? Double(edgePixels) / Double(total) : 0
    }

     func laplacianVariance(_ gray: CGImage) -> Double? {
        let w = gray.width
        let h = gray.height
        var data = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(gray, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum: Double = 0
        var count = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = Double(data[y * w + x])
                let lap = 4 * c - Double(Int(data[(y - 1) * w + x]) + Int(data[(y + 1) * w + x]) + Int(data[y * w + x - 1]) + Int(data[y * w + x + 1]))
                sum += lap * lap
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : nil
    }

     func averageBrightness(_ ci: CIImage) -> Double {
        let area = CIFilter(name: "CIAreaAverage")!
        area.setValue(ci, forKey: kCIInputImageKey)
        area.setValue(CIVector(cgRect: ci.extent), forKey: kCIInputExtentKey)
        guard let avg = area.outputImage else { return 128 }
        let ctx = CIContext()
        var pixel: [UInt8] = [0, 0, 0, 0]
        ctx.render(avg, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return Double(pixel[0]) * 0.299 + Double(pixel[1]) * 0.587 + Double(pixel[2]) * 0.114
    }

     func selectDiverse(_ images: [CGImage], maxCount: Int) -> [CGImage] {
        guard let extractor = FeatureExtractorProvider.vectorExtractor, images.count > maxCount else {
            return Array(images.prefix(maxCount))
        }
        var vectors: [[Float]] = []
        for cg in images {
            if let v = extractor.extractVector(from: cg) { vectors.append(v) }
            else { vectors.append([Float](repeating: 0, count: extractor.dimension)) }
        }
        var indices: [Int] = [0]
        for _ in 1..<min(maxCount, images.count) {
            var bestIdx = -1
            var bestMaxSim: Float = 2
            for j in 0..<vectors.count where !indices.contains(j) {
                let maxSimToSelected = indices.map { ProductEmbeddingStore.cosineSimilarity(vectors[j], vectors[$0]) }.max() ?? 0
                if maxSimToSelected < bestMaxSim {
                    bestMaxSim = maxSimToSelected
                    bestIdx = j
                }
            }
            if bestIdx >= 0 { indices.append(bestIdx) }
            else { break }
        }
        return indices.sorted().map { images[$0] }
    }

    // MARK: - Real-time validation (blur, brightness, object count)
     func runLiveValidation(on cgImage: CGImage) {
        lastFrame = cgImage
        lastFrameSize = CGSize(width: cgImage.width, height: cgImage.height)
        let (lapVar, brightness) = liveQualityMetrics(cgImage)

        guard !isProcessingOverlay else {
            DispatchQueue.main.async { [weak self] in
                self?.statusLabel.text = self?.liveValidationMessage(blur: lapVar, brightness: brightness, salientCount: self?.liveBoxes.count ?? 0)
            }
            return
        }
        isProcessingOverlay = true
        ProductFingerprintManager.shared.isolateProduct(
            in: cgImage,
            tapInImage: nil,
            previousRect: pinnedRect
        ) { [weak self] _, trackedRect, detections in
            guard let self else { return }
            self.isProcessingOverlay = false
            if let trackedRect, self.pinnedRect != nil {
                self.pinnedRect = trackedRect
            }
            self.liveBoxes = detections
            let message = self.liveValidationMessage(blur: lapVar, brightness: brightness, salientCount: detections.count)
            DispatchQueue.main.async {
                self.statusLabel.text = self.pinnedRect == nil
                    ? "Tap the product to keep only that pack"
                    : message
                self.redrawOverlay()
            }
        }
    }

     func liveQualityMetrics(_ cg: CGImage) -> (lapVariance: Double, brightness: Double) {
        let ci = CIImage(cgImage: cg)
        let w = cg.width
        let h = cg.height
        guard w > 0, h > 0 else { return (0, 128) }
        let context = CIContext()
        // Fix Bug 13: Set inputImage on the filter
        let monoFilter = CIFilter(name: "CIPhotoEffectMono")
        monoFilter?.setValue(ci, forKey: kCIInputImageKey)
        guard let gray = context.createCGImage(monoFilter?.outputImage ?? ci, from: ci.extent) else {
            return (0, averageBrightness(ci))
        }
        let lapVar = laplacianVariance(gray) ?? 0
        return (lapVar, averageBrightness(ci))
    }

     func liveValidationMessage(blur: Double, brightness: Double, salientCount: Int) -> String {
        if blur < 80 {
            return "Hold steady"
        }
        if brightness < 60 {
            return "Move closer / better lighting"
        }
        if brightness > 220 {
            return "Less glare"
        }
        if salientCount == 0 {
            return "Tap the product if no box appears"
        }
        if pinnedRect == nil {
            return "Tap the box on your product"
        }
        return "Good – turn the product slowly"
    }

    private func ensureOverlay() {
        if overlayContainer == nil {
            let container = UIView()
            container.backgroundColor = .clear
            container.isUserInteractionEnabled = true
            container.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleOverlayTap(_:))))
            previewView.addSubview(container)
            overlayContainer = container
        }
        overlayContainer?.frame = previewView.bounds
        previewView.bringSubviewToFront(overlayContainer!)
        view.bringSubviewToFront(statusLabel)
        view.bringSubviewToFront(progressLabel)
        view.bringSubviewToFront(recordButton)
    }

    @objc private func handleOverlayTap(_ gesture: UITapGestureRecognizer) {
        guard lastFrameSize.width > 0, let frame = lastFrame else { return }
        let point = gesture.location(in: overlayContainer)
        let imagePoint = mapViewPoint(point, imageSize: lastFrameSize, from: overlayContainer?.bounds.size ?? .zero)
        if let pinned = pinnedRect, pinned.insetBy(dx: -16, dy: -16).contains(imagePoint) {
            pinnedRect = nil
            redrawOverlay()
            statusLabel.text = "Tap the product to keep only that pack"
            return
        }
        ProductFingerprintManager.shared.isolateProduct(in: frame, tapInImage: imagePoint, previousRect: nil) { [weak self] _, rect, detections in
            DispatchQueue.main.async {
                self?.liveBoxes = detections
                self?.pinnedRect = rect
                self?.statusLabel.text = rect == nil ? "Tap again on the pack" : "Locked – record while turning it"
                self?.redrawOverlay()
            }
        }
    }

    private func redrawOverlay() {
        ensureOverlay()
        overlayContainer?.subviews.forEach { $0.removeFromSuperview() }
        guard let container = overlayContainer, lastFrameSize.width > 0 else { return }
        container.frame = previewView.bounds
        for box in liveBoxes {
            addBox(box.rect, color: box.hasMask ? .systemGreen : .cyan, dashed: true, label: nil, in: container)
        }
        if let pinned = pinnedRect {
            addBox(pinned, color: UIColor(named: "Lime Moss") ?? .systemGreen, dashed: false, label: "Product", in: container)
        }
    }

    private func addBox(_ imageRect: CGRect, color: UIColor, dashed: Bool, label: String?, in container: UIView) {
        let viewRect = mapImageRect(imageRect, imageSize: lastFrameSize, into: container.bounds.size)
        guard viewRect.width > 8, viewRect.height > 8, viewRect.intersects(container.bounds) else { return }
        let box = UIView(frame: viewRect)
        box.backgroundColor = color.withAlphaComponent(0.08)
        box.isUserInteractionEnabled = false
        if dashed {
            let dash = CAShapeLayer()
            dash.strokeColor = color.cgColor
            dash.fillColor = nil
            dash.lineDashPattern = [5, 3]
            dash.lineWidth = 2
            dash.frame = box.bounds
            dash.path = UIBezierPath(roundedRect: box.bounds, cornerRadius: 4).cgPath
            box.layer.addSublayer(dash)
        } else {
            box.layer.borderColor = color.cgColor
            box.layer.borderWidth = 3
            box.layer.cornerRadius = 4
        }
        if let label {
            let caption = UILabel()
            caption.text = " \(label) "
            caption.font = .systemFont(ofSize: 11, weight: .semibold)
            caption.backgroundColor = color.withAlphaComponent(0.92)
            caption.sizeToFit()
            caption.frame = CGRect(x: 0, y: max(0, -18), width: max(box.bounds.width, caption.bounds.width + 6), height: 18)
            box.addSubview(caption)
        }
        container.addSubview(box)
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

    private func mapViewPoint(_ point: CGPoint, imageSize: CGSize, from viewSize: CGSize) -> CGPoint {
        guard imageSize.width > 0, viewSize.width > 0 else { return .zero }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledW = imageSize.width * scale
        let scaledH = imageSize.height * scale
        let offsetX = (viewSize.width - scaledW) / 2
        let offsetY = (viewSize.height - scaledH) / 2
        return CGPoint(x: (point.x - offsetX) / scale, y: (point.y - offsetY) / scale)
    }
}

extension InventoryCaptureVideoViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastValidationTime >= validationInterval else { return }
        lastValidationTime = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext()
        guard let cgImage = ctx.createCGImage(ci, from: ci.extent) else { return }
        runLiveValidation(on: cgImage)
    }
}

extension InventoryCaptureVideoViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {}
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.recordButton.isEnabled = true
            if let error = error {
                self?.statusLabel.text = error.localizedDescription
                return
            }
            let elapsed = CACurrentMediaTime() - (self?.recordingStartTime ?? 0)
            if elapsed < self?.minDuration ?? 5 {
                self?.statusLabel.text = "Record at least 5 seconds. Try again."
                return
            }
            self?.processVideo(url: outputFileURL)
        }
    }
}

/// Still photo: auto-crop the pack, or tap if auto misses.
final class PhotoObjectIsolateViewController: UIViewController {
    private let source: UIImage
    var onPicked: ((UIImage) -> Void)?

    private let imageView = UIImageView()
    private let overlay = UIView()
    private let hint = UILabel()
    private let useButton = UIButton(type: .system)
    private var cgImage: CGImage?
    private var detections: [(rect: CGRect, hasMask: Bool)] = []
    private var selectedRect: CGRect?
    private var selectedCrop: CGImage?

    init(image: UIImage) {
        self.source = image
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Select product"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = source
        imageView.isUserInteractionEnabled = true
        view.addSubview(imageView)

        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = true
        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        imageView.addSubview(overlay)

        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.text = "Finding the product…"
        hint.textColor = .white
        hint.textAlignment = .center
        hint.numberOfLines = 0
        view.addSubview(hint)

        useButton.translatesAutoresizingMaskIntoConstraints = false
        useButton.setTitle("Use product photo", for: .normal)
        useButton.setTitleColor(.white, for: .normal)
        useButton.backgroundColor = UIColor(named: "Lime Moss") ?? .systemGreen
        useButton.layer.cornerRadius = 22
        useButton.addTarget(self, action: #selector(useTapped), for: .touchUpInside)
        view.addSubview(useButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -12),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            hint.bottomAnchor.constraint(equalTo: useButton.topAnchor, constant: -12),
            useButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            useButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            useButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            useButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        cgImage = Self.uprightCGImage(from: source)
        guard let cgImage else {
            hint.text = "Could not read photo"
            return
        }
        ProductFingerprintManager.shared.isolateProduct(in: cgImage, tapInImage: nil, previousRect: nil) { [weak self] crop, rect, detections in
            DispatchQueue.main.async {
                self?.detections = detections
                self?.selectedRect = rect
                self?.selectedCrop = crop
                self?.hint.text = rect == nil
                    ? "Tap the product in the photo"
                    : "Tap another object if this is wrong"
                self?.redraw()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        overlay.frame = imageView.bounds
        redraw()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func useTapped() {
        let out: UIImage
        if let crop = selectedCrop {
            out = UIImage(cgImage: crop)
        } else {
            out = source
        }
        onPicked?(out)
        dismiss(animated: true)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let cgImage else { return }
        let point = gesture.location(in: overlay)
        let imagePoint = mapViewPoint(point, imageSize: CGSize(width: cgImage.width, height: cgImage.height), from: overlay.bounds.size)
        ProductFingerprintManager.shared.isolateProduct(in: cgImage, tapInImage: imagePoint, previousRect: nil) { [weak self] crop, rect, detections in
            DispatchQueue.main.async {
                self?.detections = detections
                self?.selectedRect = rect
                self?.selectedCrop = crop
                self?.hint.text = crop == nil ? "Tap again on the pack" : "Background removed — Use product photo"
                self?.redraw()
            }
        }
    }

    private func redraw() {
        overlay.subviews.forEach { $0.removeFromSuperview() }
        overlay.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let cgImage else { return }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        for box in detections {
            addBox(box.rect, imageSize: imageSize, color: .cyan, dashed: true)
        }
        if let selected = selectedRect {
            addBox(selected, imageSize: imageSize, color: UIColor(named: "Lime Moss") ?? .systemGreen, dashed: false)
        }
    }

    private func addBox(_ imageRect: CGRect, imageSize: CGSize, color: UIColor, dashed: Bool) {
        let viewRect = mapImageRect(imageRect, imageSize: imageSize, into: overlay.bounds.size)
        let box = UIView(frame: viewRect)
        box.backgroundColor = color.withAlphaComponent(0.08)
        box.isUserInteractionEnabled = false
        box.layer.borderColor = color.cgColor
        box.layer.borderWidth = dashed ? 1.5 : 3
        overlay.addSubview(box)
    }

    private func displayedImageRect(imageSize: CGSize, in viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2, width: w, height: h)
    }

    private func mapImageRect(_ imageRect: CGRect, imageSize: CGSize, into viewSize: CGSize) -> CGRect {
        let fitted = displayedImageRect(imageSize: imageSize, in: viewSize)
        let sx = fitted.width / imageSize.width
        let sy = fitted.height / imageSize.height
        return CGRect(
            x: fitted.minX + imageRect.origin.x * sx,
            y: fitted.minY + imageRect.origin.y * sy,
            width: imageRect.width * sx,
            height: imageRect.height * sy
        )
    }

    private func mapViewPoint(_ point: CGPoint, imageSize: CGSize, from viewSize: CGSize) -> CGPoint {
        let fitted = displayedImageRect(imageSize: imageSize, in: viewSize)
        guard fitted.width > 0 else { return .zero }
        return CGPoint(
            x: (point.x - fitted.minX) / fitted.width * imageSize.width,
            y: (point.y - fitted.minY) / fitted.height * imageSize.height
        )
    }

    static func uprightCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }

    static func present(from host: UIViewController, image: UIImage, onPicked: @escaping (UIImage) -> Void) {
        let vc = PhotoObjectIsolateViewController(image: image)
        vc.onPicked = onPicked
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        host.present(nav, animated: true)
    }
}
