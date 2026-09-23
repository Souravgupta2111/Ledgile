import Foundation

/// Cloud reasoning for Assistant Live: Qwen 3.7 Flash via Supabase gemini-proxy
/// task `assistant-chat`. Roman Hinglish/English only, no Devanagari.
/// Keeps last 10 turns in memory so follow-ups ("aur gud?") resolve.
final class QwenLiveReasoner {

    struct Turn {
        var role: String  // "user" | "assistant"
        var text: String
    }

    private var history: [Turn] = []
    private let maxHistory = 10
    private let session = URLSession.shared

    private var supabaseURL: String {
        let v = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
        return (v.hasPrefix("$(") || v.isEmpty) ? "" : v.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var supabaseAnonKey: String {
        let v = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
        return (v.hasPrefix("$(") || v.isEmpty) ? "" : v.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() { history.removeAll() }

    /// Ask Qwen. Returns (answerText, sqlOrNil).
    /// If the model wants shop data it replies a single line `SQL: SELECT ...`.
    func ask(userText: String, shopPack: String, sqlResult: String? = nil) async throws -> (answer: String, sql: String?) {
        let roman = LiveRomanFilter.toRoman(userText)
        history.append(Turn(role: "user", text: roman))
        history = Array(history.suffix(maxHistory))

        var messages: [[String: String]] = [
            ["role": "system", "content": Self.systemPrompt(shopPack: shopPack)]
        ]
        for t in history.dropLast() {
            messages.append(["role": t.role == "assistant" ? "assistant" : "user", "content": t.text])
        }
        var lastUser = roman
        if let sqlResult, !sqlResult.isEmpty {
            lastUser += "\n[SHOP_SQL_RESULT]\n" + sqlResult.prefix(3000)
        }
        messages.append(["role": "user", "content": lastUser])

        LiveLog.qwen("POST assistant-chat (\(messages.count) msgs)…")
        let text: String
        do {
            text = try await postChat(messages: messages)
        } catch {
            // One retry on empty provider replies (overloaded model) — else surface.
            if (error as NSError).code == 6 {
                LiveLog.qwen("empty reply — one retry in 1s")
                try await Task.sleep(nanoseconds: 1_000_000_000)
                text = try await postChat(messages: messages)
            } else {
                throw error
            }
        }
        LiveLog.qwen("reply (\(text.count) chars): '\(text.prefix(160))'")
        let clean = LiveRomanFilter.toRoman(text)

        // SQL tool line?
        let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().hasPrefix("SQL:") {
            let sql = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            return ("", sql)
        }
        history.append(Turn(role: "assistant", text: clean))
        history = Array(history.suffix(maxHistory))
        return (clean, nil)
    }

    /// Second pass: feed SQL result back to get the final spoken answer.
    func answerWithSQLResult(_ sqlResult: String, shopPack: String) async throws -> String {
        let (answer, _) = try await ask(userText: "Use the SHOP_SQL_RESULT above and answer in Roman only.", shopPack: shopPack, sqlResult: sqlResult)
        return answer
    }

    static func systemPrompt(shopPack: String) -> String {
        """
        You are B-easy shop assistant. The shopkeeper speaks Hinglish in Roman script.
        RULES (strict):
        - Reply ONLY in Roman script (Hinglish/English). NEVER use Devanagari.
        - If user speaks Hindi -> reply Hindi in Roman. English -> English. Hinglish -> Hinglish Roman.
        - You read the phone ledger. If you need numbers, reply ONE line: SQL: SELECT ... (read-only, tables: transactions, transaction_items, items, daily_summaries, customers, suppliers, customer_payments, supplier_payments).
        - Else reply directly, short (1-3 lines), then ONE follow-up question.
        - Never invent numbers. If data missing say: data nahi mila, Stock tab dekho.
        SHOP SNAPSHOT:
        \(shopPack.prefix(3500))
        """
    }

    private func postChat(messages: [[String: String]]) async throws -> String {
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else {
            throw NSError(domain: "QwenLive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Supabase not configured"])
        }
        guard let jwt = AuthManager.shared.accessToken else {
            throw NSError(domain: "QwenLive", code: 2, userInfo: [NSLocalizedDescriptionKey: "Login required for Live"])
        }
        guard let url = URL(string: "\(supabaseURL)/functions/v1/gemini-proxy") else {
            throw NSError(domain: "QwenLive", code: 3, userInfo: [NSLocalizedDescriptionKey: "Bad Edge URL"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.timeoutInterval = 25
        let body: [String: Any] = ["task": "assistant-chat", "messages": messages, "maxOutputTokens": 400, "temperature": 0.1]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        let rawPrefix = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
        if let http = resp as? HTTPURLResponse {
            LiveLog.qwen("HTTP \(http.statusCode), body \(data.count) bytes: \(rawPrefix)")
        }
        if let http = resp as? HTTPURLResponse, http.statusCode == 402 {
            throw NSError(domain: "QwenLive", code: 4, userInfo: [NSLocalizedDescriptionKey: "AI limit reached. Please try again tomorrow or upgrade to Pro."])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            LiveLog.qwen("non-JSON body: \(rawPrefix)")
            throw NSError(domain: "QwenLive", code: 5, userInfo: [NSLocalizedDescriptionKey: "Assistant error: \(rawPrefix.prefix(120))"])
        }
        // Surface the Edge/OpenRouter message instead of hiding it.
        if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
            LiveLog.qwen("edge error: \(msg)")
            throw NSError(domain: "QwenLive", code: 6, userInfo: [NSLocalizedDescriptionKey: "Assistant error: \(msg.prefix(160))"])
        }
        guard let cands = json["candidates"] as? [[String: Any]],
              let content = cands.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            LiveLog.qwen("no candidates in: \(rawPrefix)")
            throw NSError(domain: "QwenLive", code: 5, userInfo: [NSLocalizedDescriptionKey: "No response from the assistant."])
        }
        UsageTracker.shared.record(.voice)
        return text
    }
}

/// Enforces Roman-only text: strips Devanagari via compact transliteration map.
/// Whisper already runs with language=.english so output is Roman in practice;
/// this is the safety net (no Devanagari ever reaches bubbles/TTS text).
enum LiveRomanFilter {
    // Pairs (not a literal dict) so a repeated key can never crash again —
    // last value wins via uniquingKeysWith.
    private static let pairs: [(Character, String)] = [
        ("अ", "a"), ("आ", "aa"), ("इ", "i"), ("ई", "ee"), ("उ", "u"), ("ऊ", "oo"),
        ("ए", "e"), ("ऐ", "ai"), ("ओ", "o"), ("औ", "au"), ("अं", "an"), ("अः", "ah"),
        ("क", "k"), ("ख", "kh"), ("ग", "g"), ("घ", "gh"), ("ङ", "ng"),
        ("च", "ch"), ("छ", "chh"), ("ज", "j"), ("झ", "jh"), ("ञ", "ny"),
        ("ट", "t"), ("ठ", "th"), ("ड", "d"), ("ढ", "dh"), ("ण", "n"),
        ("त", "t"), ("थ", "th"), ("द", "d"), ("ध", "dh"), ("न", "n"),
        ("प", "p"), ("फ", "ph"), ("ब", "b"), ("भ", "bh"), ("म", "m"),
        ("य", "y"), ("र", "r"), ("ल", "l"), ("व", "v"), ("श", "sh"),
        ("ष", "sh"), ("स", "s"), ("ह", "h"), ("़", ""), ("्", ""), ("ँ", "n"),
        ("ं", "n"), ("ः", "h"), ("ॉ", "o"), ("ो", "o"), ("ौ", "au"),
        ("ै", "ai"), ("े", "e"), ("ू", "oo"), ("ु", "u"), ("ी", "ee"),
        ("ि", "i"), ("ा", "aa"), ("।", "."), ("॥", "."),
        ("०", "0"), ("१", "1"), ("२", "2"), ("३", "3"), ("४", "4"),
        ("५", "5"), ("६", "6"), ("७", "7"), ("८", "8"), ("९", "9")
    ]
    private static let map: [Character: String] = Dictionary(pairs, uniquingKeysWith: { _, last in last })

    static func toRoman(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            if let r = map[ch] { out += r; continue }
            let v = ch.unicodeScalars.first?.value ?? 0
            if v >= 0x0900 && v <= 0x097F { continue } // drop other Devanagari marks
            out.append(ch)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whisper loops on noise tails ("X? X? X?", "Kheer, Kheer").
    /// Collapse consecutive duplicate sentences AND duplicate words into one.
    static func dedupeRepeats(_ text: String) -> String {
        let parts = text.components(separatedBy: ". ")
        var kept: [String] = []
        var lastNorm = ""
        for p in parts {
            let norm = p.lowercased()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if norm.isEmpty { continue }
            if norm == lastNorm { continue }
            lastNorm = norm
            kept.append(collapseWordRuns(p.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return kept.joined(separator: ". ")
    }

    private static func collapseWordRuns(_ sentence: String) -> String {
        let words = sentence.split(separator: " ").map(String.init)
        var out: [String] = []
        var last = ""
        for w in words {
            let norm = w.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if !norm.isEmpty, norm == last { continue }
            last = norm.isEmpty ? last : norm
            out.append(w)
        }
        return out.joined(separator: " ")
    }
}
