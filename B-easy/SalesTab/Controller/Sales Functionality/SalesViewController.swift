
import UIKit
import SwiftUI
import Speech
import AVFoundation

class SalesViewController: UIViewController {

    // Storyboard outlets — kept so IB connections don't break even though
    // the SwiftUI view replaces the visual UI.
    @IBOutlet weak var addEntryButton: UIButton!
    @IBOutlet weak var tableView: UITableView!

    private var hostingController: UIHostingController<SalesTabView>?

    // MARK: - Inline Voice Recording Properties (copied from VoiceEntryViewController)

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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all

        // Hide the storyboard-provided table and button — SwiftUI replaces them.
        tableView?.isHidden = true
        addEntryButton?.isHidden = true

        embedSwiftUIView()

        // Request speech permissions early
        SFSpeechRecognizer.requestAuthorization { _ in }
        WhisperService.shared.preloadModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // Refresh data each time the tab appears (e.g. after adding a sale).
        hostingController?.rootView.reload()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Reset the transcription state after the view has transitioned away
        self.onTranscriptionUpdate?("")
        self.onListeningStateChanged?(false)
    }

    // MARK: - SwiftUI Hosting

    private func embedSwiftUIView() {
        let salesView = SalesTabView(actions: SalesNavigationActions(
            onManualEntry: { [weak self] in self?.openManualSalesEntry() },
            onVoiceEntry: { [weak self] in self?.toggleInlineRecording() },
            onScanEntry: { [weak self] in self?.openScannedSalesEntry() },
            onRevenueTapped: { [weak self] in self?.openRevenue() },
            onProfitTapped: { [weak self] in self?.openProfit() },
            onTransactionTapped: { [weak self] tx in self?.presentBillSheet(for: tx) }
        ), onTranscriptionUpdate: { [weak self] callback in
            self?.onTranscriptionUpdate = callback
        }, onListeningStateChanged: { [weak self] callback in
            self?.onListeningStateChanged = callback
        })

        let host = UIHostingController(rootView: salesView)
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

    private func openManualSalesEntry() {
        performSegue(withIdentifier: "manual_sales", sender: nil)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        // Hide tab bar for ALL pushed sub-screens
        segue.destination.hidesBottomBarWhenPushed = true

        if segue.identifier == "manual_sales", let result = sender as? ParsedResult {
            if let dest = segue.destination as? SalesEntryTableViewController {
                dest.pendingResult = result
                dest.entryMode = .voice
            }
        }
    }

    private func openScannedSalesEntry() {
        let scanVC = SalesScanCameraViewController.instantiate(mode: .sale)
        scanVC.onSaleResult = { [weak self] result in
            guard let self = self else { return }
            guard let storyboard = self.storyboard,
                  let salesEntryVC = storyboard.instantiateViewController(withIdentifier: "SalesEntryTableViewController") as? SalesEntryTableViewController else { return }
            salesEntryVC.pendingResult = result
            salesEntryVC.entryMode = .camera
            salesEntryVC.hidesBottomBarWhenPushed = true
            self.navigationController?.pushViewController(salesEntryVC, animated: true)
        }
        scanVC.modalPresentationStyle = .fullScreen
        present(scanVC, animated: true)
    }

    private func openRevenue() {
        performSegue(withIdentifier: "revenue_segue", sender: nil)
    }

    private func openProfit() {
        performSegue(withIdentifier: "profit_segue", sender: nil)
    }

    // MARK: - IBActions (kept for any remaining storyboard connections)

    @IBAction func addEntryTapped(_ sender: UIButton) {
        // Fallback — the SwiftUI buttons handle navigation now,
        // but keep this in case the storyboard button is still wired.
        openManualSalesEntry()
    }

    @IBAction func salesScanButtonTapped(_ sender: UIButton) {
        openScannedSalesEntry()
    }

    @IBAction func manualSalesEntryTapped(_ sender: UIButton) {
        openManualSalesEntry()
    }

    @IBAction func voiceEntryTapped(_ sender: UIButton) {
        toggleInlineRecording()
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
        print("\n[SalesInlineVoice] ═══ startInlineListening() ═══")
        print("[SalesInlineVoice] WhisperService.isReady=\(WhisperService.shared.isReady)")

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
            print("[SalesInlineVoice] ✅ Audio session configured")
        } catch {
            print("[SalesInlineVoice] ❌ Audio session setup FAILED: \(error)")
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

                // We intentionally do not update the UI with live transcription here.
                // The UI will remain showing "Listening..." as set in toggleInlineRecording.
            }

            if let error = error {
                print("[SalesInlineVoice] ⚠️ SFSpeech error: \(error.localizedDescription)")
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
            print("[SalesInlineVoice] ✅ Audio engine started")
        } catch {
            print("[SalesInlineVoice] ❌ Audio engine start FAILED: \(error)")
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

        print("\n[SalesInlineVoice] ═══ stopListeningAndProcessImmediate() ═══")
        print("[SalesInlineVoice] recordingDuration=\(String(format: "%.2f", recordingDuration))s")
        print("[SalesInlineVoice] sfSpeechText='\(sfSpeechText)'")
        print("[SalesInlineVoice] whisperAudioFrames=\(audioFrames.count) | duration=\(String(format: "%.2f", whisperAudioDuration))s")

        stopListening()

        DispatchQueue.main.async {
            self.onTranscriptionUpdate?("Understanding...")
        }

        if isMostlySilence {
            print("[SalesInlineVoice] ⏭️ Audio is mostly silence — skipping Whisper")
            DispatchQueue.main.async {
                if Self.isUsableRecognizedText(sfSpeechText) {
                    self.processFinalTextAndNavigate(sfSpeechText)
                } else {
                    self.onTranscriptionUpdate?("Could not understand speech. Please try again.")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.onTranscriptionUpdate?("")
                    }
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
                        print("[SalesInlineVoice] Whisper hallucination detected: \(whisperText)")
                        useWhisper = false
                    }
                }

                if useWhisper, let whisperText = whisperResult, !whisperText.isEmpty {
                    print("[SalesInlineVoice] ✅ USING WHISPER: '\(whisperText)'")
                    self.processFinalTextAndNavigate(whisperText)

                } else if Self.isUsableRecognizedText(sfSpeechText) {
                    print("[SalesInlineVoice] 🔀 USING SFSPEECH FALLBACK: '\(sfSpeechText)'")
                    self.processFinalTextAndNavigate(sfSpeechText)

                } else {
                    print("[SalesInlineVoice] ❌ Both Whisper and SFSpeech failed")
                    self.onTranscriptionUpdate?("Could not understand speech. Please try again.")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.onTranscriptionUpdate?("")
                    }
                }
            }
        }
    }

    // MARK: - Process & Navigate (same as VoiceEntryViewController)

    private func processFinalTextAndNavigate(_ text: String) {
        guard Self.isUsableRecognizedText(text) else { return }

        print("\n[SalesInlineVoice] ═══ processFinalTextAndNavigate ═══")
        print("[SalesInlineVoice] Gemini status: isConfigured=\(GeminiService.shared.isConfigured(for: .voice))")

        if GeminiService.shared.isConfigured(for: .voice) {
            GeminiService.shared.parseVoiceForSale(text: text) { [weak self] geminiResult in
                guard let self = self else { return }
                if let result = geminiResult, !result.products.isEmpty {
                    print("[SalesInlineVoice] ✅ Gemini succeeded: \(result.products.count) items")
                    self.deliverResult(result)
                } else {
                    let result = MLInference.shared.run(text: text)
                    print("[SalesInlineVoice] MLInference result: \(result.products.count) items")
                    self.deliverResult(result)
                }
            }
        } else {
            if GeminiService.shared.hasAPIKey && !UsageTracker.shared.canUse(.voice) {
                showFreemiumLimitAlertIfNeeded()
            }
            let result = MLInference.shared.run(text: text)
            print("[SalesInlineVoice] MLInference result: \(result.products.count) items")
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
            self.performSegue(withIdentifier: "manual_sales", sender: result)
        }
    }

    // MARK: - Audio Helpers

    private static func isUsableRecognizedText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !trimmed.hasPrefix("Listening")
            && !trimmed.hasPrefix("Understanding")
            && !trimmed.hasPrefix("Processing")
            && trimmed != "Say customer, items, quantity or price to add sale"
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
