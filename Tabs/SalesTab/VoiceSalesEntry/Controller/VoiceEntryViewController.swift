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
     let silenceThreshold: Float = 0.015
     let maxSilenceDuration: TimeInterval = 2.0
    
   
     var recordingStartTime: CFAbsoluteTime = 0
     var bufferCount: Int = 0
     var whisperFrameCount: Int = 0
    

     var lastSFSpeechText: String = ""
     var sfSpeechPartialCount: Int = 0

    
    override func viewDidLoad() {
        super.viewDidLoad()
        resultLabel.text = "Say customer, items, quantity or price to add sale"
        
        setupMicButton()
        requestPermissions()
        
        WhisperService.shared.preloadModel()
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
        
        // Inject inventory names as contextual hints so the speech recognizer
        // biases toward known product names (e.g., "Parle G" instead of "pali g")
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
                let channelPointer = channelData[0]
                let frameLength = Int(buffer.frameLength)
                var maxAmp: Float = 0
                
                for i in stride(from: 0, to: frameLength, by: 10) {
                    let absAmp = abs(channelPointer[i])
                    if absAmp > maxAmp { maxAmp = absAmp }
                }
                
                if maxAmp > self.silenceThreshold {
                    self.lastSpeechActivity = CFAbsoluteTimeGetCurrent()
                }
            }
            
            
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
    

    // MARK: - Stop Listening
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
        
        DispatchQueue.main.async {
            self.resultLabel.text = " Processing ..."
            self.micButton?.isEnabled = false
        }
        
        // If mostly silence, skip Whisper and go straight to SFSpeech or show error
        if isMostlySilence {
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
        
        // Run Whisper transcription in background, fallback to SFSpeech if it fails or hallucinates
        Task {
            let whisperStart = CFAbsoluteTimeGetCurrent()
            let whisperResult = await WhisperService.shared.transcribe(audioFrames: audioFrames)
            let whisperTime = CFAbsoluteTimeGetCurrent() - whisperStart
            
            await MainActor.run {
                self.micButton?.isEnabled = true
                
                
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
                        print("[VoiceSale] Whisper hallucination detected: \(whisperText)")
                        useWhisper = false
                    }
                }
                
                if useWhisper, let whisperText = whisperResult, !whisperText.isEmpty {
                    self.resultLabel.text = whisperText
                    
                    let parseStart = CFAbsoluteTimeGetCurrent()
                    self.processFinalTextAndNavigate(whisperText)
                    let parseTime = CFAbsoluteTimeGetCurrent() - parseStart
                    
                    let totalTime = CFAbsoluteTimeGetCurrent() - stopTime
                    
                } else if !sfSpeechText.isEmpty && sfSpeechText != "Listening..." && sfSpeechText != "Processing..." {
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
    
    
   
    var onItemsParsed: ((ParsedResult) -> Void)?
    
    // MARK: - Process and Navigate
     func processFinalTextAndNavigate(_ text: String) {
        guard !text.isEmpty, text != "Listening...", text != "Say customer, items, quantity or price to add sale" else {
            return
        }
        
        // Try Gemini first, fall back to on-device MLInference
        if GeminiService.shared.isConfigured {
            print("[VoiceSale] Trying Gemini for: \(text)")
            GeminiService.shared.parseVoiceForSale(text: text) { [weak self] geminiResult in
                guard let self = self else { return }
                
                if let result = geminiResult, !result.products.isEmpty {
                    print("[VoiceSale] Gemini succeeded: \(result.products.count) items")
                    self.deliverResult(result)
                } else {
                    print("[VoiceSale] Gemini failed, falling back to MLInference")
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
    
    // Create Attributed Text with Entity Highlighting
     func createAttributedText(from result: ParsedResult, originalText: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        
      
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
}

