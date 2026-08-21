import Foundation
import UIKit

nonisolated final class CloudBackupService: @unchecked Sendable {

    static let shared = CloudBackupService()

    private let bucket = "ledger-backups"
    private let objectName = "ledgile.sqlite"
    private let lastDailyKey = "cloudBackup.lastDailyDate"
    private let lastSuccessKey = "cloudBackup.lastSuccessAt"
    private let lastAlertKey = "cloudBackup.lastAlertAt"

    private let lock = NSLock()
    private var isUploading = false
    private var needsRetry = false
    private var pendingCompletions: [(Result<Void, Error>) -> Void] = []

    private init() {}

    enum BackupError: LocalizedError {
        case notSignedIn
        case notConfigured
        case localCopyFailed
        case http(Int, String)
        case emptyFile

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to upload a cloud backup."
            case .notConfigured: return "Cloud backup is not configured."
            case .localCopyFailed: return "Could not create a local copy of the ledger."
            case .http(let code, let body): return "Cloud upload failed (HTTP \(code)): \(body)"
            case .emptyFile: return "No cloud backup file was found."
            }
        }
    }

    func lastSuccessDescription() -> String {
        let ts = UserDefaults.standard.double(forKey: lastSuccessKey)
        guard ts > 0 else { return "Never" }
        let date = Date(timeIntervalSince1970: ts)
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df.string(from: date)
    }

    func uploadIfDueForDaily() {
        guard AuthManager.shared.isLoggedIn else { return }
        let today = Self.dayStamp(Date())
        let last = UserDefaults.standard.string(forKey: lastDailyKey)
        guard last != today else { return }
        uploadLedger(reportFailure: true) { _ in }
    }

    func uploadAfterSale() {
        guard AuthManager.shared.isLoggedIn else { return }
        uploadLedger(reportFailure: true) { _ in }
    }

    func uploadLedger(completion: @escaping (Result<Void, Error>) -> Void) {
        uploadLedger(reportFailure: false, completion: completion)
    }

    private func uploadLedger(reportFailure: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        pendingCompletions.append { result in
            if reportFailure, case .failure(let error) = result {
                Self.presentFailure(error)
            }
            completion(result)
        }
        if isUploading {
            needsRetry = true
            lock.unlock()
            return
        }
        isUploading = true
        lock.unlock()
        startUpload()
    }

    private func startUpload() {
        let auth = AuthManager.shared
        guard auth.isConfigured else {
            finish(.failure(BackupError.notConfigured), allowRetry: false)
            return
        }
        guard let userId = auth.currentUserId, let token = auth.accessToken else {
            finish(.failure(BackupError.notSignedIn), allowRetry: false)
            return
        }

        let anonKey = auth.configuredSupabaseAnonKey
        let baseURL = auth.configuredSupabaseURL

        LedgerIO.queue.async {
            guard let localURL = BackupService.shared.createBackup() else {
                self.finish(.failure(BackupError.localCopyFailed))
                return
            }
            do {
                let data = try Data(contentsOf: localURL)
                try? FileManager.default.removeItem(at: localURL)
                self.putObject(data: data, userId: userId, token: token, anonKey: anonKey, baseURL: baseURL) { result in
                    if case .success = result {
                        UserDefaults.standard.set(Self.dayStamp(Date()), forKey: self.lastDailyKey)
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self.lastSuccessKey)
                    }
                    self.finish(result)
                }
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    private func finish(_ result: Result<Void, Error>, allowRetry: Bool = true) {
        lock.lock()
        let callbacks = pendingCompletions
        pendingCompletions = []
        let retry = allowRetry && needsRetry
        needsRetry = false
        if retry {
            lock.unlock()
            DispatchQueue.main.async {
                callbacks.forEach { $0(result) }
            }
            startUpload()
        } else {
            isUploading = false
            lock.unlock()
            DispatchQueue.main.async {
                callbacks.forEach { $0(result) }
            }
        }
    }

    func downloadLedger(completion: @escaping (Result<URL, Error>) -> Void) {
        let auth = AuthManager.shared
        guard auth.isConfigured else {
            DispatchQueue.main.async { completion(.failure(BackupError.notConfigured)) }
            return
        }
        guard let userId = auth.currentUserId, let token = auth.accessToken else {
            DispatchQueue.main.async { completion(.failure(BackupError.notSignedIn)) }
            return
        }

        let path = "\(userId)/\(objectName)"
        let encoded = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        guard let url = URL(string: "\(auth.configuredSupabaseURL)/storage/v1/object/\(bucket)/\(encoded)") else {
            DispatchQueue.main.async { completion(.failure(BackupError.notConfigured)) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(auth.configuredSupabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            guard (200...299).contains(code), let data, !data.isEmpty else {
                let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(.failure(BackupError.http(code, body))) }
                return
            }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("ledgile-cloud-restore.sqlite")
            do {
                try data.write(to: dest, options: .atomic)
                DispatchQueue.main.async { completion(.success(dest)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    private func putObject(data: Data, userId: String, token: String, anonKey: String, baseURL: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let path = "\(userId)/\(objectName)"
        let encoded = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        guard let url = URL(string: "\(baseURL)/storage/v1/object/\(bucket)/\(encoded)") else {
            completion(.failure(BackupError.notConfigured))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        request.timeoutInterval = 60

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            if (200...299).contains(code) {
                completion(.success(()))
                return
            }
            let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
            completion(.failure(BackupError.http(code, body)))
        }.resume()
    }

    private static func presentFailure(_ error: Error) {
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: CloudBackupService.shared.lastAlertKey)
        guard now - last > 30 else { return }
        UserDefaults.standard.set(now, forKey: CloudBackupService.shared.lastAlertKey)

        guard let presenter = topViewController() else { return }
        if presenter.presentedViewController is UIAlertController { return }
        let alert = UIAlertController(
            title: "Cloud backup failed",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }

    private static func dayStamp(_ date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar.current
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}
