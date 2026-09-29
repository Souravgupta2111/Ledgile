import UIKit
import SwiftUI
import Speech
import AVFoundation

class StockViewController: UIViewController {

    @IBOutlet private weak var tableView: UITableView!
    
    private var hostingController: UIHostingController<StockTabView>?

    // MARK: - Inline Voice Recording Properties (copied from VoicePurchaseEntryViewController)

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var whisperAudioFrames: [Float] = []
    private let whisperLock = NSLock()

    private var silenceTimer: Timer?
    private var lastSpeechActivity: CFAbsoluteTime = 0
    private var hasHeardSpeech = false
    private let silenceThreshold: Float = 0.015
    private let maxSilenceDuration: TimeInterval = 2.0

    private var recordingStartTime: CFAbsoluteTime = 0
    private var bufferCount: Int = 0
    private var whisperFrameCount: Int = 0

    private var lastSFSpeechText: String = ""
    private var sfSpeechPartialCount: Int = 0

    /// Callback to update the SwiftUI view's transcription text and listening state.
    private var onTranscriptionUpdate: ((String) -> Void)?
    private var onListeningStateChanged: ((Bool) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView?.isHidden = true
        embedSwiftUIView()

        // Request speech permissions early
        SFSpeechRecognizer.requestAuthorization { _ in }
        WhisperService.shared.preloadModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh data when the view appears
    }

    private func embedSwiftUIView() {
        let stockView = StockTabView(actions: StockNavigationActions(
            onManualEntry: { [weak self] in self?.openManualPurchaseEntry() },
            onVoiceEntry: { [weak self] in self?.toggleInlineRecording() },
            onScanEntry: { [weak self] in self?.openPurchaseScanner() },
            onItemTapped: { [weak self] item in self?.openItemProfile(for: item) },
            onPurchaseTapped: { [weak self] in self?.openPurchaseHistory() },
            onLowStockTapped: { [weak self] in self?.openLowStock() },
            onExpiryTapped: { [weak self] in self?.openExpiry() }
        ), onTranscriptionUpdate: { [weak self] callback in
            self?.onTranscriptionUpdate = callback
        }, onListeningStateChanged: { [weak self] callback in
            self?.onListeningStateChanged = callback
        })

        let host = UIHostingController(rootView: stockView)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear

        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        hostingController = host
    }

    // MARK: - Navigation Actions

    private func openManualPurchaseEntry() {
        performSegue(withIdentifier: "AddPurchaseFromStock", sender: nil)
    }

    private func openPurchaseHistory() {
        performSegue(withIdentifier: "purchase_segue", sender: nil)
    }

    private func openLowStock() {
        performSegue(withIdentifier: "low_stock_from_stock", sender: nil)
    }

    private func openExpiry() {
        performSegue(withIdentifier: "expiry_segue", sender: nil)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        // Hide tab bar for ALL pushed sub-screens
        segue.destination.hidesBottomBarWhenPushed = true

        if segue.identifier == "item_profile" {
            if let dest = segue.destination as? ItemProfileTableViewController, let item = sender as? Item {
                dest.item = item
            }
        }
    }

    private func openPurchaseScanner() {
        let scanVC = PurchaseScanCameraViewController.instantiate(mode: .purchase)
        scanVC.onPurchaseResult = { [weak self] result in
            guard let self = self else { return }
            guard let storyboard = self.storyboard,
                  let purchaseVC = storyboard.instantiateViewController(withIdentifier: "AddPurchaseViewController") as? AddPurchaseViewController else { return }
            purchaseVC.pendingPurchaseResult = result
            purchaseVC.entryMode = .camera
            purchaseVC.hidesBottomBarWhenPushed = true
            self.navigationController?.pushViewController(purchaseVC, animated: true)
        }
        scanVC.modalPresentationStyle = .fullScreen
        present(scanVC, animated: true)
    }

    private func openItemProfile(for item: Item) {
        performSegue(withIdentifier: "item_profile", sender: item)
    }

    // MARK: - Inline Voice Recording

    private func toggleInlineRecording() {
        if audioEngine.isRunning {
            stopListeningAndProcessImmediate()
        } else {
            startInlineListening()
        }
    }

    private func startInlineListening() {
        print("\n[StockInlineVoice] ═══ startInlineListening() ═══")
        print("[StockInlineVoice] WhisperService.isReady=\(WhisperService.shared.isReady)")

        recognitionTask?.cancel()
        recognitionTask = nil

        whisperLock.lock()
        whisperAudioFrames.removeAll()
        whisperLock.unlock()
        bufferCount = 0
        whisperFrameCount = 0
        sfSpeechPartialCount = 0
        lastSFSpeechText = ""
        recordingStartTime = CFAbsoluteTimeGetCurrent()
        lastSpeechActivity = 0
        hasHeardSpeech = false
        startSilenceTimer()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .spokenAudio, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("[StockInlineVoice] ✅ Audio session configured")
        } catch {
            print("[StockInlineVoice] ❌ Audio session setup FAILED: \(error)")
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inventoryItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        let itemNames = inventoryItems.map { $0.name }
        if !itemNames.isEmpty {
            recognitionRequest.contextualStrings = itemNames
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) {
            [weak self] result, error in
            guard let self = self else { return }

            if let result {
                let spokenText = result.bestTranscription.formattedString
                self.sfSpeechPartialCount += 1
                self.lastSFSpeechText = spokenText

                self.lastSpeechActivity = CFAbsoluteTimeGetCurrent()
                self.hasHeardSpeech = true

                // Update SwiftUI caption with live transcription
                DispatchQueue.main.async {
                    self.onTranscriptionUpdate?(spokenText)
                }
            }

            if let error = error {
                print("[StockInlineVoice] ⚠️ SFSpeech error: \(error.localizedDescription)")
            }
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self = self else { return }

            self.bufferCount += 1

            if let channelData = buffer.floatChannelData {
                let channelPointer = channelData[0]
                let frameLength = Int(buffer.frameLength)
                var maxAmp: Float = 0
                for i in stride(from: 0, to: frameLength, by: 10) {
                    let absAmp = abs(channelPointer[i])
                    if absAmp > maxAmp { maxAmp = absAmp }
                }
                if maxAmp > self.silenceThreshold {
                    self.hasHeardSpeech = true
                    self.lastSpeechActivity = CFAbsoluteTimeGetCurrent()
                }
            }

            recognitionRequest.append(buffer)

            if let frames = WhisperService.convertBufferToFrames(buffer) {
                self.whisperLock.lock()
                self.whisperAudioFrames.append(contentsOf: frames)
                self.whisperFrameCount += frames.count
                self.whisperLock.unlock()
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("[StockInlineVoice] ✅ Audio engine started")
        } catch {
            print("[StockInlineVoice] ❌ Audio engine start FAILED: \(error)")
        }

        DispatchQueue.main.async {
            self.onListeningStateChanged?(true)
            self.onTranscriptionUpdate?("Listening...")
        }
    }

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, self.audioEngine.isRunning, self.hasHeardSpeech else { return }
            let quietFor = CFAbsoluteTimeGetCurrent() - self.lastSpeechActivity
            guard quietFor >= self.maxSilenceDuration else { return }
            self.stopListeningAndProcessImmediate()
        }
    }

    private func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
        }

        recognitionRequest = nil
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        DispatchQueue.main.async {
            self.onListeningStateChanged?(false)
        }
    }

    private func stopListeningAndProcessImmediate() {
        let stopTime = CFAbsoluteTimeGetCurrent()
        let recordingDuration = stopTime - recordingStartTime
        let sfSpeechText = lastSFSpeechText

        whisperLock.lock()
        let audioFrames = whisperAudioFrames
        whisperAudioFrames.removeAll()
        whisperLock.unlock()

        let whisperAudioDuration = Double(audioFrames.count) / 16000.0

        let (rmsEnergy, peakEnergy) = Self.audioEnergy(audioFrames)
        let hasRecognizedSpeech = Self.isUsableRecognizedText(sfSpeechText)
        let isMostlySilence = !hasRecognizedSpeech && (audioFrames.isEmpty || (rmsEnergy < 0.0006 && peakEnergy < 0.015))

        print("\n[StockInlineVoice] ═══ stopListeningAndProcessImmediate() ═══")
        print("[StockInlineVoice] recordingDuration=\(String(format: "%.2f", recordingDuration))s")
        print("[StockInlineVoice] sfSpeechText='\(sfSpeechText)'")
        print("[StockInlineVoice] whisperAudioFrames=\(audioFrames.count) | duration=\(String(format: "%.2f", whisperAudioDuration))s")

        stopListening()

        DispatchQueue.main.async {
            self.onTranscriptionUpdate?("Understanding...")
        }

        if isMostlySilence {
            print("[StockInlineVoice] ⏭️ Audio is mostly silence — skipping Whisper")
            DispatchQueue.main.async {
                if Self.isUsableRecognizedText(sfSpeechText) {
                    self.onTranscriptionUpdate?(sfSpeechText)
                    self.processFinalTextAndNavigate(sfSpeechText)
                } else {
                    self.onTranscriptionUpdate?("Could not understand speech. Please try again.")
                }
            }
            return
        }

        Task {
            let whisperResult = await WhisperService.shared.transcribe(audioFrames: audioFrames)

            await MainActor.run {
                var useWhisper = true

                if useWhisper, let whisperText = whisperResult {
                    if WhisperService.shared.isGarbageTranscription(whisperText, duration: whisperAudioDuration) {
                        print("[StockInlineVoice] Whisper hallucination detected: \(whisperText)")
                        useWhisper = false
                    }
                }

                if useWhisper, let whisperText = whisperResult, !whisperText.isEmpty {
                    print("[StockInlineVoice] ✅ USING WHISPER: '\(whisperText)'")
                    self.onTranscriptionUpdate?(whisperText)
                    self.processFinalTextAndNavigate(whisperText)

                } else if Self.isUsableRecognizedText(sfSpeechText) {
                    print("[StockInlineVoice] 🔀 USING SFSPEECH FALLBACK: '\(sfSpeechText)'")
                    self.onTranscriptionUpdate?(sfSpeechText)
                    self.processFinalTextAndNavigate(sfSpeechText)

                } else {
                    print("[StockInlineVoice] ❌ Both Whisper and SFSpeech failed")
                    self.onTranscriptionUpdate?("Could not understand speech. Please try again.")
                }
            }
        }
    }

    // MARK: - Process & Navigate (same as VoicePurchaseEntryViewController)

    private func processFinalTextAndNavigate(_ text: String) {
        guard Self.isUsableRecognizedText(text) else { return }

        print("\n[StockInlineVoice] ═══ processFinalTextAndNavigate ═══")
        print("[StockInlineVoice] Gemini status: isConfigured=\(GeminiService.shared.isConfigured(for: .voice))")

        if GeminiService.shared.isConfigured(for: .voice) {
            GeminiService.shared.parseVoiceForPurchase(text: text) { [weak self] geminiResult in
                guard let self = self else { return }
                if let result = geminiResult, !result.products.isEmpty {
                    print("[StockInlineVoice] ✅ Gemini succeeded: \(result.products.count) items")
                    self.deliverResult(result)
                } else {
                    let result = MLInference.shared.run(text: text)
                    print("[StockInlineVoice] MLInference result: \(result.products.count) items")
                    self.deliverResult(result)
                }
            }
        } else {
            if GeminiService.shared.hasAPIKey && !UsageTracker.shared.canUse(.voice) {
                showFreemiumLimitAlertIfNeeded()
            }
            let result = MLInference.shared.run(text: text)
            print("[StockInlineVoice] MLInference result: \(result.products.count) items")
            deliverResult(result)
        }
    }

    private static var didShowFreemiumAlert = false
    private func showFreemiumLimitAlertIfNeeded() {
        guard !Self.didShowFreemiumAlert else { return }
        Self.didShowFreemiumAlert = true

        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: UsageTracker.shared.isProUser ? "Voice AI limit reached" : "Free AI Scans Used Up",
                message: UsageTracker.shared.limitReachedMessage(for: .voice),
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

    private func deliverResult(_ result: ParsedResult) {
        DispatchQueue.main.async {
            guard let storyboard = self.storyboard,
                  let purchaseVC = storyboard.instantiateViewController(withIdentifier: "AddPurchaseViewController") as? AddPurchaseViewController else { return }
            purchaseVC.pendingResult = result
            purchaseVC.entryMode = .voice
            purchaseVC.hidesBottomBarWhenPushed = true
            self.navigationController?.pushViewController(purchaseVC, animated: true)
        }
    }

    // MARK: - Audio Helpers

    private static func isUsableRecognizedText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !trimmed.hasPrefix("Listening")
            && !trimmed.hasPrefix("Understanding")
            && !trimmed.hasPrefix("Processing")
    }

    private static func audioEnergy(_ frames: [Float]) -> (rms: Float, peak: Float) {
        guard !frames.isEmpty else { return (0, 0) }
        var sumSquares: Float = 0
        var peak: Float = 0
        for sample in frames {
            let absSample = abs(sample)
            sumSquares += sample * sample
            if absSample > peak { peak = absSample }
        }
        return (sqrt(sumSquares / Float(frames.count)), peak)
    }
}
