import Foundation

/// Single console channel for the whole Live voice pipeline.
/// Console me `[Live][mic|whisper|qwen|tts|ui]` filter laga ke dekho.
enum LiveLog {
    static var enabled = true

    static func log(_ tag: String, _ msg: String) {
        guard enabled else { return }
        let t = String(format: "%.1f", CFAbsoluteTimeGetCurrent().truncatingRemainder(dividingBy: 100000))
        print("[Live][\(tag)][\(t)s] \(msg)")
    }

    static func mic(_ msg: String) { log("mic", msg) }
    static func whisper(_ msg: String) { log("whisper", msg) }
    static func qwen(_ msg: String) { log("qwen", msg) }
    static func tts(_ msg: String) { log("tts", msg) }
    static func ui(_ msg: String) { log("ui", msg) }
    static func sql(_ msg: String) { log("sql", msg) }
}
