import Foundation
import SwiftWhisper
import AVFoundation

final class WhisperService {
    
    static let shared = WhisperService()
    
    
     var whisper: Whisper?
     var isLoading = false
     let loadLock = NSLock()
    
    
    var isReady: Bool { whisper != nil }
    
     init() {}
    
    
    func preloadModel() {
        loadLock.lock()
        defer { loadLock.unlock() }
        
        guard whisper == nil, !isLoading else { return }
        isLoading = true
        
        let loadStart = CFAbsoluteTimeGetCurrent()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if let coreMLURL = Bundle.main.url(forResource: "ggml-small-encoder", withExtension: "mlmodelc") {
            } else {
            }

            guard let modelURL = Bundle.main.url(forResource: "ggml-small-q5_1", withExtension: "bin") else {
                self.loadLock.lock()
                self.isLoading = false
                self.loadLock.unlock()
                return
            }
            
            if let attrs = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
               let size = attrs[.size] as? Int64 {
            }
            
            do {
                let params = Self.makeWhisperParams()
                
               
                let whisperInstance = try Whisper(fromFileURL: modelURL, withParams: params)
                let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
                self.loadLock.lock()
                self.whisper = whisperInstance
                self.isLoading = false
                self.loadLock.unlock()
            } catch {
                let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
                self.loadLock.lock()
                self.isLoading = false
                self.loadLock.unlock()
            }
        }
    }
    
    
    func transcribe(audioFrames: [Float]) async -> String? {
        let totalStart = CFAbsoluteTimeGetCurrent()
        
        let trimmedFrames = Self.trimSilence(from: audioFrames, threshold: 0.03) 
        
        let durationSecs = Double(trimmedFrames.count) / 16000.0
        let maxAmplitude = trimmedFrames.map { abs($0) }.max() ?? 0
        let avgAmplitude = trimmedFrames.isEmpty ? 0 : trimmedFrames.map { abs($0) }.reduce(0, +) / Float(trimmedFrames.count)
        
     
        if maxAmplitude < 0.015 { 
            return nil
        }
        
        if durationSecs < 0.3 {
            return nil
        }
        
        if whisper == nil {
            let modelLoadStart = CFAbsoluteTimeGetCurrent()
            await loadModelSync()
            let modelLoadTime = CFAbsoluteTimeGetCurrent() - modelLoadStart
        } else {
        }
        
        guard let whisper = whisper else {
            return nil
        }
        
        guard !trimmedFrames.isEmpty else {
            return nil
        }
        
        do {
            let inferenceStart = CFAbsoluteTimeGetCurrent()
            
            let segments = try await whisper.transcribe(audioFrames: trimmedFrames)
            
            let inferenceTime = CFAbsoluteTimeGetCurrent() - inferenceStart
            let totalTime = CFAbsoluteTimeGetCurrent() - totalStart
            
            for (idx, segment) in segments.enumerated() {
            }
            
            var fullText = segments.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            
            if isGarbageTranscription(fullText, duration: durationSecs) {
                return nil
            }
            
            return fullText.isEmpty ? nil : fullText
        } catch {
            let totalTime = CFAbsoluteTimeGetCurrent() - totalStart
            return nil
        }
    }
    

     func isGarbageTranscription(_ text: String, duration: Double) -> Bool {
        let lower = text.lowercased()
        
        let hallucinationPhrases = [
            "subtitles by", "amara.org", "copyright", "all rights reserved",
            "captioned by", "transcribed by", "www.", "http", "https",
            "thank you for watching", "thanks for watching", "subscribe",
            "like and subscribe", "please subscribe", "thanks for time",
            "you can do it", "thank you so much", "bye bye", "bye-bye"
        ]
        
        if hallucinationPhrases.contains(where: { lower.contains($0) }) {
            return true
        }
        
        let hindiHallucinations = [
            "धन्यवाद", "नमस्ते", "शुक्रिया", "सब्सक्राइब",
            "ये वीडियो", "इस वीडियो", "चैनल को", "जय हिंद",
            "वंदे मातरम", "बहुत-बहुत धन्यवाद", "देखने के लिए"
        ]
        if hindiHallucinations.contains(where: { lower.contains($0) }) {
            return true
        }
        
        if lower.contains("♪") || lower.contains("🎵") || lower.contains("♫") {
            return true
        }
        
        let words = lower.split(separator: " ")
        
        if words.count >= 3 {
            for i in 0..<(words.count - 2) {
                if words[i] == words[i+1] && words[i+1] == words[i+2] {
                    return true
                }
            }
        }
        
        if words.count > 4 {
            let uniqueWords = Set(words)
            if uniqueWords.count <= 2 {
                return true
            }
        }
        
        if duration < 2.0 && words.count > 10 {
            return true
        }
        
        let foreignScripts = try? NSRegularExpression(pattern: "[\\p{Katakana}\\p{Hiragana}\\p{Han}\\p{Hangul}]", options: [])
        if let regex = foreignScripts {
            let matches = regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            if matches > 2 {
                return true
            }
        }
        
        return false
    }
    
    
    static func convertBufferToFrames(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }
        
        let sampleRate = buffer.format.sampleRate
        let channelCount = Int(buffer.format.channelCount)
        
        var monoSamples = [Float](repeating: 0, count: frameCount)
        if channelCount == 1 {
            monoSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        } else {
            let left = channelData[0]
            let right = channelData[1]
            for i in 0..<frameCount {
                monoSamples[i] = (left[i] + right[i]) / 2.0
            }
        }
        
        let targetSampleRate: Double = 16000.0
        if abs(sampleRate - targetSampleRate) < 1.0 {
            return monoSamples
        }
        
        let ratio = targetSampleRate / sampleRate
        let outputCount = Int(Double(frameCount) * ratio)
        var resampled = [Float](repeating: 0, count: outputCount)
        
        for i in 0..<outputCount {
            let srcIndex = Double(i) / ratio
            let srcIndexInt = Int(srcIndex)
            let frac = Float(srcIndex - Double(srcIndexInt))
            
            if srcIndexInt + 1 < frameCount {
                resampled[i] = monoSamples[srcIndexInt] * (1.0 - frac) + monoSamples[srcIndexInt + 1] * frac
            } else if srcIndexInt < frameCount {
                resampled[i] = monoSamples[srcIndexInt]
            }
        }
        
        return resampled
    }
    
      
     func loadModelSync() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadLock.lock()
            if whisper != nil {
                loadLock.unlock()
                continuation.resume()
                return
            }
            loadLock.unlock()
            
            guard let modelURL = Bundle.main.url(forResource: "ggml-small-q5_1", withExtension: "bin") else {
                continuation.resume()
                return
            }
            
            do {
                let params = Self.makeWhisperParams()
                let whisperInstance = try Whisper(fromFileURL: modelURL, withParams: params)
                self.loadLock.lock()
                self.whisper = whisperInstance
                self.loadLock.unlock()
                continuation.resume()
            } catch {
                continuation.resume()
            }
        }
    }
    
    
     static func makeWhisperParams() -> WhisperParams {
        let params = WhisperParams(strategy: .greedy)
       
        params.language = .english
        
        params.n_threads = 4
        params.translate = false
        params.no_context = true
        params.print_progress = false
        params.print_timestamps = false
        

        params.suppress_blank = true

        params.suppress_non_speech_tokens = true
      
        params.entropy_thold = 2.4           

        params.logprob_thold = -1.0          

        params.single_segment = true

        params.no_speech_thold = 0.6         
        

        let prompt = """
        Shivraj ko aadha kilo Aloo 40 rupees per kg, dedh kg Pyaaz 25 rupees, \
        paav kilo Dhaniya, sawa kilo Dal, dhai kg Lehsun, \
        500g Tamatar at rate 30, 250 gram Adrak, 2 liter Doodh ₹60, \
        3 kg Chawal 80 rupees, 1 kg Cheeni, 2 packet Maggi, \
        5 piece Sabun ₹30, 10 pcs Biscuit, 1 dozen Banana, \
        Paneer 200g ₹80, Ghee 1 ltr, Atta 5 kg ₹250, \
        Gobhi Gajar Matar Palak Bhindi Shimla Mirch Baingan Mooli, \
        Jeera Haldi Namak Tel Maida Besan Suji, \
        sold to Ramesh Sharma, customer Sunil Kumar. Bill banao.
        """
        params.initial_prompt = (prompt as NSString).utf8String
        
        return params
    }
    

    static func trimSilence(from frames: [Float], threshold: Float = 0.01, windowSize: Int = 1600) -> [Float] {
        guard frames.count > windowSize else { return frames }
        

        var startIndex = 0
        for i in stride(from: 0, to: frames.count - windowSize, by: windowSize / 2) {
            let end = min(i + windowSize, frames.count)
            let windowMax = frames[i..<end].map { abs($0) }.max() ?? 0
            if windowMax > threshold {
                startIndex = max(0, i - windowSize) 
                break
            }
        }
        

        var endIndex = frames.count
        for i in stride(from: frames.count - windowSize, through: 0, by: -(windowSize / 2)) {
            let start = max(0, i)
            let end = min(start + windowSize, frames.count)
            let windowMax = frames[start..<end].map { abs($0) }.max() ?? 0
            if windowMax > threshold {
                endIndex = min(frames.count, end + windowSize) 
                break
            }
        }
        
        guard startIndex < endIndex else { return frames }
        return Array(frames[startIndex..<endIndex])
    }
    

     func isGarbageTranscription(_ text: String) -> Bool {
        return isGarbageTranscription(text, duration: 999.0)
    }
}
