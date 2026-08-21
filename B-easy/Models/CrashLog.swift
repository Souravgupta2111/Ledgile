import Foundation

private func beasyUncaughtExceptionHandler(_ exception: NSException) {
    let text = """
    \(Date())
    \(exception.name.rawValue): \(exception.reason ?? "")
    \(exception.callStackSymbols.joined(separator: "\n"))
    """
    CrashLog.write(text)
}

/// Writes uncaught exceptions to disk for App Store / TestFlight support.
enum CrashLog {
    static func install() {
        NSSetUncaughtExceptionHandler(beasyUncaughtExceptionHandler)
    }

    fileprivate static func write(_ text: String) {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let folder = dir.appendingPathComponent("B-easy", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("last-crash.log")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
