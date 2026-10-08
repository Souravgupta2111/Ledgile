import Foundation
import AVFoundation

/// - Natural Indian female voice (Veena for Roman Hinglish/English, Lekha/Kavya for Hindi).
/// - Spoken currency and number formatting (₹500 -> 500 rupaye).
final class SarvamBulbulSpeaker: NSObject {

    var onLevel: ((CGFloat) -> Void)?
    var onDone: (() -> Void)?
    var onError: ((String) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var nativeQueue: [String] = []
    private var isWorking = false
    private var stopped = false
    private var levelTimer: Timer?

    var isSpeaking: Bool { synthesizer.isSpeaking || isWorking }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks the full response using Apple's native AVSpeechSynthesizer.Dukan
    func speak(_ text: String, voice: String = "priya") {
        stop()
        stopped = false
        let cleaned = Self.cleanForSpeech(text)
        guard !cleaned.isEmpty else {
            onDone?()
            return
        }
        nativeQueue = Self.splitSentences(cleaned)
        LiveLog.tts("═══ speak() [Apple Native AVSpeechSynthesizer] ═══")
        LiveLog.tts("[DIAG] \(nativeQueue.count) sentence(s), \(cleaned.count) chars: '\(cleaned.prefix(80))'")
        pumpNative()
    }

    func stop() {
        LiveLog.tts("stop()")
        stopped = true
        nativeQueue.removeAll()
        isWorking = false
        levelTimer?.invalidate()
        levelTimer = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        onLevel?(0)
    }

    private func pumpNative() {
        guard !stopped else { return }
        guard !nativeQueue.isEmpty else {
            isWorking = false
            levelTimer?.invalidate()
            levelTimer = nil
            onLevel?(0)
            LiveLog.tts("✅ [DIAG] Speech completed naturally — calling onDone")
            onDone?()
            return
        }
        isWorking = true
        let sentence = nativeQueue.removeFirst()

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let utterance = AVSpeechUtterance(string: sentence)
        let selectedVoice = Self.resolveBestVoice(for: sentence)
        utterance.voice = selectedVoice
        // Natural human conversational pacing (0.48 rate, normal female pitch 1.02)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.02
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = 0.08

        LiveLog.tts("🔊 [DIAG] Speaking with voice: '\(selectedVoice.name)' (\(selectedVoice.language)) [\(nativeQueue.count) remaining]: '\(sentence.prefix(60))'")
        synthesizer.speak(utterance)
        startLevels()
    }

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
    /// strips markdown formatting, and ensures smooth Hindi/English pronunciation.
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

    /// Selects highest-quality female voice available on device.
    /// Prioritizes Female Indian voices (Veena for en-IN Roman Hinglish, or Kavya/Lekha for hi-IN Devanagari).
    private static func resolveBestVoice(for text: String) -> AVSpeechSynthesisVoice {
        let hasDevanagari = text.range(of: "\\p{Devanagari}", options: .regularExpression) != nil
        let targetLang = hasDevanagari ? "hi-IN" : "en-IN"
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        // 1. Look for Female Premium/Enhanced Indian voices (en-IN or hi-IN)
        if let v = allVoices.first(where: { $0.language == targetLang && $0.gender == .female && ($0.quality == .premium || $0.quality == .enhanced) }) {
            return v
        }

        // 2. Look for Female Indian target voice (Veena for en-IN, Kavya/Lekha for hi-IN)
        if let v = allVoices.first(where: { $0.language == targetLang && $0.gender == .female }) {
            return v
        }

        // 3. Alternate Indian female voice
        let altLang = hasDevanagari ? "en-IN" : "hi-IN"
        if let v = allVoices.first(where: { $0.language == altLang && $0.gender == .female }) {
            return v
        }

        // 4. Any Indian female voice
        if let v = allVoices.first(where: { $0.gender == .female && ($0.language.hasPrefix("en") || $0.language.hasPrefix("hi")) }) {
            return v
        }

        // 5. Default female or fallback
        if let v = allVoices.first(where: { $0.gender == .female }) {
            return v
        }

        return AVSpeechSynthesisVoice(language: targetLang)
            ?? AVSpeechSynthesisVoice(language: "en-IN")
            ?? AVSpeechSynthesisVoice(language: "hi-IN")
            ?? AVSpeechSynthesisVoice()
    }

    private func startLevels() {
        levelTimer?.invalidate()
        var phase: Float = 0
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, self.synthesizer.isSpeaking else { return }
            phase += 0.35
            let pulse = (sin(phase) + 1.0) * 0.3 + 0.15
            self.onLevel?(CGFloat(pulse))
        }
    }
}

extension SarvamBulbulSpeaker: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        LiveLog.tts("✅ [DIAG] native sentence finished — pumping next")
        pumpNative()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        LiveLog.tts("[DIAG] native AVSpeechSynthesizer cancelled")
        nativeQueue.removeAll()
        levelTimer?.invalidate()
        levelTimer = nil
        onLevel?(0)
        isWorking = false
    }
}
