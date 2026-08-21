import UIKit

enum AuthNavigationHelper {

    static let profileCompleteKey = "userDidCompleteProfileDetails"
    static let needsLaunchPlanKey = "userNeedsLaunchPlan"
    static let didFinishLaunchPlanKey = "userDidFinishLaunchPlan"

    static var hasCompletedProfile: Bool {
        if UserDefaults.standard.bool(forKey: profileCompleteKey) { return true }
        return isLocalProfileComplete()
    }

    static var needsLaunchPlan: Bool {
        UserDefaults.standard.bool(forKey: needsLaunchPlanKey)
            && !UserDefaults.standard.bool(forKey: didFinishLaunchPlanKey)
    }

    static func isValidName(_ name: String) -> Bool {
        isValidPersonName(name)
    }

    static func isValidPersonName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0 == " " }
    }

    static func isValidShopName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || "&-.'".contains($0) }
    }

    static func isValidPhone(_ phone: String, countryCode: String) -> Bool {
        let digits = phone.filter(\.isNumber)
        if countryCode == "+91" { return digits.count == 10 }
        return (7...15).contains(digits.count)
    }

    static func isLocalProfileComplete() -> Bool {
        guard let settings = try? AppDataModel.shared.dataModel.db.getSettings() else { return false }
        let name = (settings.ownerName ?? settings.profileName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shop = settings.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = (settings.businessPhone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidPersonName(name)
            && isValidShopName(shop)
            && shop.lowercased() != "my shop"
            && !phone.isEmpty
    }

    static func isRemoteProfileComplete(_ profile: [String: Any]) -> Bool {
        let name = (profile["owner_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let shop = (profile["shop_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = (profile["phone"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidPersonName(name) && isValidShopName(shop) && !phone.isEmpty
    }

    static func applyRemoteProfile(_ profile: [String: Any]) {
        if var settings = try? AppDataModel.shared.dataModel.db.getSettings() {
            if let ownerName = profile["owner_name"] as? String,
               !ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.ownerName = ownerName
                settings.profileName = ownerName
            }
            if let shopName = profile["shop_name"] as? String,
               !shopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.businessName = shopName
            }
            if let phone = profile["phone"] as? String,
               !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.businessPhone = phone
            }
            try? AppDataModel.shared.dataModel.db.updateSettings(settings)
        }

        if let email = profile["email"] as? String, !email.isEmpty {
            AuthManager.shared.saveAppleEmail(email)
        }
    }

    static func saveLocalProfile(name: String, shopName: String, phone: String) {
        if var settings = try? AppDataModel.shared.dataModel.db.getSettings() {
            settings.ownerName = name
            settings.profileName = name
            settings.businessName = shopName
            settings.businessPhone = phone
            try? AppDataModel.shared.dataModel.db.updateSettings(settings)
        }
    }

    static func goToMainApp() {
        UserDefaults.standard.set(true, forKey: "userDidCompleteOnboarding")
        UserDefaults.standard.set(true, forKey: profileCompleteKey)
        UserDefaults.standard.set(false, forKey: needsLaunchPlanKey)
        UserDefaults.standard.set(true, forKey: didFinishLaunchPlanKey)

        let mainTabBarController = MainTabInstaller.makeRootTabBar()

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController = mainTabBarController
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: nil)
        }
    }

    /// After first login + profile: Free vs Pro, then monthly/yearly if they pick Pro.
    static func continueAfterAccountReady() {
        UserDefaults.standard.set(true, forKey: "userDidCompleteOnboarding")
        UserDefaults.standard.set(true, forKey: profileCompleteKey)
        if UsageTracker.shared.isProUser || UserDefaults.standard.bool(forKey: didFinishLaunchPlanKey) {
            goToMainApp()
            return
        }
        UserDefaults.standard.set(true, forKey: needsLaunchPlanKey)
        presentLaunchPlan()
    }

    static func finishLaunchPlanAndGoToApp() {
        goToMainApp()
    }

    static func presentLaunchPlan() {
        let vc = FreeVsProViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.setNavigationBarHidden(true, animated: false)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController = nav
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: nil)
        }
    }

    static func makeLaunchPlanController() -> UIViewController {
        let nav = UINavigationController(rootViewController: FreeVsProViewController())
        nav.setNavigationBarHidden(true, animated: false)
        return nav
    }

    static func makeCompleteProfileController(
        name: String? = nil,
        shopName: String? = nil,
        phone: String? = nil,
        email: String? = nil
    ) -> CompleteProfileViewController {
        let completeVC = CompleteProfileViewController()
        completeVC.prefilledName = name
        completeVC.prefilledShop = shopName
        completeVC.prefilledPhone = phone
        completeVC.prefilledEmail = email
        return completeVC
    }

    static func continueAfterAppleAuth(
        from viewController: UIViewController,
        appleName: String?,
        appleEmail: String?
    ) {
        AuthManager.shared.saveAppleEmail(appleEmail)

        let presentComplete: ([String: Any]?) -> Void = { profile in
            if let profile, isRemoteProfileComplete(profile) {
                applyRemoteProfile(profile)
                continueAfterAccountReady()
                return
            }

            let completeVC = makeCompleteProfileController(
                name: firstNonEmpty(appleName, profile?["owner_name"] as? String),
                shopName: profile?["shop_name"] as? String,
                phone: profile?["phone"] as? String,
                email: appleEmail
            )

            if let nav = viewController.navigationController {
                nav.pushViewController(completeVC, animated: true)
            } else {
                let nav = UINavigationController(rootViewController: completeVC)
                nav.modalPresentationStyle = .fullScreen
                viewController.present(nav, animated: true)
            }
        }

        if AuthManager.shared.isConfigured {
            AuthManager.shared.fetchUserProfile { profile in
                DispatchQueue.main.async {
                    presentComplete(profile)
                }
            }
        } else {
            presentComplete(nil)
        }
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }
}
