import Foundation
import UIKit

// MARK: - Walkthrough Step Definition

enum WalkthroughStep: Int, CaseIterable {
    case welcome
    case dashboardOverview
    case analytics
    case creditDetails
    case stockTab
    case stockActions
    case salesActions
    case completion

    var isModal: Bool {
        switch self {
        case .welcome, .completion:
            return true
        default:
            return false
        }
    }

    /// 1-based index among guided steps (excluding pure welcome and completion modals)
    var stepIndex: Int? {
        switch self {
        case .dashboardOverview: return 1
        case .analytics:         return 2
        case .creditDetails:     return 3
        case .stockTab:          return 4
        case .stockActions:      return 5
        case .salesActions:      return 6
        case .welcome, .completion:
            return nil
        }
    }

    static var totalGuidedSteps: Int {
        return 6
    }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome to B Easy!"
        case .dashboardOverview:
            return "Dashboard Overview"
        case .analytics:
            return "Analytics & Reports"
        case .creditDetails:
            return "Credit Management"
        case .stockTab:
            return "Stock Management"
        case .stockActions:
            return "Adding Stock"
        case .salesActions:
            return "Recording Sales"
        case .completion:
            return "You're all set!"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "Manage your business, track your stock, record sales, and understand your performance—all in one place. Let's take a quick tour to help you get started."
        case .dashboardOverview:
            return "Your business overview is right here. Quickly check how your business is performing from your dashboard."
        case .analytics:
            return "Want to understand your business better? Tap here to explore your analytics and performance reports."
        case .creditDetails:
            return "Access your credit-related information and explore the available credit actions here."
        case .stockTab:
            return "Manage your inventory and keep track of the products available in your business here."
        case .stockActions:
            return "Add stock to your inventory using your preferred method:\n\n• Voice: Tap to speak and record purchases hands-free.\n• Scan: Scan product barcodes or QR codes quickly.\n• Manual: Enter item details and quantities directly."
        case .salesActions:
            return "Record your sales using your preferred method:\n\n• Voice: Tap to speak and record sales hands-free.\n• Scan: Scan product barcodes or QR codes quickly.\n• Manual: Enter items, quantities, and prices directly."
        case .completion:
            return "You now know where to find your dashboard insights, manage stock, record sales, and access credit details. Explore B Easy at your own pace."
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .welcome:
            return "Start Tour"
        case .completion:
            return "Finish"
        default:
            return "Next"
        }
    }
}

// MARK: - Walkthrough Manager

final class WalkthroughManager {

    static let shared = WalkthroughManager()

    private let defaults = UserDefaults.standard
    private let completedKeyPrefix = "beasy_walkthrough_completed"
    private let skippedKeyPrefix = "beasy_walkthrough_skipped"

    private init() {}

    // MARK: - User Key Resolution

    private func key(for prefix: String, userId: String? = nil) -> String {
        let resolvedId = userId ?? AuthManager.shared.currentUserId ?? "device_guest"
        return "\(prefix)_\(resolvedId)"
    }

    // MARK: - State Inspection

    /// Determines whether the first-time walkthrough should automatically appear.
    func shouldShowWalkthrough(for userId: String? = nil) -> Bool {
        let completedKey = key(for: completedKeyPrefix, userId: userId)
        let skippedKey = key(for: skippedKeyPrefix, userId: userId)

        let hasCompleted = defaults.bool(forKey: completedKey)
        let hasSkipped = defaults.bool(forKey: skippedKey)

        // Show only if neither completed nor skipped
        return !hasCompleted && !hasSkipped
    }

    /// Returns whether the tour was ever completed by this user.
    func hasCompletedWalkthrough(for userId: String? = nil) -> Bool {
        let completedKey = key(for: completedKeyPrefix, userId: userId)
        return defaults.bool(forKey: completedKey)
    }

    // MARK: - State Mutation

    /// Marks the walkthrough as completed for the current user.
    func markWalkthroughCompleted(for userId: String? = nil) {
        let completedKey = key(for: completedKeyPrefix, userId: userId)
        defaults.set(true, forKey: completedKey)
    }

    /// Marks the walkthrough as skipped for the current user (won't auto-popup on next launches).
    func markWalkthroughSkipped(for userId: String? = nil) {
        let skippedKey = key(for: skippedKeyPrefix, userId: userId)
        defaults.set(true, forKey: skippedKey)
    }

    /// Resets walkthrough completion/skipped state for replaying.
    func resetWalkthroughState(for userId: String? = nil) {
        let completedKey = key(for: completedKeyPrefix, userId: userId)
        let skippedKey = key(for: skippedKeyPrefix, userId: userId)
        defaults.removeObject(forKey: completedKey)
        defaults.removeObject(forKey: skippedKey)
    }
}
