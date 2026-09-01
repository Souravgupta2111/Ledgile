import UIKit
import Speech
import AVFoundation

class VoiceEntryViewController: UIViewController {

  
    @IBOutlet weak var resultLabel: UILabel!
    @IBOutlet weak var micButton: UIButton!
    @IBOutlet weak var tapToSpeakLabel: UILabel!

    
     let audioEngine = AVAudioEngine()
     let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
     var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
     var recognitionTask: SFSpeechRecognitionTask?
    
   
     var whisperAudioFrames: [Float] = []
     let whisperLock = NSLock()
    
    
     var silenceTimer: Timer?
     var lastSpeechActivity: CFAbsoluteTime = 0
     var hasHeardSpeech = false
     let silenceThreshold: Float = 0.015
     let maxSilenceDuration: TimeInterval = 2.0
    
   
     var recordingStartTime: CFAbsoluteTime = 0
     var bufferCount: Int = 0
     var whisperFrameCount: Int = 0
    

     var lastSFSpeechText: String = ""
     var sfSpeechPartialCount: Int = 0
     
     // MARK: - Whisper Streaming State
     private var whisperTimer: Timer?
     private var isWhisperTranscribing = false    
    override func viewDidLoad() {
        super.viewDidLoad()
        resultLabel.text = "Say customer, items, quantity or price to add sale"
        
        setupMicButton()
        requestPermissions()
        
        WhisperService.shared.preloadModel()
        print("[VoiceSale] viewDidLoad — WhisperService preload triggered")
    }
    
     func setupMicButton() {
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
    
   
     func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                if status != .authorized {
                    self.resultLabel.text = "Speech permission not granted"
                }
            }
        }
    }

    
     func startListening() {
        print("\n[VoiceSale] ═══ startListening() ═══")
        print("[VoiceSale] WhisperService.isReady=\(WhisperService.shared.isReady)")
        
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
        startWhisperStreamingTimer()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .spokenAudio, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("[VoiceSale] ✅ Audio session configured (record/spokenAudio)")
        } catch {
            print("[VoiceSale] ❌ Audio session setup FAILED: \(error)")
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        
        let inventoryItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        let itemNames = inventoryItems.map { $0.name }
        if !itemNames.isEmpty {
            recognitionRequest.contextualStrings = itemNames
            print("[VoiceSale] Injected \(itemNames.count) inventory names into speech context")
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
                
                // DispatchQueue.main.async {
                //     self.resultLabel.text = spokenText
                // }
                
                if self.sfSpeechPartialCount % 5 == 0 || result.isFinal {
                    let elapsed = CFAbsoluteTimeGetCurrent() - self.recordingStartTime
                }
            }

            if let error = error {
                print("[VoiceSale] ⚠️ SFSpeech recognition error: \(error.localizedDescription)")
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
            print("[VoiceSale] ✅ Audio engine started")
        } catch {
            print("[VoiceSale] ❌ Audio engine start FAILED: \(error)")
        }

        DispatchQueue.main.async {
            self.resultLabel.text = "Listening..."
            self.micButton?.setImage(UIImage(systemName: "stop.fill"), for: .normal)
            self.micButton?.backgroundColor = .white
            self.micButton?.tintColor = .systemRed
            self.tapToSpeakLabel?.text = "Tap to Stop"
        }
    }
    

     func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, self.audioEngine.isRunning, self.hasHeardSpeech else { return }
            let quietFor = CFAbsoluteTimeGetCurrent() - self.lastSpeechActivity
            guard quietFor >= self.maxSilenceDuration else { return }
            self.stopListeningAndProcessImmediate()
        }
    }

     func stopListening() {
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
        
        stopWhisperStreamingTimer()
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        
        DispatchQueue.main.async {
            self.micButton?.setImage(UIImage(systemName: "microphone.fill"), for: .normal)
            self.micButton?.backgroundColor = .systemRed
            self.micButton?.tintColor = .white
            self.tapToSpeakLabel?.text = "Tap to Speak"
        }
    }
    
     func stopListeningAndProcessImmediate() {
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
        
        print("\n[VoiceSale] ═══ stopListeningAndProcessImmediate() ═══")
        print("[VoiceSale] recordingDuration=\(String(format: "%.2f", recordingDuration))s")
        print("[VoiceSale] sfSpeechText='\(sfSpeechText)'")
        print("[VoiceSale] whisperAudioFrames=\(audioFrames.count) | duration=\(String(format: "%.2f", whisperAudioDuration))s")
        print("[VoiceSale] rmsEnergy=\(String(format: "%.5f", rmsEnergy)) peak=\(String(format: "%.5f", peakEnergy)) | isMostlySilence=\(isMostlySilence)")
        
        stopListening()
        
        DispatchQueue.main.async {
            self.resultLabel.text = " Processing ..."
            self.micButton?.isEnabled = false
        }
        
        if isMostlySilence {
            print("[VoiceSale] ⏭️ Audio is mostly silence — skipping Whisper")
            DispatchQueue.main.async {
                self.micButton?.isEnabled = true
                if !sfSpeechText.isEmpty && sfSpeechText != "Listening..." && sfSpeechText != "Processing..." {
                    self.resultLabel.text = sfSpeechText
                    self.processFinalTextAndNavigate(sfSpeechText)
                } else {
                    self.resultLabel.text = "Could not understand speech. Please try again."
                }
            }
            return
        }
        
        Task {
            // Wait for any pending background Whisper transcription to finish
            while self.isWhisperTranscribing {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            
            let whisperStart = CFAbsoluteTimeGetCurrent()
            let whisperResult = await WhisperService.shared.transcribe(audioFrames: audioFrames)
            let whisperTime = CFAbsoluteTimeGetCurrent() - whisperStart
            print("[VoiceSale] Whisper transcribe returned in \(String(format: "%.2f", whisperTime))s | chars=\(whisperResult?.count ?? 0)")
            
            await MainActor.run {
                self.micButton?.isEnabled = true
                
                
                var useWhisper = true

                if useWhisper, let whisperText = whisperResult {
                    if WhisperService.shared.isGarbageTranscription(whisperText, duration: whisperAudioDuration) {
                        print("[VoiceSale] Whisper hallucination detected: \(whisperText)")
                        useWhisper = false
                    }
                }
                
                if useWhisper, let whisperText = whisperResult, !whisperText.isEmpty {
                    print("[VoiceSale] ✅ USING WHISPER: '\(whisperText)'")
                    self.resultLabel.text = whisperText
                    
                    let parseStart = CFAbsoluteTimeGetCurrent()
                    self.processFinalTextAndNavigate(whisperText)
                    let parseTime = CFAbsoluteTimeGetCurrent() - parseStart
                    
                    let totalTime = CFAbsoluteTimeGetCurrent() - stopTime
                    
                } else if !sfSpeechText.isEmpty && sfSpeechText != "Listening..." && sfSpeechText != "Processing..." {
                    print("[VoiceSale] 🔀 USING SFSPEECH FALLBACK: '\(sfSpeechText)'")
                    self.resultLabel.text = sfSpeechText
                    
                    let parseStart = CFAbsoluteTimeGetCurrent()
                    self.processFinalTextAndNavigate(sfSpeechText)
                    let parseTime = CFAbsoluteTimeGetCurrent() - parseStart
                    
                    let totalTime = CFAbsoluteTimeGetCurrent() - stopTime
                    
                } else {
                    print("[VoiceSale] ❌ Both Whisper and SFSpeech failed — no usable text")
                    self.resultLabel.text = "Could not understand speech. Please try again."
                }
            }
        }
    }
    
    
    var onItemsParsed: ((ParsedResult) -> Void)?
    
     func processFinalTextAndNavigate(_ text: String) {
        guard !text.isEmpty, text != "Listening...", text != "Say customer, items, quantity or price to add sale" else {
            return
        }
        
        print("\n[VoiceSale] ═══════════════════════════════════════")
        print("[VoiceSale] processFinalTextAndNavigate | chars=\(text.count)")
        print("[VoiceSale] Gemini status: isConfigured=\(GeminiService.shared.isConfigured(for: .voice)), hasAPIKey=\(GeminiService.shared.hasAPIKey), isLimitReached=\(GeminiService.shared.isLimitReached)")
        
        if GeminiService.shared.isConfigured(for: .voice) {
            print("[VoiceSale] ✅ Trying Gemini for: \(text)")
            GeminiService.shared.parseVoiceForSale(text: text) { [weak self] geminiResult in
                guard let self = self else { return }
                
                if let result = geminiResult, !result.products.isEmpty {
                    print("[VoiceSale] ✅ Gemini succeeded: \(result.products.count) items")
                    for (i, p) in result.products.enumerated() {
                        print("[VoiceSale]   \(i+1). \(p.name) | qty=\(p.quantity) | price=\(p.price ?? "nil") | costPrice=\(p.costPrice ?? "nil") | unit=\(p.unit ?? "nil")")
                    }
                    print("[VoiceSale] ═══════════════════════════════════════\n")
                    self.deliverResult(result)
                } else {
                    print("[VoiceSale] ❌ Gemini failed or empty, falling back to MLInference")
                    let result = MLInference.shared.run(text: text)
                    print("[VoiceSale] MLInference result: \(result.products.count) items")
                    for (i, p) in result.products.enumerated() {
                        print("[VoiceSale]   \(i+1). \(p.name) | qty=\(p.quantity) | price=\(p.price ?? "nil") | costPrice=\(p.costPrice ?? "nil") | unit=\(p.unit ?? "nil")")
                    }
                    print("[VoiceSale] ═══════════════════════════════════════\n")
                    self.deliverResult(result)
                }
            }
        } else {
            print("[VoiceSale] ⚠️ Gemini NOT configured — using MLInference only")
            if GeminiService.shared.hasAPIKey && !UsageTracker.shared.canUse(.voice) {
                print("[VoiceSale] ⚠️ Reason: voice AI limit reached")
                showFreemiumLimitAlertIfNeeded()
            }
            let result = MLInference.shared.run(text: text)
            print("[VoiceSale] MLInference result: \(result.products.count) items")
            for (i, p) in result.products.enumerated() {
                print("[VoiceSale]   \(i+1). \(p.name) | qty=\(p.quantity) | price=\(p.price ?? "nil") | costPrice=\(p.costPrice ?? "nil") | unit=\(p.unit ?? "nil")")
            }
            print("[VoiceSale] ═══════════════════════════════════════\n")
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
    
     func deliverResult(_ result: ParsedResult) {
        if let onItemsParsed = onItemsParsed {
            onItemsParsed(result)
            DispatchQueue.main.async {
                self.dismiss(animated: true)
            }
        } else {
            DispatchQueue.main.async {
                self.performSegue(withIdentifier: "ParsedVoiceEntryScreen", sender: result)
            }
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

        if segue.identifier == "ParsedVoiceEntryScreen",
           let result = sender as? ParsedResult,
           let dest = segue.destination as? SalesEntryTableViewController {

            dest.pendingResult = result
            dest.entryMode = .voice
        }
    }
    
     func createAttributedText(from result: ParsedResult, originalText: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        
      
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label
        ]
        
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
        
        let summaryText = "\n\nParsed Result:\n"
        attributedString.append(NSAttributedString(string: summaryText, attributes: [
            .font: UIFont.boldSystemFont(ofSize: 15),
            .foregroundColor: UIColor.label
        ]))
        
      
        if result.isNegation {
            attributedString.append(NSAttributedString(string: " Cancellation detected\n", attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: negationColor
            ]))
        }
        
 
        if result.isReference {
            attributedString.append(NSAttributedString(string: " Reference to previous item\n", attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: referenceColor
            ]))
        }
        
   
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
            && trimmed != "Listening..."
            && trimmed != "Processing..."
            && trimmed != " Processing ..."
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
    
    // MARK: - Whisper Streaming

    private func startWhisperStreamingTimer() {
        whisperTimer?.invalidate()
        isWhisperTranscribing = false
        whisperTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.processWhisperPartial()
        }
    }

    private func stopWhisperStreamingTimer() {
        whisperTimer?.invalidate()
        whisperTimer = nil
    }

    private func processWhisperPartial() {
        guard !isWhisperTranscribing else { return }
        
        whisperLock.lock()
        let audioFrames = whisperAudioFrames
        whisperLock.unlock()

        let whisperAudioDuration = Double(audioFrames.count) / 16000.0
        guard whisperAudioDuration >= 0.3 else { return }

        isWhisperTranscribing = true
        
        Task {
            let result = await WhisperService.shared.transcribe(audioFrames: audioFrames)
            await MainActor.run {
                self.isWhisperTranscribing = false
                if let text = result, !text.isEmpty {
                    // Update UI with Whisper partials if it's not hallucination
                    if !WhisperService.shared.isGarbageTranscription(text, duration: whisperAudioDuration) {
                        // We use Whisper's highly accurate text for the UI to prevent chopped words
                        self.resultLabel.text = text
                    }
                }
            }
        }
    }
}

