import UIKit
import Speech
import AVFoundation

class VoicePurchaseEntryViewController: UIViewController {

    // MARK: - UI
    @IBOutlet weak var resultLabel: UILabel!
    @IBOutlet weak var micButton: UIButton!
    @IBOutlet weak var tapToSpeakLabel: UILabel!

    // MARK: - Audio & Speech (SFSpeech for live feedback)
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // MARK: - Whisper Audio Accumulator
    /// Accumulated audio frames (16kHz PCM Float32) for SwiftWhisper final transcription
    private var whisperAudioFrames: [Float] = []
    private let whisperLock = NSLock()
    
    // MARK: - Silence Detection
    private var silenceTimer: Timer?
    private var lastSpeechActivity: CFAbsoluteTime = 0
    private let silenceThreshold: Float = 0.015 // Amplitude threshold
    private let maxSilenceDuration: TimeInterval = 2.0 // Stop after 2s silence
    
    // MARK: - Timing
    private var recordingStartTime: CFAbsoluteTime = 0
    private var bufferCount: Int = 0
    private var whisperFrameCount: Int = 0
    
    // MARK: - SFSpeech tracking
    private var lastSFSpeechText: String = ""
    private var sfSpeechPartialCount: Int = 0

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupMicButton()
        requestPermissions()
        
        // Preload whisper model in background so it's ready when user starts speaking
        WhisperService.shared.preloadModel()
    }
    
    private func setupMicButton() {
        micButton?.layer.cornerRadius = 40
        micButton?.clipsToBounds = true
        micButton?.tintColor = .white
    }

    // MARK: - Button Action
    @IBAction func startVoiceTapped(_ sender: UIButton) {
        if audioEngine.isRunning {
             // Immediate stop and process
             stopListeningAndProcessImmediate()
        } else {
            startListening()
        }
    }
    
    // MARK: - Permissions
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                if status != .authorized {
                    self.resultLabel.text = "Speech permission not granted"
                }
            }
        }
    }

    // MARK: - Start Listening (Hybrid: SFSpeech for live + Whisper audio accumulation)
    private func startListening() {
        
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
        
        lastSpeechActivity = CFAbsoluteTimeGetCurrent()
        startSilenceTimer()

        // Audio session setup
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            return
        }

        // Enable partial results for live display
        recognitionRequest.shouldReportPartialResults = true

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
                
                // Real-time update from SFSpeech (live visual feedback)
                DispatchQueue.main.async {
                    self.resultLabel.text = spokenText
                }
                
                if self.sfSpeechPartialCount % 5 == 0 || result.isFinal {
                    let elapsed = CFAbsoluteTimeGetCurrent() - self.recordingStartTime
                }
            }

            if let error = error {
            }
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self = self else { return }
            
            self.bufferCount += 1
            
            if let channelData = buffer.floatChannelData {
                let channelPointer = channelData[0] // Mono or Left
                let frameLength = Int(buffer.frameLength)
                var maxAmp: Float = 0
                
                // Quick max scan (stride 10 for performance)
                for i in stride(from: 0, to: frameLength, by: 10) {
                    let absAmp = abs(channelPointer[i])
                    if absAmp > maxAmp { maxAmp = absAmp }
                }
                
                if maxAmp > self.silenceThreshold {
                    self.lastSpeechActivity = CFAbsoluteTimeGetCurrent()
                }
            }
            
            // Feed buffer to SFSpeech for live partial results
            recognitionRequest.append(buffer)
            
            // Simultaneously accumulate audio for Whisper
            if let frames = WhisperService.convertBufferToFrames(buffer) {
                self.whisperLock.lock()
                self.whisperAudioFrames.append(contentsOf: frames)
                self.whisperFrameCount += frames.count
                self.whisperLock.unlock()
            }
            
            if self.bufferCount % 50 == 0 {
                let elapsed = CFAbsoluteTimeGetCurrent() - self.recordingStartTime
                self.whisperLock.lock()
                let totalFrames = self.whisperAudioFrames.count
                self.whisperLock.unlock()
                let whisperDuration = Double(totalFrames) / 16000.0
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
        }

        DispatchQueue.main.async {
            self.resultLabel.text = "Listening..."
            self.micButton?.setImage(UIImage(systemName: "stop.fill"), for: .normal)
            self.micButton?.backgroundColor = .white
            self.micButton?.tintColor = .systemRed
            self.tapToSpeakLabel?.text = "Tap to Stop"
        }
    }
    
    // MARK: - Silence Logic
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
    }

    // MARK: - Stop Listening
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
            self.micButton?.setImage(UIImage(systemName: "microphone.fill"), for: .normal)
            self.micButton?.backgroundColor = .systemRed
            self.micButton?.tintColor = .white
            self.tapToSpeakLabel?.text = "Tap to Speak"
        }
    }
    
    private func stopListeningAndProcessImmediate() {
        let stopTime = CFAbsoluteTimeGetCurrent()
        let recordingDuration = stopTime - recordingStartTime
        let sfSpeechText = lastSFSpeechText
        
        // Grab the accumulated whisper audio
        whisperLock.lock()
        let audioFrames = whisperAudioFrames
        whisperAudioFrames.removeAll()
        whisperLock.unlock()
        
        let whisperAudioDuration = Double(audioFrames.count) / 16000.0
        
        // Quick RMS energy check — if audio is mostly silence, skip Whisper entirely
        let rmsEnergy: Float = {
            guard !audioFrames.isEmpty else { return 0 }
            let sumOfSquares = audioFrames.reduce(Float(0)) { $0 + $1 * $1 }
            return sqrt(sumOfSquares / Float(audioFrames.count))
        }()
        let isMostlySilence = rmsEnergy < 0.005
        
        stopListening()
        
        // Show processing indicator
        DispatchQueue.main.async {
            self.resultLabel.text = "🔄 Processing with Whisper..."
            self.micButton?.isEnabled = false
        }
        
        // If mostly silence, skip Whisper and go straight to SFSpeech or show error
        if isMostlySilence {
            DispatchQueue.main.async {
                self.micButton?.isEnabled = true
                if !sfSpeechText.isEmpty && sfSpeechText != "Listening..." && sfSpeechText != "🔄 Processing with Whisper..." {
                    self.resultLabel.text = sfSpeechText
                    self.processFinalTextAndNavigate(sfSpeechText)
                } else {
                    self.resultLabel.text = "Could not understand speech. Please try again."
                }
            }
            return
        }
        
        // Run Whisper transcription in background, fallback to SFSpeech if it fails or hallucinates
        Task {
            let whisperStart = CFAbsoluteTimeGetCurrent()
            let whisperResult = await WhisperService.shared.transcribe(audioFrames: audioFrames)
            let whisperTime = CFAbsoluteTimeGetCurrent() - whisperStart
            
            await MainActor.run {
                self.micButton?.isEnabled = true
                
                // HYBRID STRATEGY:
                var useWhisper = true
                
                if recordingDuration < 5.0 {
                    if !sfSpeechText.isEmpty {
                        useWhisper = false
                    } else {
                    }
                }
                
                if useWhisper, let whisperText = whisperResult {
                    // Hallucination Check: verify Whisper output makes sense
                    if WhisperService.shared.isGarbageTranscription(whisperText, duration: whisperAudioDuration) {
                        print("[VoicePurchase] Whisper hallucination detected: \(whisperText)")
                        useWhisper = false
                    }
                }
                
                if useWhisper, let whisperText = whisperResult, !whisperText.isEmpty {
                    self.resultLabel.text = whisperText
                    
                    let parseStart = CFAbsoluteTimeGetCurrent()
                    self.processFinalTextAndNavigate(whisperText)
                    let parseTime = CFAbsoluteTimeGetCurrent() - parseStart
                    
                    let totalTime = CFAbsoluteTimeGetCurrent() - stopTime
                    
                } else if !sfSpeechText.isEmpty && sfSpeechText != "Listening..." && sfSpeechText != "🔄 Processing with Whisper..." {
                    self.resultLabel.text = sfSpeechText
                    
                    let parseStart = CFAbsoluteTimeGetCurrent()
                    self.processFinalTextAndNavigate(sfSpeechText)
                    let parseTime = CFAbsoluteTimeGetCurrent() - parseStart
                    
                    let totalTime = CFAbsoluteTimeGetCurrent() - stopTime
                    
                } else {
                    self.resultLabel.text = "Could not understand speech. Please try again."
                }
            }
        }
    }
    
    // MARK: - Navigation / Callbacks
    
    /// Closure to handle parsed results when this VC is presented for appending items
    var onItemsParsed: ((ParsedResult) -> Void)?
    
    // MARK: - Process and Navigate
    private func processFinalTextAndNavigate(_ text: String) {
        guard !text.isEmpty, text != "Listening...", text != "Say customer, items, quantity or price to add sale" else {
            return
        }
        
        // Try Gemini first, fall back to on-device MLInference
        if GeminiService.shared.isConfigured {
            print("[VoicePurchase] Trying Gemini for: \(text)")
            GeminiService.shared.parseVoiceForPurchase(text: text) { [weak self] geminiResult in
                guard let self = self else { return }
                
                if let result = geminiResult, !result.products.isEmpty {
                    print("[VoicePurchase] Gemini succeeded: \(result.products.count) items")
                    self.deliverResult(result)
                } else {
                    print("[VoicePurchase] Gemini failed, falling back to MLInference")
                    let result = MLInference.shared.run(text: text)
                    self.deliverResult(result)
                }
            }
        } else {
            // Show one-time alert if user just hit their Gemini limit
            if GeminiService.shared.hasAPIKey && GeminiService.shared.isLimitReached {
                showFreemiumLimitAlertIfNeeded()
            }
            // No API key or limit reached — use on-device only
            let result = MLInference.shared.run(text: text)
            deliverResult(result)
        }
    }

    /// Shows a one-time alert per app session when the user exhausts their free Gemini scans.
    private static var didShowFreemiumAlert = false
    private func showFreemiumLimitAlertIfNeeded() {
        guard !Self.didShowFreemiumAlert else { return }
        Self.didShowFreemiumAlert = true

        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Free AI Scans Used Up",
                message: UsageTracker.shared.limitReachedMessage,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
    
    /// Deliver parsed result to the next screen (shared by Gemini and MLInference paths).
    private func deliverResult(_ result: ParsedResult) {
        if let onItemsParsed = onItemsParsed {
            onItemsParsed(result)
            DispatchQueue.main.async {
                self.dismiss(animated: true)
            }
        } else {
            // Navigate to AddPurchaseViewController with batch items
            DispatchQueue.main.async {
                self.performSegue(withIdentifier: "VoicePurchaseEntryList", sender: result)
            }
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "VoicePurchaseEntryList",
           let result = sender as? ParsedResult,
           let dest = segue.destination as? AddPurchaseViewController {
            dest.pendingResult = result
            dest.entryMode = .voice
        }
    }
    
    // MARK: - Create Attributed Text with Entity Highlighting
    private func createAttributedText(from result: ParsedResult, originalText: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        
        // Default text attributes
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label
        ]
        
        // Entity color mapping
        let itemColor = UIColor.systemBlue
        let quantityColor = UIColor(named: "Lime Moss")!
        let customerColor = UIColor.systemOrange
        let priceColor = UIColor.systemPurple
        let unitColor = UIColor.systemTeal
        let negationColor = UIColor.systemRed
        let referenceColor = UIColor.systemBrown
        
        for entity in result.entities {
            var attributes = defaultAttributes
            
            switch entity.type {
            case .item:
                attributes[.foregroundColor] = itemColor
            case .quantity:
                attributes[.foregroundColor] = quantityColor
            case .customer:
                attributes[.foregroundColor] = customerColor
            case .price:
                attributes[.foregroundColor] = priceColor
            case .unit:
                attributes[.foregroundColor] = unitColor
            case .negation:
                attributes[.foregroundColor] = negationColor
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case .reference:
                attributes[.foregroundColor] = referenceColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case .sellingPrice, .costPrice:
                attributes[.foregroundColor] = priceColor
            case .supplier:
                attributes[.foregroundColor] = customerColor
            case .discount:
                attributes[.foregroundColor] = UIColor.systemOrange
            case .expiry:
                attributes[.foregroundColor] = UIColor.systemGray
            case .action, .other:
                break
            }
            
            let entityString = NSAttributedString(string: entity.text + " ", attributes: attributes)
            attributedString.append(entityString)
        }
        
        let summaryText = "\n\n📋 Parsed Result:\n"
        attributedString.append(NSAttributedString(string: summaryText, attributes: [
            .font: UIFont.boldSystemFont(ofSize: 15),
            .foregroundColor: UIColor.label
        ]))
        
        // Show negation warning if present
        if result.isNegation {
            attributedString.append(NSAttributedString(string: "⚠️ Cancellation detected\n", attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: negationColor
            ]))
        }
        
        // Show reference indicator if present
        if result.isReference {
            attributedString.append(NSAttributedString(string: "↩️ Reference to previous item\n", attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: referenceColor
            ]))
        }
        
        // Products
        if !result.products.isEmpty {
            attributedString.append(NSAttributedString(string: "Products:\n", attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.secondaryLabel
            ]))
            
            for product in result.products {
                var productText = "  • \(product.name)"
                productText += " (Qty: \(product.quantity)"
                if let unit = product.unit {
                    productText += " \(unit)"
                }
                if let price = product.price {
                    productText += ", ₹\(price)"
                }
                productText += ")\n"
                
                attributedString.append(NSAttributedString(string: productText, attributes: [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: itemColor
                ]))
            }
        }
        
        // Customer
        if let customer = result.customerName {
            let customerText = "Customer: \(customer)\n"
            attributedString.append(NSAttributedString(string: customerText, attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: customerColor
            ]))
        }
        return attributedString
    }
}

