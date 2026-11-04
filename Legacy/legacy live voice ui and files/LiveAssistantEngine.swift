import Foundation
import AVFoundation

final class LiveAssistantEngine {

    enum Status {
        case idle, listening, thinking, speaking
    }

    var onStatus: ((Status, String) -> Void)?
    var onLevel: ((CGFloat) -> Void)?
    var onFinal: ((String) -> Void)?
    var onBargeIn: (() -> Void)?
    var onSpeechStarted: (() -> Void)?
    var onMicHint: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let stateLock = NSLock()
    private var tapInstalled = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketSession: URLSession?
    private var isWebSocketConnected = false

    private var accumulatedPCMData = Data()
    private var isFinalized = false
    private var hasSpeechStarted = false
    private var monitoring = false // true while speaker plays (barge-in watch)
    private var bargeHits = 0
    private var turnStartTime: CFAbsoluteTime = 0
    private var lastSpeechTime: CFAbsoluteTime = 0
    private var lastHeartbeatTime: CFAbsoluteTime = 0
    private var bufferCount = 0

    var isRunning: Bool { audioEngine.isRunning }

    static var apiKey: String {
        if let key = Bundle.main.infoDictionary?["DEEPGRAM_API_KEY"] as? String,
           !key.isEmpty, !key.hasPrefix("$(") {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "e6f867b60b0bace8e478728b4dc2626f55147988"
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        webSocketSession = URLSession(configuration: config)
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() {
        LiveLog.mic("═══ start() [Deepgram STT] ═══")
        stop()

        stateLock.lock()
        isFinalized = false
        hasSpeechStarted = false
        monitoring = false
        bargeHits = 0
        bufferCount = 0
        accumulatedPCMData.removeAll()
        turnStartTime = CFAbsoluteTimeGetCurrent()
        lastSpeechTime = turnStartTime
        lastHeartbeatTime = turnStartTime
        stateLock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                LiveLog.mic("✅ Audio session active for Deepgram STT")
            } catch {
                LiveLog.mic("❌ Audio session setup failed: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self.connectWebSocket()
                self.startTap()
                self.onStatus?(.listening, "Listening...")
            }
        }
    }

    func listenAgain() {
        LiveLog.mic("═══ listenAgain() [Next Question] ═══")
        stateLock.lock()
        monitoring = false
        bargeHits = 0
        isFinalized = false
        hasSpeechStarted = false
        bufferCount = 0
        accumulatedPCMData.removeAll()
        turnStartTime = CFAbsoluteTimeGetCurrent()
        lastSpeechTime = turnStartTime
        lastHeartbeatTime = turnStartTime
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onStatus?(.listening, "Listening...")
            self.connectWebSocket()
            self.startTap()
        }
    }

    /// Pauses mic and WebSocket during assistant speech without tearing down the audio session.
    func pauseListening() {
        stateLock.lock()
        monitoring = false
        isFinalized = true
        stateLock.unlock()

        stopTap()
        closeWebSocket()
    }

    /// Full teardown when exiting the screen.
    func stop() {
        LiveLog.mic("stop()")
        pauseListening()

        DispatchQueue.global(qos: .utility).async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        onStatus?(.idle, "")
    }

    func monitorForBargeIn(_ on: Bool) {
        stateLock.lock()
        monitoring = on
        bargeHits = 0
        stateLock.unlock()
        LiveLog.mic("monitorForBargeIn(\(on)) — engine running=\(audioEngine.isRunning)")
        if on && !audioEngine.isRunning {
            startTap()
        }
    }

    // MARK: - Deepgram WebSocket STT

    private func connectWebSocket() {
        closeWebSocket()

        // Nova-2 with en-IN handles Indian English and Roman Hinglish natively.
        let urlString = "wss://api.deepgram.com/v1/listen?model=nova-2&language=en-IN&smart_format=true&encoding=linear16&sample_rate=16000&channels=1&endpointing=350&interim_results=true"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("Token \(Self.apiKey)", forHTTPHeaderField: "Authorization")

        let task = webSocketSession?.webSocketTask(with: request)
        webSocketTask = task
        isWebSocketConnected = true
        task?.resume()

        LiveLog.mic("🔌 Connecting to Deepgram Live STT WebSocket...")
        listenWebSocketMessages(for: task)
    }

    private func closeWebSocket() {
        isWebSocketConnected = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func listenWebSocketMessages(for activeTask: URLSessionWebSocketTask?) {
        guard let activeTask = activeTask, isWebSocketConnected else { return }

        activeTask.receive { [weak self] result in
            guard let self else { return }
            guard self.webSocketTask === activeTask else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleWebSocketJSON(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleWebSocketJSON(text)
                    }
                @unknown default:
                    break
                }
                self.listenWebSocketMessages(for: activeTask)

            case .failure(let error):
                LiveLog.mic("⚠️ Deepgram WebSocket receive error: \(error.localizedDescription)")
                self.isWebSocketConnected = false
            }
        }
    }

    private func handleWebSocketJSON(_ jsonText: String) {
        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let isSpeechFinal = json["speech_final"] as? Bool ?? false
        let isFinal = json["is_final"] as? Bool ?? false

        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first else { return }

        let transcript = (firstAlt["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        stateLock.lock()
        let alreadyFinalized = isFinalized
        let isMonitoring = monitoring
        stateLock.unlock()

        guard !alreadyFinalized else { return }

        if !transcript.isEmpty && !hasSpeechStarted {
            hasSpeechStarted = true
            LiveLog.mic("🗣️ Speech onset: '\(transcript)'")
            DispatchQueue.main.async { self.onSpeechStarted?() }
        }

        // If user finished speaking (speech_final or is_final with text)
        if (isSpeechFinal || isFinal) && !transcript.isEmpty && !isMonitoring {
            stateLock.lock()
            isFinalized = true
            stateLock.unlock()

            LiveLog.mic("✅ [Deepgram STT Final] Transcript: '\(transcript)'")
            DispatchQueue.main.async {
                self.stopTap()
                self.closeWebSocket()
                self.onStatus?(.thinking, "Understanding...")
                self.onFinal?(transcript)
            }
        }
    }

    // MARK: - Audio Tap & PCM Streaming

    private func startTap() {
        if audioEngine.isRunning && tapInstalled { return }

        stopTap()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        audioEngine.reset()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            LiveLog.mic("⚠️ Invalid inputNode format: \(format) — retrying in 0.2s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.startTap()
            }
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }
        tapInstalled = true

        do {
            try audioEngine.start()
            LiveLog.mic("✅ AudioEngine started — mic tap live (\(format.sampleRate)Hz)")
        } catch {
            LiveLog.mic("❌ AudioEngine start failed: \(error.localizedDescription)")
            stopTap()
            DispatchQueue.main.async { self.onStatus?(.idle, "Mic unavailable") }
        }
    }

    private func stopTap() {
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let chunk = WhisperService.convertBufferToFrames(buffer), !chunk.isEmpty else { return }

        // 1. Metering calculation for UI Orb
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        let peak = chunk.map { abs($0) }.max() ?? 0
        let lvl = max(0, min(1, (20 * log10(rms + 1e-6) + 50) / 50))
        DispatchQueue.main.async { self.onLevel?(CGFloat(lvl)) }

        // 2. Barge-in check during assistant speech
        stateLock.lock()
        let isMonitoring = monitoring
        let alreadyFinalized = isFinalized
        stateLock.unlock()

        if isMonitoring {
            if peak > 0.05 && rms > 0.015 {
                bargeHits += 1
                if bargeHits >= 4 {
                    bargeHits = 0
                    stateLock.lock()
                    monitoring = false
                    stateLock.unlock()
                    LiveLog.mic("🗣️ Clear vocal speech during playback — triggering barge-in")
                    DispatchQueue.main.async { self.onBargeIn?() }
                }
            } else {
                bargeHits = max(0, bargeHits - 1)
            }
            return
        }

        guard !alreadyFinalized else { return }

        // 3. Convert 16kHz float frames into 16-bit Linear PCM Little-Endian
        let pcmData = Self.framesToLinear16PCM(chunk)

        stateLock.lock()
        accumulatedPCMData.append(pcmData)
        bufferCount += 1
        stateLock.unlock()

        // 4. Send audio bytes over WebSocket to Deepgram STT
        if isWebSocketConnected, let task = webSocketTask {
            task.send(.data(pcmData)) { error in
                if let error = error {
                    LiveLog.mic("⚠️ Deepgram send error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Utilities

    /// Converts normalized 16kHz Float audio frames [-1.0, 1.0] to 16-bit signed Linear PCM bytes.
    static func framesToLinear16PCM(_ frames: [Float]) -> Data {
        var data = Data(capacity: frames.count * MemoryLayout<Int16>.size)
        for sample in frames {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Val = Int16(clamped * 32767.0)
            var le = int16Val.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }
}
