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

    var onComplete: (([UIImage]) -> Void)?
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
    }

     func setupUI() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Record 5–8 seconds while slowly rotating the product"
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
                self.previewView.layer.addSublayer(layer)
                self.previewLayer = layer
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
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.onComplete?(images)
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

        if passed.isEmpty {
            // Fall back to raw frames, still compress
            return cgImages.prefix(15).compactMap { compressImage($0, maxDimension: 480) }
        }

        // Phase 2: Sort by quality, then pick diverse frames using CLIP embeddings
        let sorted = passed.sorted { $0.score > $1.score }
        let candidates = sorted.map { $0.cg }

        // Phase 3: Diversity selection — uses CLIP cosine similarity to maximize angle coverage
        // The key insight: different viewing angles produce different CLIP vectors,
        // so maximizing cosine distance naturally captures diverse angles.
        let selection = selectDiverse(candidates, maxCount: 25)

        print("[FrameExtract] Selected \(selection.count) diverse frames for training")

        return selection.compactMap { compressImage($0, maxDimension: 480) }
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
        let (lapVar, brightness) = liveQualityMetrics(cgImage)
        var salientCount = 0
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        if let result = request.results?.first as? VNSaliencyImageObservation, let objects = result.salientObjects {
            salientCount = objects.count
        }
        let message = liveValidationMessage(blur: lapVar, brightness: brightness, salientCount: salientCount)
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = message
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
            return "Move closer – show one product"
        }
        if salientCount > 1 {
            return "Show exactly 1 product"
        }
        return "Good – keep going"
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
