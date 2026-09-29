import Foundation
import AVFoundation

/// Sarvam Bulbul v3 cloud TTS (Anushka default, hi-IN).
/// Key stays on Edge (SARVAM_API_KEY); app only sends text via gemini-proxy
/// task `bulbul-tts` and plays returned base64 WAV. Sentence queue gives
/// Gemini-like streaming: first sentence plays while rest synthesizes.
final class SarvamBulbulSpeaker: NSObject {

    var onLevel: ((CGFloat) -> Void)?
    var onDone: (() -> Void)?
    var onError: ((String) -> Void)?

    private var player: AVAudioPlayer?
    private var queue: [String] = []
    private var isWorking = false
    private var stopped = false
    private let session = URLSession.shared
    private var levelTimer: Timer?
    private var consecutiveFailures = 0

    var isSpeaking: Bool { player?.isPlaying == true || isWorking }

    private var supabaseURL: String {
        let v = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
        return (v.hasPrefix("$(") || v.isEmpty) ? "" : v.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var supabaseAnonKey: String {
        let v = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
        return (v.hasPrefix("$(") || v.isEmpty) ? "" : v.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Speak full answer, split into sentences for streaming feel.
    func speak(_ text: String, voice: String = "priya") {
        stop()
        stopped = false
        consecutiveFailures = 0
        let parts = text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        queue = parts.isEmpty ? [text] : parts
        LiveLog.tts("speak() — \(queue.count) sentence(s), \(text.count) chars")
        pump(voice: voice)
    }

    func stop() {
        LiveLog.tts("stop()")
        stopped = true
        queue.removeAll()
        isWorking = false
        consecutiveFailures = 0
        levelTimer?.invalidate()
        levelTimer = nil
        player?.stop()
        player = nil
        onLevel?(0)
    }

    private func pump(voice: String) {
        guard !stopped else { return }
        guard !queue.isEmpty else {
            isWorking = false
            onDone?()
            return
        }
        isWorking = true
        let sentence = queue.removeFirst()
        Task {
            do {
                LiveLog.tts("fetchTTS '\(sentence.prefix(80))…'")
                let data = try await fetchTTS(text: sentence, voice: voice)
                LiveLog.tts("audio \(data.count) bytes — playing")
                guard !self.stopped else { return }
                self.consecutiveFailures = 0
                try self.play(data: data)
            } catch {
                self.consecutiveFailures += 1
                LiveLog.tts("sentence FAILED (#\(self.consecutiveFailures)): \(error.localizedDescription)")
                if self.consecutiveFailures >= 3 || self.queue.isEmpty {
                    // All sentences failed — surface error and stop trying.
                    LiveLog.tts("too many failures or queue empty — giving up, firing onError")
                    self.isWorking = false
                    DispatchQueue.main.async {
                        self.onError?(error.localizedDescription)
                        self.onDone?()
                    }
                    return
                }
                self.pump(voice: voice)
            }
        }
    }

    private func fetchTTS(text: String, voice: String) async throws -> Data {
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else {
            throw NSError(domain: "Bulbul", code: 1, userInfo: [NSLocalizedDescriptionKey: "Supabase not configured"])
        }
        guard let jwt = AuthManager.shared.accessToken else {
            throw NSError(domain: "Bulbul", code: 2, userInfo: [NSLocalizedDescriptionKey: "Login required for voice"])
        }
        guard let url = URL(string: "\(supabaseURL)/functions/v1/gemini-proxy") else {
            throw NSError(domain: "Bulbul", code: 3, userInfo: [NSLocalizedDescriptionKey: "Bad Edge URL"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.timeoutInterval = 25
        let body: [String: Any] = ["task": "bulbul-tts", "text": text, "speaker": voice, "language": "hi-IN", "pace": 1.0]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let b64 = json["audioBase64"] as? String,
              let audio = Data(base64Encoded: b64) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? "Voice synthesis failed."
            throw NSError(domain: "Bulbul", code: 4, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return audio
    }

    private func play(data: Data) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? audioSession.setActive(true)
        player = try AVAudioPlayer(data: data)
        player?.delegate = self
        player?.isMeteringEnabled = true
        player?.play()
        startLevels()
    }

    private func startLevels() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, let p = self.player, p.isPlaying else { return }
            p.updateMeters()
            let db = p.averagePower(forChannel: 0)
            let lvl = max(0, min(1, (db + 50) / 50))
            self.onLevel?(CGFloat(lvl))
        }
    }
}

extension SarvamBulbulSpeaker: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        levelTimer?.invalidate()
        levelTimer = nil
        onLevel?(0)
        // Next sentence (same voice).
        pump(voice: "priya")
    }
}
