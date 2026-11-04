import Foundation
import UIKit
import AVFoundation
import Speech


final class HotwordListener {

    static let shared = HotwordListener()

    // MARK: - Public
    var onHotword: (() -> Void)?

    
    var isListening: Bool { audioEngine.isRunning }

    static let wakeWordKey = "hotword.customWakePhrase"
    static let defaultWakePhrase = "hey b easy"

    
    var wakePhrase: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Self.wakeWordKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return (stored?.isEmpty ?? true) ? Self.defaultWakePhrase : stored!
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                                       forKey: Self.wakeWordKey)
        }
    }

    // MARK: - Private

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var windowTimer: Timer?

    private var isPaused = false
    private var lastTriggerTime: CFAbsoluteTime = 0
    private let cooldown: TimeInterval = 3.0
    private let windowDuration: TimeInterval = 30.0

    private var hasPermission = false

    private init() {
        checkPermissions()
    }

    // MARK: - Permissions

    private func checkPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            self?.hasPermission = (status == .authorized)
            if status != .authorized {
                print("[Hotword] ⚠️ Speech recognition not authorized: \(status.rawValue)")
            }
        }
    }

    // MARK: - Start / Stop

    func start() {
        #if targetEnvironment(simulator)
        print("[Hotword] ℹ️ Hotword listener disabled in Simulator")
        return
        #else
        guard !isPaused, !audioEngine.isRunning, hasPermission else { return }
        print("[Hotword] 🎙️ Starting hotword listener — phrase: '\(wakePhrase)'")

        guard configureAudioSession() else {
            print("[Hotword] ⚠️ Could not configure audio session; listener will not start.")
            return
        }
        startRecognitionWindow()
        startWindowTimer()
        #endif
    }

    func stop() {
        print("[Hotword] 🛑 Stopping hotword listener")
        windowTimer?.invalidate()
        windowTimer = nil
        stopRecognition()
        stopEngine()
    }

    
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        print("[Hotword] ⏸ Paused")
        stop()
    }

    /// Resume after pause.
    func resume() {
        guard isPaused else { return }
        isPaused = false
        print("[Hotword] ▶️ Resuming")
        #if targetEnvironment(simulator)
        return
        #else
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.isPaused else { return }
            self.start()
        }
        #endif
    }

    // MARK: - Audio Session

    @discardableResult
    private func configureAudioSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[Hotword] ✅ Audio session active")
            return true
        } catch {
            print("[Hotword] ❌ Audio session failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Rolling Recognition Windows

    private func startWindowTimer() {
        windowTimer?.invalidate()
        windowTimer = Timer.scheduledTimer(withTimeInterval: windowDuration, repeats: true) { [weak self] _ in
            self?.restartRecognitionWindow()
        }
    }

    private func restartRecognitionWindow() {
        stopRecognition()
        // Small delay to let the old task tear down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.isPaused else { return }
            self.startRecognitionWindow()
        }
    }

    private func startRecognitionWindow() {
        guard speechRecognizer?.isAvailable == true else {
            print("[Hotword] ⚠️ SFSpeechRecognizer not available")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true  // low latency, no network
        } else {
            request.requiresOnDeviceRecognition = false
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                if self.containsWakePhrase(text) {
                    self.triggerHotword()
                }
            }
            if let error {
                // Error 216 = "request was canceled" — normal on window restart, ignore.
                // Error 1110 = "No speech detected" — normal when room is quiet, ignore.
                let nsError = error as NSError
                if nsError.code != 216 && nsError.code != 1110 {
                    print("[Hotword] SFSpeech error: \(error.localizedDescription)")
                }
            }
        }

        // Install mic tap if engine is not running.
        if !audioEngine.isRunning {
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                print("[Hotword] ⚠️ Invalid audio input format (sampleRate: \(format.sampleRate), channels: \(format.channelCount)). Tap not installed.")
                return
            }
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard let self, let req = self.recognitionRequest else { return }
                req.append(buffer)
            }

            audioEngine.prepare()
            do {
                try audioEngine.start()
            } catch {
                print("[Hotword] ❌ Engine start failed: \(error.localizedDescription)")
            }
        }
    }

    private func stopRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    private func stopEngine() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        // Deactivate synchronously: callers immediately start another recorder
        // (inline voice/Live), and a queued deactivation would tear down the
        // newly activated session.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Wake Phrase Matching


    private var wakePatterns: [String] {
        let phrase = wakePhrase.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        var patterns = Set<String>()
        patterns.insert(phrase)
        
        let collapsed = phrase.replacingOccurrences(of: " ", with: "")
        patterns.insert(collapsed)
        
        if phrase.hasPrefix("hey ") {
            let withoutHey = String(phrase.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            patterns.insert(withoutHey)
            patterns.insert(withoutHey.replacingOccurrences(of: " ", with: ""))
        }
        
        if phrase.contains("b easy") || phrase.contains("beasy") {
            patterns.insert("hey beasy")
            patterns.insert("beasy")
            patterns.insert("hey b easy")
            patterns.insert("b easy")
            patterns.insert("hey be easy")
            patterns.insert("be easy")
        }
        if phrase.contains("narayan") {
            patterns.insert("hey narayan")
            patterns.insert("narayan")
            patterns.insert("hey narayana")
            patterns.insert("narayana")
        }
        return Array(patterns).filter { !$0.isEmpty }
    }

    private func containsWakePhrase(_ text: String) -> Bool {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return wakePatterns.contains { pattern in
            let cleanPattern = pattern.replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
            return cleaned.contains(cleanPattern)
        }
    }

    // MARK: - Trigger

    private func triggerHotword() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastTriggerTime > cooldown else { return }
        lastTriggerTime = now
        print("[Hotword] 🔔 Wake phrase detected! Triggering voice sale...")
        // Haptic feedback
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            self.onHotword?()
        }
    }
}
