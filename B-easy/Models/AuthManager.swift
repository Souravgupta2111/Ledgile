import Foundation

nonisolated class AuthManager: @unchecked Sendable {

    static let shared = AuthManager()

    // MARK: - Configuration

    private static func resolveConfigValue(key: String, plistValue: String?) -> String {
        if let val = plistValue, !val.isEmpty, !val.hasPrefix("$(") {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        print("[AuthManager] Failed to resolve \(key) from Info.plist.")
        return ""
    }

    private let supabaseURL: String = {
        resolveConfigValue(key: "SUPABASE_URL", plistValue: Bundle.main.infoDictionary?["SUPABASE_URL"] as? String)
    }()

    private let supabaseAnonKey: String = {
        resolveConfigValue(key: "SUPABASE_ANON_KEY", plistValue: Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String)
    }()

    private let session = URLSession.shared

    // MARK: - Session Keys

    private let accessTokenKey = "supabaseAccessToken"
    private let refreshTokenKey = "supabaseRefreshToken"
    private let userIdKey = "supabaseUserId"
    private let isLoggedInKey = "supabaseIsLoggedIn"
    private let appleEmailKey = "appleSignInEmail"

    private let keychain = KeychainHelper.shared
    private let defaults = UserDefaults.standard

    private init() {
        // One-time migration: move tokens from UserDefaults to Keychain
        migrateTokensToKeychainIfNeeded()
    }

    // MARK: - Public: Session State
    var isLoggedIn: Bool {
        defaults.bool(forKey: isLoggedInKey)
    }
    var currentUserId: String? {
        keychain.read(forKey: userIdKey)
    }
    var accessToken: String? {
        keychain.read(forKey: accessTokenKey)
    }
    var appleEmail: String? {
        keychain.read(forKey: appleEmailKey)
    }
    var configuredSupabaseURL: String { supabaseURL }
    var configuredSupabaseAnonKey: String { supabaseAnonKey }
    var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty &&
        supabaseURL != "YOUR_SUPABASE_URL" && supabaseAnonKey != "YOUR_SUPABASE_ANON_KEY"
    }

    func saveAppleEmail(_ email: String?) {
        if let email = email, !email.isEmpty {
            keychain.save(email, forKey: appleEmailKey)
        }
    }

    // MARK: - Public: Send OTP
    func sendOTP(phone: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        guard isConfigured else {
            DispatchQueue.main.async {
                completion(.failure(.notConfigured))
            }
            return
        }

        let urlString = "\(supabaseURL)/auth/v1/otp"
        print("[AuthManager] sendOTP urlString is: '\(urlString)'")
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(.failure(.invalidURL)) }
            return
        }

        let body: [String: Any] = [
            "phone": phone
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 15

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            DispatchQueue.main.async { completion(.failure(.jsonError(error.localizedDescription))) }
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(.network(error.localizedDescription))) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(.unknown)) }
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                print("[AuthManager] OTP sent successfully to \(phone)")
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                let errorMessage = self.extractErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
                print("[AuthManager] OTP send failed: \(errorMessage)")
                DispatchQueue.main.async { completion(.failure(.server(errorMessage))) }
            }
        }.resume()
    }

    // MARK: - Public: Verify OTP

    func verifyOTP(phone: String, code: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        guard isConfigured else {
            DispatchQueue.main.async { completion(.failure(.notConfigured)) }
            return
        }

        let urlString = "\(supabaseURL)/auth/v1/verify"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(.failure(.invalidURL)) }
            return
        }

        let body: [String: Any] = [
            "phone": phone,
            "token": code,
            "type": "sms"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 15

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            DispatchQueue.main.async { completion(.failure(.jsonError(error.localizedDescription))) }
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(.network(error.localizedDescription))) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(.unknown)) }
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                // Parse the session response
                if let data = data {
                    self.parseAndSaveSession(data: data)
                }
                print("[AuthManager] OTP verified successfully for \(phone)")
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                let errorMessage = self.extractErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
                print("[AuthManager] OTP verification failed: \(errorMessage)")
                DispatchQueue.main.async { completion(.failure(.server(errorMessage))) }
            }
        }.resume()
    }

    // MARK: - Public: Apple Sign In
    func signInWithApple(idToken: String, nonce: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        guard isConfigured else {
            DispatchQueue.main.async { completion(.failure(.notConfigured)) }
            return
        }

        let urlString = "\(supabaseURL)/auth/v1/token?grant_type=id_token"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(.failure(.invalidURL)) }
            return
        }

        let body: [String: Any] = [
            "id_token": idToken,
            "nonce": nonce,
            "provider": "apple"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 15

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            DispatchQueue.main.async { completion(.failure(.jsonError(error.localizedDescription))) }
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(.network(error.localizedDescription))) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(.unknown)) }
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                if let data = data {
                    self.parseAndSaveSession(data: data)
                }
                print("[AuthManager] Apple Sign-In successful")
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                let errorMessage = self.extractErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
                print("[AuthManager] Apple Sign-In failed: \(errorMessage)")
                DispatchQueue.main.async { completion(.failure(.server(errorMessage))) }
            }
        }.resume()
    }

    // MARK: - Public: Log Out

    func logOut() {
        // Invalidate server session if possible
        if isConfigured, let token = accessToken {
            let urlString = "\(supabaseURL)/auth/v1/logout"
            if let url = URL(string: urlString) {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 5
                session.dataTask(with: request) { _, _, _ in }.resume()
            }
        }

        // Clear Keychain tokens
        keychain.delete(forKey: accessTokenKey)
        keychain.delete(forKey: refreshTokenKey)
        keychain.delete(forKey: userIdKey)
        keychain.delete(forKey: appleEmailKey)
        defaults.set(false, forKey: isLoggedInKey)
        defaults.removeObject(forKey: "userDidCompleteOnboarding")
        defaults.removeObject(forKey: AuthNavigationHelper.profileCompleteKey)
        defaults.removeObject(forKey: AuthNavigationHelper.needsLaunchPlanKey)
        UsageTracker.shared.clearAccountLocalState()
        print("[AuthManager] User logged out. Session cleared from Keychain.")
    }

    // MARK: - Public: Delete Account

    func deleteAccount(completion: @escaping (Result<Void, AuthError>) -> Void) {
        guard isConfigured, let token = accessToken else {
            // Not configured or no session — just clear local data
            logOut()
            DispatchQueue.main.async { completion(.success(())) }
            return
        }

        // Call Supabase to delete the authenticated user via RPC
        let urlString = "\(supabaseURL)/rest/v1/rpc/delete_user"
        guard let url = URL(string: urlString) else {
            logOut()
            DispatchQueue.main.async { completion(.success(())) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        session.dataTask(with: request) { [weak self] _, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(.network(error.localizedDescription))) }
                return
            }
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                DispatchQueue.main.async {
                    completion(.failure(.network("Could not delete account (HTTP \(httpResponse.statusCode)).")))
                }
                return
            }
            self?.logOut()
            DispatchQueue.main.async { completion(.success(())) }
        }.resume()
    }

    // MARK: - Public: Refresh Session

    func refreshSessionIfNeeded(completion: ((Bool) -> Void)? = nil) {
        guard isConfigured,
              let refreshToken = keychain.read(forKey: refreshTokenKey),
              !refreshToken.isEmpty else {
            completion?(false)
            return
        }

        let urlString = "\(supabaseURL)/auth/v1/token?grant_type=refresh_token"
        guard let url = URL(string: urlString) else {
            completion?(false)
            return
        }

        let body: [String: Any] = ["refresh_token": refreshToken]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion?(false)
            return
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[AuthManager] Token refresh network error: \(error)")
                completion?(false)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  let data = data else {
                print("[AuthManager] Token refresh failed: invalid response.")
                completion?(false)
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                self.parseAndSaveSession(data: data)
                print("[AuthManager] Token refreshed successfully.")
                completion?(true)
            } else {
                print("[AuthManager] Token refresh failed with status \(httpResponse.statusCode).")
                if (400...499).contains(httpResponse.statusCode) {
                    print("[AuthManager] Refresh token invalid/expired, logging out.")
                    self.logOut()
                }
                completion?(false)
            }
        }.resume()
    }

    // MARK: - Private: Session Parsing

    private func parseAndSaveSession(data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            if let accessToken = json["access_token"] as? String {
                keychain.save(accessToken, forKey: accessTokenKey)
            }
            if let refreshToken = json["refresh_token"] as? String {
                keychain.save(refreshToken, forKey: refreshTokenKey)
            }
            if let user = json["user"] as? [String: Any],
               let userId = user["id"] as? String {
                keychain.save(userId, forKey: userIdKey)
            }

            defaults.set(true, forKey: isLoggedInKey)
            print("[AuthManager] Session saved to Keychain.")
        } catch {
            print("[AuthManager] Failed to parse session: \(error)")
        }
    }

    // MARK: - Public: Profile Sync

    func updateUserProfile(name: String?, shopName: String?, phone: String?, email: String? = nil, completion: ((Error?) -> Void)? = nil) {
        guard isConfigured,
              let userId = currentUserId,
              let token = accessToken else {
            completion?(nil)
            return
        }

        let urlString = "\(supabaseURL)/rest/v1/user_profiles"
        guard let url = URL(string: urlString) else { return }

        var body: [String: Any] = [
            "id": userId,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let name = name { body["owner_name"] = name }
        if let shopName = shopName { body["shop_name"] = shopName }
        if let phone = phone { body["phone"] = phone }
        if let email = email { body["email"] = email }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion?(error)
            return
        }

        session.dataTask(with: request) { _, response, error in
            if let error {
                completion?(error)
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion?(NSError(domain: "AuthManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Could not save profile (HTTP \(http.statusCode))."]))
                return
            }
            completion?(nil)
        }.resume()
    }
    
    func fetchUserProfile(completion: @escaping ([String: Any]?) -> Void) {
        guard isConfigured,
              let userId = currentUserId,
              let token = accessToken else {
            completion(nil)
            return
        }

        // Query Supabase for the specific user id
        let urlString = "\(supabaseURL)/rest/v1/user_profiles?id=eq.\(userId)&select=owner_name,shop_name,phone,email"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        session.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }

            // Supabase returns an array of matching rows
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let profile = jsonArray.first {
                completion(profile)
            } else {
                completion(nil)
            }
        }.resume()
    }

    func fetchAuthUserEmail(completion: @escaping (String?) -> Void) {
        guard isConfigured, let token = accessToken else {
            completion(nil)
            return
        }
        let urlString = "\(supabaseURL)/auth/v1/user"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        session.dataTask(with: request) { data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            let email = (json["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            completion((email?.isEmpty == false) ? email : nil)
        }.resume()
    }

    private func extractErrorMessage(from data: Data?) -> String? {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["error_description"] as? String ?? json["msg"] as? String ?? json["message"] as? String
    }

    // MARK: - Error Type

    enum AuthError: Error, LocalizedError {
        case notConfigured
        case invalidURL
        case network(String)
        case server(String)
        case jsonError(String)
        case unknown

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Supabase is not configured. Please add your credentials."
            case .invalidURL: return "Invalid Supabase URL."
            case .network(let msg): return "Network error: \(msg)"
            case .server(let msg): return msg
            case .jsonError(let msg): return "JSON error: \(msg)"
            case .unknown: return "An unknown error occurred."
            }
        }
    }
    // MARK: - Migration (UserDefaults → Keychain)

    private func migrateTokensToKeychainIfNeeded() {
        let migrationKey = "didMigrateTokensToKeychain"
        guard !defaults.bool(forKey: migrationKey) else { return }

        // Move tokens from UserDefaults to Keychain if they exist
        if let token = defaults.string(forKey: accessTokenKey) {
            keychain.save(token, forKey: accessTokenKey)
            defaults.removeObject(forKey: accessTokenKey)
        }
        if let token = defaults.string(forKey: refreshTokenKey) {
            keychain.save(token, forKey: refreshTokenKey)
            defaults.removeObject(forKey: refreshTokenKey)
        }
        if let userId = defaults.string(forKey: userIdKey) {
            keychain.save(userId, forKey: userIdKey)
            defaults.removeObject(forKey: userIdKey)
        }

        defaults.set(true, forKey: migrationKey)
        print("[AuthManager] Migrated tokens from UserDefaults to Keychain.")
    }
}
