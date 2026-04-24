import Foundation

class AuthManager {

    static let shared = AuthManager()

    // MARK: - Configuration

    private let supabaseURL: String = {
        Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
    }()

    private let supabaseAnonKey: String = {
        Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
    }()

    private let session = URLSession.shared

    // MARK: - Session Keys (UserDefaults)

    private let accessTokenKey = "supabaseAccessToken"
    private let refreshTokenKey = "supabaseRefreshToken"
    private let userIdKey = "supabaseUserId"
    private let isLoggedInKey = "supabaseIsLoggedIn"

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Public: Session State
    var isLoggedIn: Bool {
        defaults.bool(forKey: isLoggedInKey)
    }
    var currentUserId: String? {
        defaults.string(forKey: userIdKey)
    }
    var accessToken: String? {
        defaults.string(forKey: accessTokenKey)
    }
    var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty &&
        supabaseURL != "YOUR_SUPABASE_URL" && supabaseAnonKey != "YOUR_SUPABASE_ANON_KEY"
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

    // MARK: - Public: Log Out

    func logOut() {
        defaults.removeObject(forKey: accessTokenKey)
        defaults.removeObject(forKey: refreshTokenKey)
        defaults.removeObject(forKey: userIdKey)
        defaults.set(false, forKey: isLoggedInKey)
        print("[AuthManager] User logged out. Session cleared.")
    }

    // MARK: - Private: Session Parsing

    private func parseAndSaveSession(data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            if let accessToken = json["access_token"] as? String {
                defaults.set(accessToken, forKey: accessTokenKey)
            }
            if let refreshToken = json["refresh_token"] as? String {
                defaults.set(refreshToken, forKey: refreshTokenKey)
            }
            if let user = json["user"] as? [String: Any],
               let userId = user["id"] as? String {
                defaults.set(userId, forKey: userIdKey)
            }

            defaults.set(true, forKey: isLoggedInKey)
            print("[AuthManager] Session saved successfully.")
        } catch {
            print("[AuthManager] Failed to parse session: \(error)")
        }
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
}
