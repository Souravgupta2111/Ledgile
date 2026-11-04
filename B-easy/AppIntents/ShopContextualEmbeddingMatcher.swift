import Foundation
import NaturalLanguage

public enum ShopIntentMatch: Hashable, Sendable {
    case todaySummary
    case udhaarSummary
    case lowStock
    case expiry
    case recentTransactions
    case partyBalance(partyName: String?)
    case unknown
}

public final class ShopContextualEmbeddingMatcher: @unchecked Sendable {
    public static let shared = ShopContextualEmbeddingMatcher()

    private let enEmbedding: NLContextualEmbedding?
    private let hiEmbedding: NLContextualEmbedding?

    public init() {
        self.enEmbedding = NLContextualEmbedding(language: .english)
        self.hiEmbedding = NLContextualEmbedding(language: NLLanguage("hi"))
        _ = try? enEmbedding?.load()
        _ = try? hiEmbedding?.load()
    }

    /// Background asset request and model pre-warming so embeddings are ready when user asks Siri.
    public func warmup() {
        if let hi = hiEmbedding, !hi.hasAvailableAssets {
            hi.requestAssets { _, _ in
                _ = try? hi.load()
            }
        }
        if let en = enEmbedding, !en.hasAvailableAssets {
            en.requestAssets { _, _ in
                _ = try? en.load()
            }
        }
    }

    /// Matches a freeform spoken or typed query into one of the 6 read-only shop intents.
    public func match(query: String) -> ShopIntentMatch {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .unknown }

        // 1. Check for specific party balance query patterns
        if let partyMatch = extractPartyBalance(from: cleaned) {
            return partyMatch
        }

        // 2. Score intents using n-gram / semantic keyword matcher + contextual embeddings
        let scores = scoreIntents(query: cleaned)
        guard let best = scores.max(by: { $0.value < $1.value }), best.value >= 1.3 else {
            return .unknown
        }

        return best.key
    }

    /// Extracts party name from Hinglish/Hindi or English phrased balance inquiries.
    private func extractPartyBalance(from query: String) -> ShopIntentMatch? {
        let lower = query.lowercased()

        let hinglishSuffixes = [
            " ka kitna udhaar", " ka kitna udhar", " ka kitna baki", " ka kitna baaki",
            " ka udhaar", " ka udhar", " ka balance", " ka hisaab", " ka hisab",
            " ka khata", " ke paise", " ka baaki", " ka baki", " ki udhari",
            " का कितना उधार", " का कितना बाकी",
            " का उधार", " का बैलेंस", " का हिसाब", " का खाता", " का बाकी"
        ]

        for suffix in hinglishSuffixes {
            if let range = lower.range(of: suffix) {
                let namePart = String(query[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedName = cleanExtractedName(namePart)
                if isValidPartyName(cleanedName) {
                    return .partyBalance(partyName: cleanedName)
                }
            }
        }

        let englishPrefixes = [
            "balance of ", "how much does ", "how much does party ", "udhaar of ", "account of "
        ]
        for prefix in englishPrefixes {
            if lower.hasPrefix(prefix) {
                var rest = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if rest.lowercased().hasSuffix(" owe") {
                    rest = String(rest.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if rest.lowercased().hasSuffix(" owe me") {
                    rest = String(rest.dropLast(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let cleanedName = cleanExtractedName(rest)
                if isValidPartyName(cleanedName) {
                    return .partyBalance(partyName: cleanedName)
                }
            }
        }

        return nil
    }

    private func cleanExtractedName(_ raw: String) -> String {
        var name = raw
        let prefixesToRemove = ["tell me ", "show me ", "ask beasy ", "beasy ", "b-easy ", "check "]
        for p in prefixesToRemove {
            if name.lowercased().hasPrefix(p) {
                name = String(name.dropFirst(p.count))
            }
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func isValidPartyName(_ name: String) -> Bool {
        guard !name.isEmpty && name.count <= 60 else { return false }
        let lower = name.lowercased()
        let forbidden = ["total", "sabka", "summary", "kitna", "bazaar", "market", "today", "aaj", "kya", "recent", "low stock", "expiry"]
        for f in forbidden {
            if lower == f || lower.hasPrefix(f + " ") { return false }
        }
        return true
    }

    private func scoreIntents(query: String) -> [ShopIntentMatch: Double] {
        let norm = normalizeText(query)
        var scores: [ShopIntentMatch: Double] = [
            .todaySummary: 0,
            .udhaarSummary: 0,
            .lowStock: 0,
            .expiry: 0,
            .recentTransactions: 0
        ]

        // Semantic keyword weights across English, Devanagari Hindi, and Hinglish
        let keywords: [(ShopIntentMatch, [String], Double)] = [
            // Today summary: generic temporal tokens get 0.8, business tokens get 2.0, compound phrases get 3.5
            (.todaySummary, ["today", "aaj", "aajka", "aajki", "आज", "daily"], 0.8),
            (.todaySummary, ["bikri", "dhandha", "kamai", "munafa", "profit", "revenue", "बिक्री", "मुनाफा", "बिका", "बेचा"], 2.0),
            (.todaySummary, ["today sale", "today's sale", "today sales", "today's sales", "aaj ki sale", "aaj ka hisab", "aaj ka hisaab", "aaj ki bikri", "aaj kitna", "today summary", "how much did i sell", "aaj kitne bill", "सामान बिका", "सामान बेचा"], 3.5),

            // Udhaar summary
            (.udhaarSummary, ["udhar", "udhaar", "udhari", "उधार", "baaki", "baki", "बाकी", "receivable", "payable", "credit", "debt", "dues", "phasa", "fasa", "मार्केट", "फंसा", "market", "bazaar"], 1.5),
            (.udhaarSummary, ["udhaar summary", "kitna udhaar", "total udhaar", "udhar baki", "who owes", "market udhaar", "paisa phasa", "kitna lena", "kitna dena", "पैसा फंसा", "मार्केट में"], 3.0),

            // Low stock
            (.lowStock, ["stock", "स्टॉक", "khatam", "खत्म", "reorder", "inventory", "threshold", "running low", "kam", "कम", "maal", "shortage", "restock"], 1.5),
            (.lowStock, ["low stock", "stock kam", "khatam ho", "reorder alert", "out of stock", "restock alerts", "stock bacha", "सामान खत्म", "कम स्टॉक", "खत्म हो रहा"], 3.0),

            // Expiry
            (.expiry, ["expir", "expire", "expired", "expiry", "एक्सपायर", "एक्सपायरी", "date", "kharab", "batch", "batches", "validity"], 1.5),
            (.expiry, ["expiry alert", "kya expire", "expire ho raha", "expiring soon", "date nikal", "batch expiry"], 3.0),

            // Recent transactions
            (.recentTransactions, ["transaction", "transactions", "bill", "bills", "बिल", "invoice", "invoices", "recent", "last", "pichla", "pichle", "aakhri", "latest", "order", "orders", "आखिरी", "पिछला"], 1.5),
            (.recentTransactions, ["recent bills", "recent transactions", "last bill", "pichla bill", "pichle bills", "aakhri bill", "last sale", "latest bill", "pichla transaction"], 3.0)
        ]

        for (intent, tokens, weight) in keywords {
            for token in tokens {
                let tokenNorm = normalizeText(token)
                if norm.contains(tokenNorm) {
                    scores[intent, default: 0] += weight
                }
            }
        }

        // Subword n-gram similarity against prototype sentence clusters
        let prototypes: [(ShopIntentMatch, [String])] = [
            (.todaySummary, ["today sales revenue profit", "aaj ki sale bikri munafa hisaab", "today summary bills sold", "aaj kitna bika kitni kamai", "aaj kitne bill bane", "आज की कुल बिक्री और मुनाफा आज कितना सामान बिका"]),
            (.udhaarSummary, ["udhaar summary total receivables payables", "kitna udhaar baaki hai bazaar me paisa phasa", "customers owe supplier payable", "total credit dues", "कुल कितना उधार बाकी है मार्केट में कितना पैसा फंसा है"]),
            (.lowStock, ["low stock items threshold restock", "stock kam hai kaunsa saaman khatam ho raha hai", "items running low inventory alert", "khatam hone wala maal", "कौन सा सामान खत्म हो रहा है कम स्टॉक"]),
            (.expiry, ["expiry alerts items expired soon", "kya expire ho raha hai kiski expiry paas hai", "batch expired alert date nikal gayi", "kharab hone wala samaan", "क्या एक्सपायर हो रहा है एक्सपायरी"]),
            (.recentTransactions, ["recent transactions bills invoices last sale", "aakhri bill kitne ka tha pichla bill dikhao", "latest sales orders bills summary", "pichle teen bill", "हाल के बिल आखिरी बिल"])
        ]

        for (intent, protos) in prototypes {
            var maxSim = 0.0
            for proto in protos {
                let sim = nGramSimilarity(norm, normalizeText(proto))
                if sim > maxSim { maxSim = sim }
            }
            scores[intent, default: 0] += maxSim * 2.0
        }

        return scores
    }

    private func normalizeText(_ text: String) -> String {
        var str = text.lowercased()
        // Phonetic vowel folding for Hinglish transliterations
        str = str.replacingOccurrences(of: "aa", with: "a")
        str = str.replacingOccurrences(of: "ee", with: "i")
        str = str.replacingOccurrences(of: "oo", with: "u")
        str = str.replacingOccurrences(of: "dh", with: "d")
        str = str.replacingOccurrences(of: "bh", with: "b")
        str = str.replacingOccurrences(of: "kh", with: "k")
        let clean = str.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) }
        return String(clean).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nGramSimilarity(_ s1: String, _ s2: String) -> Double {
        let set1 = characterNGrams(s1, n: 3)
        let set2 = characterNGrams(s2, n: 3)
        guard !set1.isEmpty && !set2.isEmpty else { return 0 }
        let intersection = set1.intersection(set2)
        return Double(2 * intersection.count) / Double(set1.count + set2.count)
    }

    private func characterNGrams(_ s: String, n: Int) -> Set<String> {
        let chars = Array(s)
        guard chars.count >= n else { return [s] }
        var result = Set<String>()
        for i in 0...(chars.count - n) {
            result.insert(String(chars[i..<(i + n)]))
        }
        return result
    }
}
