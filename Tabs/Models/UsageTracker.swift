import Foundation

/// Tracks Gemini AI usage for the Freemium model.
/// Free users get a limited number of Gemini-powered actions.
/// After the limit, the app gracefully falls back to on-device ML.
final class UsageTracker {

    static let shared = UsageTracker()

    // MARK: - Configuration

    /// Number of free Gemini actions before requiring Pro.
    static let freeGeminiLimit = 10

    // MARK: - Keys

    private let geminiUsageCountKey = "geminiUsageCount"
    private let isProUserKey = "isProUser"

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Public API

    var canUseGemini: Bool {
        return true
    }

    /// The number of Gemini actions used so far.
    var geminiUsageCount: Int {
        defaults.integer(forKey: geminiUsageCountKey)
    }

    /// How many free Gemini actions remain.
    var remainingFreeUses: Int {
        max(0, Self.freeGeminiLimit - geminiUsageCount)
    }

    /// Whether the user has a Pro subscription.
    var isProUser: Bool {
        get { defaults.bool(forKey: isProUserKey) }
        set { defaults.set(newValue, forKey: isProUserKey) }
    }

    /// Call this after a successful Gemini API call to increment the counter.
    func recordGeminiUsage() {
        let current = geminiUsageCount
        defaults.set(current + 1, forKey: geminiUsageCountKey)

        let remaining = remainingFreeUses
        if remaining > 0 {
            print("[UsageTracker] Gemini usage: \(current + 1)/\(Self.freeGeminiLimit) — \(remaining) free uses left")
        } else {
            print("[UsageTracker] Gemini free limit reached (\(Self.freeGeminiLimit)). Falling back to on-device ML.")
        }
    }

    /// Reset usage counter (e.g., for testing or when user upgrades).
    func resetUsage() {
        defaults.set(0, forKey: geminiUsageCountKey)
        print("[UsageTracker] Usage counter reset.")
    }

    // MARK: - User-Facing Messages

    /// Returns a friendly message for the limit-reached alert.
    var limitReachedMessage: String {
        "You've used all \(Self.freeGeminiLimit) free AI scans. " +
        "We're now using the standard local scanner. " +
        "Upgrade to Pro to unlock unlimited AI-powered scanning!"
    }

    /// Returns a subtitle showing remaining uses (for display in UI).
    var usageStatusText: String {
        if isProUser { return "Pro — Unlimited AI scans" }
        let remaining = remainingFreeUses
        if remaining <= 0 { return "Free tier — AI scans exhausted" }
        return "\(remaining) free AI scan\(remaining == 1 ? "" : "s") remaining"
    }
}
