import Foundation

/// A persistent cache for repetitive Voice AI requests.

final class RequestCacheManager {
    static let shared = RequestCacheManager()
    
    private let userDefaults = UserDefaults.standard
    private let saleCacheKey = "GeminiSaleVoiceCache"
    private let purchaseCacheKey = "GeminiPurchaseVoiceCache"
    
    // Max entries to prevent unbounded growth
    private let maxCacheSize = 2000
    
    private init() {}
    
    // MARK: - Sale Cache
    
    func getCachedSaleResponse(for text: String) -> String? {
        let normalized = normalize(text)
        let cache = userDefaults.dictionary(forKey: saleCacheKey) as? [String: String] ?? [:]
        return cache[normalized]
    }
    
    func cacheSaleResponse(for text: String, json: String) {
        let normalized = normalize(text)
        var cache = userDefaults.dictionary(forKey: saleCacheKey) as? [String: String] ?? [:]
        
        // Evict randomly if full to prevent bloat
        if cache.count >= maxCacheSize {
            if let randomKey = cache.keys.randomElement() { cache.removeValue(forKey: randomKey) }
        }
        
        cache[normalized] = json
        userDefaults.set(cache, forKey: saleCacheKey)
    }
    
    // MARK: - Purchase Cache
    
    func getCachedPurchaseResponse(for text: String) -> String? {
        let normalized = normalize(text)
        let cache = userDefaults.dictionary(forKey: purchaseCacheKey) as? [String: String] ?? [:]
        return cache[normalized]
    }
    
    func cachePurchaseResponse(for text: String, json: String) {
        let normalized = normalize(text)
        var cache = userDefaults.dictionary(forKey: purchaseCacheKey) as? [String: String] ?? [:]
        
        if cache.count >= maxCacheSize {
            if let randomKey = cache.keys.randomElement() { cache.removeValue(forKey: randomKey) }
        }
        
        cache[normalized] = json
        userDefaults.set(cache, forKey: purchaseCacheKey)
    }
    
    // MARK: - Helpers
    
    /// Normalizes text to maximize cache hits (lowercases, strips punctuation)
    private func normalize(_ text: String) -> String {
        let charsToKeep = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = text.unicodeScalars.filter { charsToKeep.contains($0) }
        return String(cleaned).lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
