import UIKit
import Speech
import AVFoundation

class VoicePurchaseEntryViewController: UIViewController {


    @IBOutlet weak var resultLabel: UILabel!
    @IBOutlet weak var micButton: UIButton!
    @IBOutlet weak var tapToSpeakLabel: UILabel!


    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    

    private var whisperAudioFrames: [Float] = []
    private let whisperLock = NSLock()
    

    private var silenceTimer: Timer?
    private var lastSpeechActivity: CFAbsoluteTime = 0
    private var hasHeardSpeech = false
    private let silenceThreshold: Float = 0.015 // Amplitude threshold
    private let maxSilenceDuration: TimeInterval = 2.0 // Stop after 2s silence
    

    private var recordingStartTime: CFAbsoluteTime = 0
    private var bufferCount: Int = 0
    private var whisperFrameCount: Int = 0
    

    private var lastSFSpeechText: String = ""
    private var sfSpeechPartialCount: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        resultLabel.numberOfLines = 0
        resultLabel.lineBreakMode = .byWordWrapping
        resultLabel.adjustsFontSizeToFitWidth = true
        resultLabel.minimumScaleFactor = 0.75
        
        setupMicButton()
        requestPermissions()
        
        WhisperService.shared.preloadModel()
        print("[VoicePurchase] viewDidLoad — WhisperService preload triggered")
    }
    
    private func setupMicButton() {
        micButton?.layer.cornerRadius = 40
        micButton?.clipsToBounds = true
        micButton?.tintColor = .white
    }


    @IBAction func startVoiceTapped(_ sender: UIButton) {
        if audioEngine.isRunning {

             stopListeningAndProcessImmediate()
        } else {
            startListening()
        }
    }
    

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                if status != .authorized {
                    self.resultLabel.text = "Speech permission not granted"
                }
            }
        }
    }


    private func startListening() {
        print("\n[VoicePurchase] ═══ startListening() ═══")
        print("[VoicePurchase] WhisperService.isReady=\(WhisperService.shared.isReady)")
        
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
        startSilenceTimer()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .spokenAudio, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("[VoicePurchase] ✅ Audio session configured (record/spokenAudio)")
        } catch {
            print("[VoicePurchase] ❌ Audio session setup FAILED: \(error)")
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            return
        }


        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            print("[VoicePurchase] ⚠️ Invalid input format (sampleRate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount))")
            DispatchQueue.main.async {
                self.resultLabel.text = "Microphone unavailable"
                self.stopListening()
            }
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) {
            [weak self] result, error in
            guard let self = self else { return }

            if let result {
                let spokenText = result.bestTranscription.formattedString
                self.sfSpeechPartialCount += 1
                self.lastSFSpeechText = spokenText
                
                self.lastSpeechActivity = CFAbsoluteTimeGetCurrent()
                self.hasHeardSpeech = true
                
                // Real-time update from SFSpeech (live visual feedback)
                // DispatchQueue.main.async {
                //     self.resultLabel.text = spokenText
                // }
                
                if self.sfSpeechPartialCount % 5 == 0 || result.isFinal {
                    let elapsed = CFAbsoluteTimeGetCurrent() - self.recordingStartTime
                }
            }

            if let error = error {
                print("[VoicePurchase] ⚠️ SFSpeech recognition error: \(error.localizedDescription)")
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
                

                for i in stride(from: 0, to: frameLength, by: 10) {
                    let absAmp = abs(channelPointer[i])
                    if absAmp > maxAmp { maxAmp = absAmp }
                }
                
                if maxAmp > self.silenceThreshold {
                    self.hasHeardSpeech = true
                    self.lastSpeechActivity = CFAbsoluteTimeGetCurrent()
                self.hasHeardSpeech = true
                }
            }
            

            recognitionRequest.append(buffer)
            

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
            print("[VoicePurchase] ✅ Audio engine started")
        } catch {
            print("[VoicePurchase] ❌ Audio engine start FAILED: \(error)")
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
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, self.audioEngine.isRunning, self.hasHeardSpeech else { return }
            let quietFor = CFAbsoluteTimeGetCurrent() - self.lastSpeechActivity
            guard quietFor >= self.maxSilenceDuration else { return }
            self.stopListeningAndProcessImmediate()
        }
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
        
        let (rmsEnergy, peakEnergy) = Self.audioEnergy(audioFrames)
        let hasRecognizedSpeech = Self.isUsableRecognizedText(sfSpeechText)
        let isMostlySilence = !hasRecognizedSpeech && (audioFrames.isEmpty || (rmsEnergy < 0.0006 && peakEnergy < 0.015))
        
        print("\n[VoicePurchase] ═══ stopListeningAndProcessImmediate() ═══")
        print("[VoicePurchase] recordingDuration=\(String(format: "%.2f", recordingDuration))s")
        print("[VoicePurchase] sfSpeechText='\(sfSpeechText)'")
        print("[VoicePurchase] whisperAudioFrames=\(audioFrames.count) | duration=\(String(format: "%.2f", whisperAudioDuration))s")
        print("[VoicePurchase] rmsEnergy=\(String(format: "%.5f", rmsEnergy)) peak=\(String(format: "%.5f", peakEnergy)) | isMostlySilence=\(isMostlySilence)")
        
        stopListening()
        
        // Show processing indicator
        DispatchQueue.main.async {
            self.resultLabel.text = "Understanding..."
            self.micButton?.isEnabled = false
            self.tapToSpeakLabel?.text = "Understanding..."
        }
        
        if isMostlySilence {
            print("[VoicePurchase] ⏭️ Audio is mostly silence — skipping Whisper")
            DispatchQueue.main.async {
                self.micButton?.isEnabled = true
                self.tapToSpeakLabel?.text = "Tap to Speak"
                if Self.isUsableRecognizedText(sfSpeechText) {
                    self.resultLabel.text = sfSpeechText
                    self.processFinalTextAndNavigate(sfSpeechText)
                } else {
                    self.resultLabel.text = "Could not understand speech. Please try again."
                }
            }
            return
        }
        
        Task {
            let whisperStart = CFAbsoluteTimeGetCurrent()
            let whisperResult = await WhisperService.shared.transcribe(audioFrames: audioFrames)
            let whisperTime = CFAbsoluteTimeGetCurrent() - whisperStart
            print("[VoicePurchase] Whisper transcribe returned in \(String(format: "%.2f", whisperTime))s | chars=\(whisperResult?.count ?? 0)")
            
            await MainActor.run {
                self.micButton?.isEnabled = true
                self.tapToSpeakLabel?.text = "Tap to Speak"
                
                var useWhisper = true

                if useWhisper, let whisperText = whisperResult {
                    // Hallucination Check: verify Whisper output makes sense
                    if WhisperService.shared.isGarbageTranscription(whisperText, duration: whisperAudioDuration) {
                        print("[VoicePurchase] Whisper hallucination detected: \(whisperText)")
                        useWhisper = false
                    }
                }
                
                if useWhisper, let whisperText = whisperResult, !whisperText.isEmpty {
                    print("[VoicePurchase] ✅ USING WHISPER: '\(whisperText)'")
                    self.resultLabel.text = whisperText
                    
                    let parseStart = CFAbsoluteTimeGetCurrent()
                    self.processFinalTextAndNavigate(whisperText)
                    let parseTime = CFAbsoluteTimeGetCurrent() - parseStart
                    
                    let totalTime = CFAbsoluteTimeGetCurrent() - stopTime
                    print("[VoicePurchase] Total processing completed in \(String(format: "%.2f", totalTime))s (parse=\(String(format: "%.2f", parseTime))s)")
                    
                } else if Self.isUsableRecognizedText(sfSpeechText) {
                    print("[VoicePurchase] 🔀 USING SFSPEECH FALLBACK: '\(sfSpeechText)'")
                    self.resultLabel.text = sfSpeechText
                    
                    let parseStart = CFAbsoluteTimeGetCurrent()
                    self.processFinalTextAndNavigate(sfSpeechText)
                    let parseTime = CFAbsoluteTimeGetCurrent() - parseStart
                    
                    let totalTime = CFAbsoluteTimeGetCurrent() - stopTime
                    print("[VoicePurchase] Total processing completed in \(String(format: "%.2f", totalTime))s (parse=\(String(format: "%.2f", parseTime))s)")
                    
                } else {
                    print("[VoicePurchase] ❌ Both Whisper and SFSpeech failed — no usable text")
                    self.resultLabel.text = "Could not understand speech. Please try again."
                }
            }
        }
    }
    

    var onItemsParsed: ((ParsedResult) -> Void)?
    

    private func processFinalTextAndNavigate(_ text: String) {
        guard Self.isUsableRecognizedText(text) else {
            return
        }
        
        print("\n[VoicePurchase] ═══════════════════════════════════════")
        print("[VoicePurchase] processFinalTextAndNavigate | chars=\(text.count)")
        print("[VoicePurchase] Gemini status: isConfigured=\(GeminiService.shared.isConfigured(for: .voice)), hasAPIKey=\(GeminiService.shared.hasAPIKey), isLimitReached=\(GeminiService.shared.isLimitReached)")
        

        if GeminiService.shared.isConfigured(for: .voice) {
            print("[VoicePurchase] ✅ Trying Gemini for: \(text)")
            GeminiService.shared.parseVoiceForPurchase(text: text) { [weak self] geminiResult in
                guard let self = self else { return }
                
                if let result = geminiResult, !result.products.isEmpty {
                    print("[VoicePurchase] ✅ Gemini succeeded: \(result.products.count) items")
                    for (i, p) in result.products.enumerated() {
                        print("[VoicePurchase]   \(i+1). \(p.name) | qty=\(p.quantity) | price=\(p.price ?? "nil") | costPrice=\(p.costPrice ?? "nil") | unit=\(p.unit ?? "nil")")
                    }
                    print("[VoicePurchase] ═══════════════════════════════════════\n")
                    self.deliverResult(result)
                } else {
                    print("[VoicePurchase] ❌ Gemini failed or empty, falling back to MLInference")
                    let result = MLInference.shared.run(text: text)
                    print("[VoicePurchase] MLInference result: \(result.products.count) items")
                    for (i, p) in result.products.enumerated() {
                        print("[VoicePurchase]   \(i+1). \(p.name) | qty=\(p.quantity) | price=\(p.price ?? "nil") | costPrice=\(p.costPrice ?? "nil") | unit=\(p.unit ?? "nil")")
                    }
                    print("[VoicePurchase] ═══════════════════════════════════════\n")
                    self.deliverResult(result)
                }
            }
        } else {
            print("[VoicePurchase] ⚠️ Gemini NOT configured — using MLInference only")
            // Show one-time alert if user just hit their Gemini limit
            if GeminiService.shared.hasAPIKey && !UsageTracker.shared.canUse(.voice) {
                print("[VoicePurchase] ⚠️ Reason: voice AI limit reached")
                showFreemiumLimitAlertIfNeeded()
            }

            let result = MLInference.shared.run(text: text)
            print("[VoicePurchase] MLInference result: \(result.products.count) items")
            for (i, p) in result.products.enumerated() {
                print("[VoicePurchase]   \(i+1). \(p.name) | qty=\(p.quantity) | price=\(p.price ?? "nil") | costPrice=\(p.costPrice ?? "nil") | unit=\(p.unit ?? "nil")")
            }
            print("[VoicePurchase] ═══════════════════════════════════════\n")
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

