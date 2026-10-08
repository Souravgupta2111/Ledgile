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
    /// Fired when the mic hears nothing for a long time (simulator = no mic).
    var onMicHint: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var frames: [Float] = []
    private var lastVoiceTime: CFAbsoluteTime = 0
    private var turnStart: CFAbsoluteTime = 0
    private var heardSpeech = false
    private var isCutting = false
    private var monitoring = false  // true while speaker plays (barge-in watch)
    private var bargeHits = 0
    private var bargePreRoll: [Float] = []
    private var silentRestarts = 0
    private var lastHeartbeat: CFAbsoluteTime = 0
    private var bufferCount = 0
    private var lastBufferTime: CFAbsoluteTime = 0
    private var failedStarts = 0
    private var stallWarned = false

    private let silenceCut: TimeInterval = 0.85
    private let maxTurn: TimeInterval = 30.0
    
    private var noiseFloor: Float = 0.002
    private var voiceStreak = 0
    private let neededStreak = 5
    private var speechStart: CFAbsoluteTime = 0

    private func voiceThreshold() -> Float {
        var thr = max(noiseFloor * 3, noiseFloor + 0.002, 0.002)
        if noiseFloor > 0.04 { thr *= 1.5 } // loud room: conservative
        return thr
    }

    var isRunning: Bool { audioEngine.isRunning }

    func start() {
        LiveLog.mic("═══ start() ═══")
        LiveLog.mic("engine.isRunning=\(audioEngine.isRunning)")
        stopTap()
        frames.removeAll()
        heardSpeech = false
        voiceStreak = 0
        speechStart = 0
        isCutting = false
        monitoring = false
        bargeHits = 0
        bargePreRoll.removeAll()
        silentRestarts = 0
        bufferCount = 0
        noiseFloor = 0.002
        lastHeartbeat = CFAbsoluteTimeGetCurrent()
        turnStart = CFAbsoluteTimeGetCurrent()
        lastVoiceTime = turnStart

        
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            LiveLog.mic("[DIAG] AVAudioSession current: category=\(session.category.rawValue) mode=\(session.mode.rawValue) sampleRate=\(session.sampleRate) inputAvailable=\(session.isInputAvailable)")
            if let inputs = session.availableInputs {
                for inp in inputs {
                    LiveLog.mic("[DIAG] available input: \(inp.portName) type=\(inp.portType.rawValue)")
                }
            }
            try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            do {
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                LiveLog.mic("✅ audio session active — sampleRate=\(session.sampleRate) inputAvailable=\(session.isInputAvailable)")
                if let currentInput = session.currentRoute.inputs.first {
                    LiveLog.mic("[DIAG] active input: \(currentInput.portName) type=\(currentInput.portType.rawValue)")
                } else {
                    LiveLog.mic("⚠️ [DIAG] NO active input in currentRoute!")
                }
            } catch {
                LiveLog.mic("❌ session activate FAILED: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                WhisperService.shared.preloadModel()
                LiveLog.mic("Whisper ready=\(WhisperService.shared.isReady) — starting tap")
                self.onStatus?(.listening, "Listening...")
                self.startTap()
            }
        }
    }

   
    func monitorForBargeIn(_ on: Bool) {
        LiveLog.mic("monitorForBargeIn(\(on)) — engine running=\(audioEngine.isRunning)")
        monitoring = on
        bargeHits = 0
        bargePreRoll.removeAll()
        if on && !audioEngine.isRunning { startTap() }
    }

    func stop() {
        LiveLog.mic("stop()")
        monitoring = false
        stopTap()
        DispatchQueue.global(qos: .utility).async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        onStatus?(.idle, "")
    }

    // MARK: - Tap

    private func startTap() {
        if audioEngine.isRunning {
            LiveLog.mic("startTap: engine already running")
            return
        }
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        LiveLog.mic("[DIAG] inputNode format: sampleRate=\(format.sampleRate) channels=\(format.channelCount) commonFormat=\(format.commonFormat.rawValue) interleaved=\(format.isInterleaved)")
        guard format.sampleRate > 0, format.channelCount > 0 else {
            LiveLog.mic("❌ startTap FAILED: invalid input format (sampleRate=\(format.sampleRate), channels=\(format.channelCount))")
            DispatchQueue.main.async { self.onStatus?(.idle, "Mic unavailable") }
            return
        }
        input.removeTap(onBus: 0)
        
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.handle(buffer: buffer)
        }
        do {
            try audioEngine.start()
            failedStarts = 0
            stallWarned = false
            lastBufferTime = CFAbsoluteTimeGetCurrent()
            LiveLog.mic("✅ engine started — tap live (format: \(format.sampleRate)Hz, \(format.channelCount)ch)")
        } catch {
            failedStarts += 1
            LiveLog.mic("❌ engine.start FAILED (#\(failedStarts)): \(error.localizedDescription)")
            DispatchQueue.main.async { self.onStatus?(.idle, "Mic unavailable") }
        }
    }

    private func stopTap() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }

    private func handle(buffer: AVAudioPCMBuffer) {
        guard let chunk = WhisperService.convertBufferToFrames(buffer), !chunk.isEmpty else {
            if bufferCount == 0 {
                LiveLog.mic("⚠️ [DIAG] FIRST tap buffer is EMPTY — convertBufferToFrames returned nil/empty (buffer.format=\(buffer.format), frameLength=\(buffer.frameLength))")
            }
            return
        }
        bufferCount += 1
        lastBufferTime = CFAbsoluteTimeGetCurrent()
        if bufferCount == 1 {
            LiveLog.mic("[DIAG] ✅ first tap buffer received: frames=\(chunk.count) fmt=\(buffer.format)")
        }
        // Log every 50th buffer for flow diagnostics
        if bufferCount % 50 == 0 {
            let rmsVal = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            let peakVal = chunk.map { abs($0) }.max() ?? 0
            LiveLog.mic("[DIAG] buffer #\(bufferCount): rms=\(String(format: "%.5f", rmsVal)) peak=\(String(format: "%.5f", peakVal)) threshold=\(String(format: "%.5f", voiceThreshold())) noiseFloor=\(String(format: "%.5f", noiseFloor)) heardSpeech=\(heardSpeech) voiceStreak=\(voiceStreak) totalFrames=\(frames.count)")
        }
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        let peak = chunk.map { abs($0) }.max() ?? 0
        let lvl = max(0, min(1, (20 * log10(rms + 1e-6) + 50) / 50))
        DispatchQueue.main.async { self.onLevel?(CGFloat(lvl)) }

        // Barge-in watch while speaking — requires clear sustained vocal sound, ignoring ambient taps/breaths.
        if monitoring {
            bargePreRoll.append(contentsOf: chunk)
            if bargePreRoll.count > 16_000 {
                bargePreRoll.removeFirst(bargePreRoll.count - 16_000)
            }
            if peak > 0.035 && rms > max(self.voiceThreshold() * 1.5, 0.005) {
                bargeHits += 1
                if bargeHits >= 5 {
                    bargeHits = 0
                    LiveLog.mic("🗣️ [DIAG] Clear vocal speech detected during playback — triggering barge-in")
                    monitoring = false
                    frames = bargePreRoll
                    bargePreRoll.removeAll()
                    heardSpeech = true
                    speechStart = CFAbsoluteTimeGetCurrent() - 0.5
                    lastVoiceTime = CFAbsoluteTimeGetCurrent()
                    voiceStreak = neededStreak
                    DispatchQueue.main.async { self.onBargeIn?() }
                }
            } else {
                bargeHits = max(0, bargeHits - 1)
            }
            return
        }

        // Normal listen turn.
        frames.append(contentsOf: chunk)
        if frames.count > 480_000 { frames.removeFirst(frames.count - 480_000) } // 30s cap
        let now = CFAbsoluteTimeGetCurrent()
        let thr = voiceThreshold()
        if peak > thr && rms > thr * 0.25 {
            voiceStreak += 1
            if voiceStreak >= neededStreak {
                if !heardSpeech {
                    speechStart = now - 0.4 // include streak onset + pad
                    LiveLog.mic("speech confirmed (\(voiceStreak) bufs, rms=\(String(format: "%.3f", rms)), floor=\(String(format: "%.4f", noiseFloor)), thr=\(String(format: "%.3f", thr)))")
                    DispatchQueue.main.async { self.onSpeechStarted?() }
                }
                lastVoiceTime = now
                heardSpeech = true
            }
        } else {
            if voiceStreak > 0 && voiceStreak < neededStreak {
                LiveLog.mic("voice streak broken at \(voiceStreak)/\(neededStreak) — spike ignored")
            }
            voiceStreak = 0
            
            noiseFloor += (min(rms, thr) - noiseFloor) * 0.03
            noiseFloor = min(max(noiseFloor, 0.0005), 0.04)
        }
        if !heardSpeech, now - lastHeartbeat > 5 {
            lastHeartbeat = now
            let sinceBuffer = now - lastBufferTime
            LiveLog.mic("heartbeat: listening \(String(format: "%.0f", now - turnStart))s, no speech yet, floor=\(String(format: "%.4f", noiseFloor)), buffered=\(String(format: "%.1f", Double(frames.count) / 16000.0))s, lastBuffer=\(String(format: "%.1f", sinceBuffer))s ago")
            if sinceBuffer > 10 && !stallWarned {
                stallWarned = true
                LiveLog.mic("STALL: tap delivering no buffers 10s+ (simulator input device often dies after reconfig)")
                DispatchQueue.main.async {
                    self.onMicHint?("Audio tap stalled — no mic buffers for 10s+.")
                }
            }
        }
        let dur = now - turnStart
        let silentFor = now - lastVoiceTime
        if isCutting { return }
        if heardSpeech && frames.count > 9600 && silentFor >= silenceCut {
            cut(reason: "silence")
        } else if dur >= maxTurn && heardSpeech {
            cut(reason: "max")
        } else if dur >= maxTurn && !heardSpeech {
            // 30s me kuch nahi bola -> restart turn, count silence.
            silentRestarts += 1
            LiveLog.mic("30s with NO speech (silentRestarts=\(silentRestarts)) — simulator mic is usually dead")
            frames.removeAll()
            turnStart = now
            lastVoiceTime = now
            lastHeartbeat = now
            if silentRestarts == 2 {
                DispatchQueue.main.async {
                    self.onMicHint?("No mic input detected — simulator has no mic. Type below instead.")
                }
            }
        }
    }

    private func cut(reason: String) {
        isCutting = true
        var snapshot = frames
        frames.removeAll()
        let nowCut = CFAbsoluteTimeGetCurrent()
        LiveLog.mic("═══ cut(reason=\(reason)) ═══")
        LiveLog.mic("[DIAG] raw snapshot: \(snapshot.count) frames = \(String(format: "%.1f", Double(snapshot.count) / 16000.0))s")
        if speechStart > 0 {
            let keepSecs = min(Double(snapshot.count) / 16000.0, (nowCut - speechStart) + 1.5)
            let keepCount = max(4800, Int(keepSecs * 16000))
            if snapshot.count > keepCount {
                LiveLog.mic("[DIAG] snapshot bounded: \(String(format: "%.1f", Double(snapshot.count) / 16000.0))s -> \(String(format: "%.1f", Double(keepCount) / 16000.0))s")
                snapshot.removeFirst(snapshot.count - keepCount)
            }
        }
       
        
        turnStart = CFAbsoluteTimeGetCurrent()
        lastVoiceTime = turnStart
        let snapshotRms = snapshot.isEmpty ? 0 : sqrt(snapshot.reduce(0) { $0 + $1 * $1 } / Float(snapshot.count))
        let snapshotPeak = snapshot.map { abs($0) }.max() ?? 0
        LiveLog.whisper("cut(reason=\(reason)) — transcribing \(String(format: "%.1f", Double(snapshot.count) / 16000.0))s audio (rms=\(String(format: "%.5f", snapshotRms)) peak=\(String(format: "%.4f", snapshotPeak)))")
        DispatchQueue.main.async { self.onStatus?(.thinking, reason == "max" ? "Heard the full 30 seconds. Understanding..." : "Understanding...") }
        Task {
            LiveLog.whisper("[DIAG] calling WhisperService.transcribe with \(snapshot.count) frames...")
            let text = await WhisperService.shared.transcribe(audioFrames: snapshot)
            LiveLog.whisper("[DIAG] Whisper raw result: '\(text ?? "<nil>")'")
            let roman = LiveRomanFilter.dedupeRepeats(LiveRomanFilter.toRoman(text ?? ""))
            LiveLog.whisper("[DIAG] after Roman filter: '\(roman.prefix(120))' (\(roman.count) chars)")
            DispatchQueue.main.async {
                self.isCutting = false
               
                if self.frames.count > 192_000 { self.frames.removeFirst(self.frames.count - 192_000) }
                self.heardSpeech = false
                self.voiceStreak = 0
                self.speechStart = 0
                self.lastVoiceTime = CFAbsoluteTimeGetCurrent()
                if roman.count < 2 {
                    LiveLog.whisper("⚠️ too short/garbage ('\(roman)') — listening again, Qwen skipped")
                    self.listenAgain()
                    return
                }
                LiveLog.whisper("✅ sending to Qwen: '\(roman.prefix(120))'")
                self.onFinal?(roman)
            }
        }
    }

    
    func listenAgain() {
        guard !monitoring else { return }
        LiveLog.mic("listenAgain() — resetting turn markers (engine running=\(audioEngine.isRunning))")
        frames.removeAll()
        heardSpeech = false
        voiceStreak = 0
        speechStart = 0
        isCutting = false
        silentRestarts = 0
        turnStart = CFAbsoluteTimeGetCurrent()
        lastVoiceTime = turnStart
        lastHeartbeat = turnStart
        DispatchQueue.main.async { self.onStatus?(.listening, "Listening...") }
        if !audioEngine.isRunning {
            if failedStarts >= 3 {
                LiveLog.mic("not restarting engine — 3+ start failures, staying on typed input")
                return
            }
            LiveLog.mic("engine not running at listenAgain — re-activating session + restart")
            DispatchQueue.global(qos: .userInitiated).async {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
                try? session.setActive(true, options: .notifyOthersOnDeactivation)
                DispatchQueue.main.async {
                    self.startTap()
                }
            }
        }
    }
}
