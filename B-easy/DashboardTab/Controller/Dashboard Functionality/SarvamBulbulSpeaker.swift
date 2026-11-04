import Foundation
import AVFoundation

/// Typealias so callers can refer to either DeepgramSpeaker or SarvamBulbulSpeaker interchangeably.
typealias DeepgramSpeaker = SarvamBulbulSpeaker

/// Text-to-Speech Engine powered by Deepgram Flux TTS (Hannah Voice).
/// - Model: flux-hannah-en (Flux conversational architecture, Hannah voice)
/// - Expressivity: 1, Speed: 1.0x
/// - Low-latency sentence pipelining & prefetching
/// - Real-time AVAudioPlayer audio metering driving the interactive voice orb
/// - Automatic fallback to Apple's native AVSpeechSynthesizer if offline or network unavailable
final class SarvamBulbulSpeaker: NSObject {

    var onLevel: ((CGFloat) -> Void)?
    var onDone: (() -> Void)?
    var onError: ((String) -> Void)?

    // Audio & Synthesizer
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var nativeUtterance: AVSpeechUtterance?

    // Queues & State
    private var pendingSentences: [String] = []
    private var prefetchTask: Task<Data, Error>?
    private var prefetchedSentence: String?
    private var isWorking = false
    private var stopped = false
    private var levelTimer: Timer?
    private var isUsingNativeFallback = false

    // Every `speak()` gets a new run id. Stale fetch/playback tasks compare
    // against it so a cancelled run can never speak over the next one.
    private var runID = 0
    private var activeRunID = 0
    private var activeVoice = SarvamBulbulSpeaker.defaultVoice

    var isSpeaking: Bool {
        (player?.isPlaying == true) || synthesizer.isSpeaking || isWorking
    }

    // MARK: - TTS Configuration
    static let defaultVoice = "aura-asteria-en"
    static let defaultExpressivity = 1
    static let defaultSpeed = 1.0

    static var apiKey: String {
        if let key = Bundle.main.infoDictionary?["DEEPGRAM_API_KEY"] as? String,
           !key.isEmpty, !key.hasPrefix("$(") {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "e6f867b60b0bace8e478728b4dc2626f55147988"
    }

    private var supabaseURL: String {
        let v = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
        return (v.hasPrefix("$(") || v.isEmpty) ? "" : v.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var supabaseAnonKey: String {
        let v = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
        return (v.hasPrefix("$(") || v.isEmpty) ? "" : v.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    deinit {
        stop()
    }

    // MARK: - Public Interface

    /// Speaks the full response text using Deepgram Flux (Hannah voice) with sentence streaming.
    func speak(_ text: String, voice: String = defaultVoice) {
        stop()
        stopped = false
        isUsingNativeFallback = false
        activeVoice = voice
        activeRunID = runID

        let cleaned = Self.cleanForSpeech(text)
        guard !cleaned.isEmpty else {
            onDone?()
            return
        }

        pendingSentences = Self.splitSentences(cleaned)
        LiveLog.tts("═══ speak() [Deepgram Flux: Hannah (\(voice)), speed: \(Self.defaultSpeed)x, expressivity: \(Self.defaultExpressivity)] ═══")
        LiveLog.tts("[DIAG] \(pendingSentences.count) sentence(s), \(cleaned.count) chars: '\(cleaned.prefix(80))'")

        pumpNext(runID: activeRunID, voice: voice)
    }

    /// Stops any current speech playback, cancels in-flight network requests, and resets audio meters.
    func stop() {
        LiveLog.tts("stop()")
        runID &+= 1
        stopped = true
        pendingSentences.removeAll()
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchedSentence = nil
        isWorking = false
        isUsingNativeFallback = false
        nativeUtterance = nil
        levelTimer?.invalidate()
        levelTimer = nil
        if let p = player {
            p.stop()
            player = nil
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        onLevel?(0)
    }

    // MARK: - Sentence Pipeline & Prefetching

    private func pumpNext(runID: Int, voice: String) {
        guard !stopped, runID == self.runID else { return }

        guard !pendingSentences.isEmpty else {
            isWorking = false
            levelTimer?.invalidate()
            levelTimer = nil
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopped, runID == self.runID else { return }
                self.onLevel?(0)
                LiveLog.tts("✅ [DIAG] Speech completed naturally — calling onDone")
                self.onDone?()
            }
            return
        }

        isWorking = true
        let sentence = pendingSentences.removeFirst()

        Task { [weak self] in
            guard let self, !self.stopped, runID == self.runID else { return }

            do {
                let audioData: Data
                // Check if this sentence was already prefetched
                if self.prefetchedSentence == sentence, let task = self.prefetchTask {
                    LiveLog.tts("[DIAG] using prefetched audio for: '\(sentence.prefix(50))'")
                    audioData = try await task.value
                    guard !self.stopped, runID == self.runID else { return }
                    self.prefetchTask = nil
                    self.prefetchedSentence = nil
                } else {
                    audioData = try await self.fetchDeepgramAudio(text: sentence, voice: voice)
                }

                guard !self.stopped, runID == self.runID else { return }

                // Prefetch the next sentence in background while this one plays
                if let nextSentence = self.pendingSentences.first {
                    self.prefetchedSentence = nextSentence
                    self.prefetchTask = Task { [weak self] () -> Data in
                        guard let self, !self.stopped, runID == self.runID else { throw CancellationError() }
                        return try await self.fetchDeepgramAudio(text: nextSentence, voice: voice)
                    }
                }

                // Play the synthesized audio on main thread so Timer and audio delegate run on main RunLoop
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.stopped, runID == self.runID else { return }
                    do {
                        try self.playAudio(data: audioData, for: sentence)
                    } catch {
                        LiveLog.tts("⚠️ Playback error: \(error.localizedDescription) — falling back to native synthesizer")
                        self.speakWithNativeSynthesizer(sentence, runID: runID)
                    }
                }

            } catch {
                guard !self.stopped, runID == self.runID else { return }
                LiveLog.tts("⚠️ TTS fetch failed: \(error.localizedDescription) — falling back to native synthesizer for this sentence")
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.stopped, runID == self.runID else { return }
                    self.speakWithNativeSynthesizer(sentence, runID: runID)
                }
            }
        }
    }

    // MARK: - Direct Deepgram TTS Request

    private func fetchDeepgramAudio(text: String, voice: String) async throws -> Data {
        let key = Self.apiKey
        guard !key.isEmpty else {
            throw NSError(domain: "Deepgram", code: 1, userInfo: [NSLocalizedDescriptionKey: "Deepgram API key missing"])
        }
        guard let requestURL = URL(string: "https://api.deepgram.com/v1/speak?model=\(voice)") else {
            throw NSError(domain: "Deepgram", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid Deepgram URL"])
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: Any] = ["text": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 500
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            LiveLog.tts("❌ Deepgram TTS HTTP \(status): \(errorText.prefix(200))")
            throw NSError(domain: "Deepgram", code: status, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        LiveLog.tts("⚡️ Deepgram TTS fetched in \(String(format: "%.2f", elapsed))s (\(data.count) bytes)")
        return data
    }

    // MARK: - Audio Playback

    private func playAudio(data: Data, for sentence: String) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? audioSession.overrideOutputAudioPort(.speaker)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        player = try AVAudioPlayer(data: data)
        player?.delegate = self
        player?.isMeteringEnabled = true
        player?.volume = 1.0
        player?.prepareToPlay()
        guard player?.play() == true else {
            throw NSError(domain: "SarvamSpeaker", code: 500, userInfo: [NSLocalizedDescriptionKey: "AVAudioPlayer.play() returned false"])
        }

        LiveLog.tts("🔊 [DIAG] Playing Deepgram audio (\(data.count) bytes) [\(pendingSentences.count) remaining]: '\(sentence.prefix(60))'")
        startAudioLevels()
    }

    private func startAudioLevels() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let p = self.player, p.isPlaying else { return }
            p.updateMeters()
            let power = p.averagePower(forChannel: 0) // range: -160 to 0 dB
            let norm = max(0, min(1, (power + 45) / 45))
            self.onLevel?(CGFloat(norm))
        }
    }

    // MARK: - Native Fallback Synthesizer

    private func speakWithNativeSynthesizer(_ sentence: String, runID: Int) {
        guard !stopped, runID == self.runID else { return }
        isUsingNativeFallback = true

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? audioSession.overrideOutputAudioPort(.speaker)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let utterance = AVSpeechUtterance(string: sentence)
        let selectedVoice = Self.resolveBestVoice(for: sentence)
        utterance.voice = selectedVoice
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.02
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = 0.08
        nativeUtterance = utterance

        LiveLog.tts("🔊 [FALLBACK] Speaking with native voice: '\(selectedVoice.name)' (\(selectedVoice.language)): '\(sentence.prefix(60))'")
        synthesizer.speak(utterance)
        startNativeLevels()
    }

    private func startNativeLevels() {
        levelTimer?.invalidate()
        var phase: Float = 0
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, self.synthesizer.isSpeaking else { return }
            phase += 0.35
            let pulse = (sin(phase) + 1.0) * 0.3 + 0.15
            self.onLevel?(CGFloat(pulse))
        }
    }

    // MARK: - Text Cleaning & Splitting Utilities

    /// Splits text into natural conversational sentence chunks on punctuation boundaries.
    static func splitSentences(_ text: String) -> [String] {
        let pattern = "(?<=[.?!\\n])\\s+"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            var results: [String] = []
            var lastIndex = 0
            for match in matches {
                let r = NSRange(location: lastIndex, length: match.range.location - lastIndex)
                let s = nsString.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { results.append(s) }
                lastIndex = match.range.location + match.range.length
            }
            if lastIndex < nsString.length {
                let s = nsString.substring(from: lastIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { results.append(s) }
            }
            if !results.isEmpty { return results }
        }
        return [text]
    }

    /// Preprocesses text for spoken clarity: converts currency symbols to spoken words,
    /// strips markdown formatting, and ensures smooth pronunciation.
    static func cleanForSpeech(_ text: String) -> String {
        var clean = text
        // 1. Remove bracketed debug or SQL tags like [SHOP_SQL_RESULT]
        clean = clean.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)

        // 2. Currency: replace ₹1,200 or ₹ 1200 or ₹50 with '<number> rupaye', stripping commas inside numbers
        if let regex = try? NSRegularExpression(pattern: "₹\\s*([0-9,]+(?:\\.[0-9]{1,2})?)", options: []) {
            let nsString = clean as NSString
            let matches = regex.matches(in: clean, range: NSRange(location: 0, length: nsString.length)).reversed()
            for match in matches {
                let numRange = match.range(at: 1)
                let rawNum = nsString.substring(with: numRange)
                let cleanedNum = rawNum.replacingOccurrences(of: ",", with: "")
                clean = (clean as NSString).replacingCharacters(in: match.range, with: "\(cleanedNum) rupaye")
            }
        }
        clean = clean.replacingOccurrences(of: "₹\\s*", with: "rupaye ", options: .regularExpression)

        // 3. Remove markdown formatting: bold, italic, code blocks, hashtags, bullets
        clean = clean.replacingOccurrences(of: "[*#_`~•]", with: "", options: .regularExpression)

        // 4. Clean multiple whitespace & newlines
        clean = clean.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Selects highest-quality female voice available on device for fallback.
    private static func resolveBestVoice(for text: String) -> AVSpeechSynthesisVoice {
        let hasDevanagari = text.range(of: "\\p{Devanagari}", options: .regularExpression) != nil
        let targetLang = hasDevanagari ? "hi-IN" : "en-IN"
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        if let v = allVoices.first(where: { $0.language == targetLang && $0.gender == .female && ($0.quality == .premium || $0.quality == .enhanced) }) {
            return v
        }
        if let v = allVoices.first(where: { $0.language == targetLang && $0.gender == .female }) {
            return v
        }
        let altLang = hasDevanagari ? "en-IN" : "hi-IN"
        if let v = allVoices.first(where: { $0.language == altLang && $0.gender == .female }) {
            return v
        }
        if let v = allVoices.first(where: { $0.gender == .female && ($0.language.hasPrefix("en") || $0.language.hasPrefix("hi")) }) {
            return v
        }
        if let v = allVoices.first(where: { $0.gender == .female }) {
            return v
        }
        return AVSpeechSynthesisVoice(language: targetLang)
            ?? AVSpeechSynthesisVoice(language: "en-IN")
            ?? AVSpeechSynthesisVoice(language: "hi-IN")
            ?? AVSpeechSynthesisVoice()
    }
}

// MARK: - AVAudioPlayerDelegate

extension SarvamBulbulSpeaker: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player, !stopped else { return }
        LiveLog.tts("✅ [DIAG] Deepgram sentence audio finished playing — pumping next")
        levelTimer?.invalidate()
        levelTimer = nil
        onLevel?(0)
        pumpNext(runID: activeRunID, voice: activeVoice)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === self.player, !stopped else { return }
        LiveLog.tts("❌ [DIAG] AVAudioPlayer decode error: \(error?.localizedDescription ?? "unknown")")
        levelTimer?.invalidate()
        levelTimer = nil
        onLevel?(0)
        pumpNext(runID: activeRunID, voice: activeVoice)
    }
}

// MARK: - AVSpeechSynthesizerDelegate (Fallback)

extension SarvamBulbulSpeaker: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === nativeUtterance, !stopped else { return }
        nativeUtterance = nil
        LiveLog.tts("✅ [DIAG] Native fallback sentence finished — pumping next")
        levelTimer?.invalidate()
        levelTimer = nil
        onLevel?(0)
        isUsingNativeFallback = false
        pumpNext(runID: activeRunID, voice: activeVoice)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard utterance === nativeUtterance else { return }
        nativeUtterance = nil
        LiveLog.tts("[DIAG] Native AVSpeechSynthesizer cancelled")
        pendingSentences.removeAll()
        levelTimer?.invalidate()
        levelTimer = nil
        onLevel?(0)
        isWorking = false
        isUsingNativeFallback = false
    }
}
