import Foundation
import UIKit

/// Freemium cloud-AI limits and Pro plan copy.
/// Free: 40 lifetime scans (voice or camera). Pro: daily caps, then on-device.
final class UsageTracker {

    static let shared = UsageTracker()

    enum AIKind: String {
        case voice
        case camera
    }

    static let freeGeminiLimit = 40
    static let proVoiceScansPerDay = 300
    static let proCameraScansPerDay = 100
    static let monthlyPriceINR = 199
    static let yearlyPriceINR = 1999

    static let monthlyProductID = "com.sourav.beasyyyy.pro.monthly"
    static let yearlyProductID = "com.sourav.beasyyyy.pro.yearly"

    static var yearlySavingsPercent: Int {
        let monthlyCost = monthlyPriceINR * 12
        guard monthlyCost > 0 else { return 0 }
        return Int((Double(monthlyCost - yearlyPriceINR) / Double(monthlyCost) * 100).rounded())
    }

    private let geminiUsageCountKey = "geminiUsageCount"
    private let isProUserKey = "isProUser"
    private let voiceMonthCountKey = "proVoiceMonthCount"
    private let cameraMonthCountKey = "proCameraMonthCount"
    private let usageMonthKey = "proUsageMonthStamp"

    private let defaults = UserDefaults.standard

    private init() {}

    var canUseGemini: Bool {
        canUse(.voice) || canUse(.camera)
    }

    func canUse(_ kind: AIKind) -> Bool {
        if isProUser {
            rollDayIfNeeded()
            return remainingProUses(kind) > 0
        }
        return remainingFreeUses > 0
    }

    var geminiUsageCount: Int {
        defaults.integer(forKey: geminiUsageCountKey)
    }

    var remainingFreeUses: Int {
        max(0, Self.freeGeminiLimit - geminiUsageCount)
    }

    var isProUser: Bool {
        defaults.bool(forKey: isProUserKey)
    }

    func setStoreKitEntitled(_ entitled: Bool) {
        defaults.set(entitled, forKey: isProUserKey)
    }

    func applyServerQuota(_ quota: [String: Any]) {
        if let isPro = quota["isPro"] as? Bool {
            defaults.set(isPro, forKey: isProUserKey)
        }
        if let freeUsed = quota["freeUsed"] as? Int {
            defaults.set(freeUsed, forKey: geminiUsageCountKey)
        }
        if let voiceUsed = quota["voiceUsed"] as? Int {
            defaults.set(voiceUsed, forKey: voiceMonthCountKey)
        }
        if let cameraUsed = quota["cameraUsed"] as? Int {
            defaults.set(cameraUsed, forKey: cameraMonthCountKey)
        }
        if let day = (quota["day"] as? String) ?? (quota["month"] as? String) {
            defaults.set(day, forKey: usageMonthKey)
        }
    }

    func markCloudQuotaExhausted() {
        if isProUser {
            rollDayIfNeeded()
            defaults.set(Self.proVoiceScansPerDay, forKey: voiceMonthCountKey)
            defaults.set(Self.proCameraScansPerDay, forKey: cameraMonthCountKey)
        } else {
            defaults.set(Self.freeGeminiLimit, forKey: geminiUsageCountKey)
        }
    }

    func clearAccountLocalState() {
        defaults.set(false, forKey: isProUserKey)
        resetUsage()
    }

    func remainingProUses(_ kind: AIKind) -> Int {
        rollDayIfNeeded()
        switch kind {
        case .voice:
            return max(0, Self.proVoiceScansPerDay - defaults.integer(forKey: voiceMonthCountKey))
        case .camera:
            return max(0, Self.proCameraScansPerDay - defaults.integer(forKey: cameraMonthCountKey))
        }
    }

    func recordGeminiUsage() {
        record(.voice)
    }

    func record(_ kind: AIKind) {
        if isProUser {
            rollDayIfNeeded()
            let key = kind == .voice ? voiceMonthCountKey : cameraMonthCountKey
            let next = defaults.integer(forKey: key) + 1
            defaults.set(next, forKey: key)
            let left = remainingProUses(kind)
            print("[UsageTracker] Pro \(kind.rawValue): \(next) used, \(left) left today")
            if left == 10 || left == 5 {
                presentRemainingWarning(kind: kind, remaining: left)
            }
            return
        }

        let current = geminiUsageCount
        defaults.set(current + 1, forKey: geminiUsageCountKey)
        let remaining = remainingFreeUses
        if remaining > 0 {
            print("[UsageTracker] Free AI: \(current + 1)/\(Self.freeGeminiLimit) — \(remaining) left")
        } else {
            print("[UsageTracker] Free AI limit reached. Falling back to on-device ML.")
        }
        if remaining == 10 || remaining == 5 {
            presentRemainingWarning(kind: nil, remaining: remaining)
        }
    }

    func resetUsage() {
        defaults.set(0, forKey: geminiUsageCountKey)
        defaults.set(0, forKey: voiceMonthCountKey)
        defaults.set(0, forKey: cameraMonthCountKey)
        defaults.removeObject(forKey: usageMonthKey)
        print("[UsageTracker] Usage counters reset.")
    }

    func limitReachedMessage(for kind: AIKind) -> String {
        if isProUser {
            switch kind {
            case .voice:
                return "You've used today's \(Self.proVoiceScansPerDay) voice scans. Voice will use the on-device parser until tomorrow."
            case .camera:
                return "You've used today's \(Self.proCameraScansPerDay) photo scans. Bills will use the on-device scanner until tomorrow."
            }
        }
        return limitReachedMessage
    }

    var limitReachedMessage: String {
        "You've used all \(Self.freeGeminiLimit) free AI scans. " +
        "We're now using the on-device scanner. " +
        "Pro is ₹\(Self.monthlyPriceINR)/month or ₹\(Self.yearlyPriceINR)/year — \(Self.proVoiceScansPerDay) voice and \(Self.proCameraScansPerDay) photo scans each day."
    }

    var usageStatusText: String {
        if isProUser {
            return "Pro — \(remainingProUses(.voice)) voice / \(remainingProUses(.camera)) photo scans left today"
        }
        let remaining = remainingFreeUses
        if remaining <= 0 { return "Free — AI scans used up" }
        return "\(remaining) free AI scan\(remaining == 1 ? "" : "s") remaining"
    }

    private func rollDayIfNeeded() {
        let stamp = Self.dayStamp()
        let stored = defaults.string(forKey: usageMonthKey)
        guard stored != stamp else { return }
        defaults.set(stamp, forKey: usageMonthKey)
        defaults.set(0, forKey: voiceMonthCountKey)
        defaults.set(0, forKey: cameraMonthCountKey)
    }

    /// IST calendar day so the daily cap matches Indian shop hours.
    private static func dayStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func presentRemainingWarning(kind: AIKind?, remaining: Int) {
        DispatchQueue.main.async {
            let title = "\(remaining) AI scans left"
            let message: String
            if let kind {
                let label = kind == .voice ? "voice" : "camera"
                message = "You have \(remaining) \(label) scans left today. After that this phone uses the on-device scanner."
            } else {
                message = "You have \(remaining) free AI scans remaining. After they finish, this phone uses the on-device scanner."
            }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            Self.topViewController()?.present(alert, animated: true)
        }
    }

    private static func topViewController(
        from root: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    ) -> UIViewController? {
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        return root
    }
}
