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
    private var silentRestarts = 0
    private var lastHeartbeat: CFAbsoluteTime = 0
    private var bufferCount = 0
    private var lastBufferTime: CFAbsoluteTime = 0
    private var failedStarts = 0
    private var stallWarned = false

    private let silenceCut: TimeInterval = 1.2
    private let maxTurn: TimeInterval = 30.0
    
    private var noiseFloor: Float = 0.008
    private var voiceStreak = 0
    private let neededStreak = 8
    private var speechStart: CFAbsoluteTime = 0

    private func voiceThreshold() -> Float {
        var thr = max(noiseFloor * 4, noiseFloor + 0.012, 0.006)
        if noiseFloor > 0.04 { thr *= 1.5 } // loud room: conservative
        return thr
    }

    var isRunning: Bool { audioEngine.isRunning }

    func start() {
        LiveLog.mic("start() — configuring session + tap")
        stopTap()
        frames.removeAll()
        heardSpeech = false
        voiceStreak = 0
        speechStart = 0
        isCutting = false
        monitoring = false
        bargeHits = 0
        silentRestarts = 0
        bufferCount = 0
        noiseFloor = 0.008
        lastHeartbeat = CFAbsoluteTimeGetCurrent()
        turnStart = CFAbsoluteTimeGetCurrent()
        lastVoiceTime = turnStart

        
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            do {
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                LiveLog.mic("audio session active")
            } catch {
                LiveLog.mic("session activate FAILED: \(error.localizedDescription)")
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
        guard format.sampleRate > 0, format.channelCount > 0 else {
            LiveLog.mic("startTap FAILED: invalid input format (sampleRate=\(format.sampleRate), channels=\(format.channelCount))")
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
            LiveLog.mic("engine started — tap live")
        } catch {
            failedStarts += 1
            LiveLog.mic("engine.start FAILED (#\(failedStarts)): \(error.localizedDescription)")
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
            LiveLog.mic("tap buffer EMPTY (format=\(buffer.format))")
            return
        }
        bufferCount += 1
        lastBufferTime = CFAbsoluteTimeGetCurrent()
        if bufferCount == 1 {
            LiveLog.mic("first tap buffer: frames=\(chunk.count) fmt=\(buffer.format)")
        }
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        let peak = chunk.map { abs($0) }.max() ?? 0
        let lvl = max(0, min(1, (20 * log10(rms + 1e-6) + 50) / 50))
        DispatchQueue.main.async { self.onLevel?(CGFloat(lvl)) }

        // Barge-in watch while speaking.
        if monitoring {
            if rms > self.voiceThreshold() && peak > 0.02 {
                bargeHits += 1
                if bargeHits >= 4 {
                    bargeHits = 0
                    DispatchQueue.main.async { self.onBargeIn?() }
                }
            } else {
                bargeHits = 0
            }
            return
        }

        // Normal listen turn.
        frames.append(contentsOf: chunk)
        if frames.count > 480_000 { frames.removeFirst(frames.count - 480_000) } // 30s cap
        let now = CFAbsoluteTimeGetCurrent()
        let thr = voiceThreshold()
        if rms > thr && peak > thr {
            voiceStreak += 1
            if voiceStreak >= neededStreak {
                if !heardSpeech {
                    speechStart = now - 0.4 // include streak onset + pad
                    LiveLog.mic("speech confirmed (\(voiceStreak) bufs, rms=\(String(format: "%.3f", rms)), floor=\(String(format: "%.4f", noiseFloor)), thr=\(String(format: "%.3f", thr)))")
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
            noiseFloor = min(max(noiseFloor, 0.004), 0.04)
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
        if speechStart > 0 {
            let keepSecs = min(Double(snapshot.count) / 16000.0, (nowCut - speechStart) + 1.5)
            let keepCount = max(4800, Int(keepSecs * 16000))
            if snapshot.count > keepCount {
                LiveLog.mic("snapshot bounded: \(String(format: "%.1f", Double(snapshot.count) / 16000.0))s -> \(String(format: "%.1f", Double(keepCount) / 16000.0))s (stale dropped)")
                snapshot.removeFirst(snapshot.count - keepCount)
            }
        }
       
        
        turnStart = CFAbsoluteTimeGetCurrent()
        lastVoiceTime = turnStart
        LiveLog.whisper("cut(reason=\(reason)) — transcribing \(String(format: "%.1f", Double(snapshot.count) / 16000.0))s audio (engine keeps running)")
        DispatchQueue.main.async { self.onStatus?(.thinking, reason == "max" ? "Heard the full 30 seconds. Understanding..." : "Understanding...") }
        Task {
            let text = await WhisperService.shared.transcribe(audioFrames: snapshot)
            let roman = LiveRomanFilter.dedupeRepeats(LiveRomanFilter.toRoman(text ?? ""))
            LiveLog.whisper("result: '\(roman.prefix(120))'")
            DispatchQueue.main.async {
                self.isCutting = false
               
                if self.frames.count > 192_000 { self.frames.removeFirst(self.frames.count - 192_000) }
                self.heardSpeech = false
                self.voiceStreak = 0
                self.speechStart = 0
                self.lastVoiceTime = CFAbsoluteTimeGetCurrent()
                if roman.count < 2 {
                    LiveLog.whisper("too short/garbage — listening again, Qwen skipped")
                    self.listenAgain()
                    return
                }
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
