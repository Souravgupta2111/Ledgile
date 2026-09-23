
import UIKit

enum MainTabInstaller {
    static func makeRootTabBar() -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let root = storyboard.instantiateViewController(withIdentifier: "MainTabBarController")
        if let tab = root as? UITabBarController {
            addSearchTabIfNeeded(on: tab)
        }
        return root
    }

    static func addSearchTabIfNeeded(on tabBarController: UITabBarController) {
        var currentControllers = tabBarController.viewControllers ?? []

        let hasSearchTab = currentControllers.contains { controller in
            if let nav = controller as? UINavigationController {
                return nav.viewControllers.first is GlobalSearchViewController
            }
            return controller is GlobalSearchViewController
        }
        if hasSearchTab { return }

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let searchVC = storyboard.instantiateViewController(withIdentifier: "GlobalSearchViewController") as? GlobalSearchViewController else {
            return
        }
        searchVC.title = "Search"

        let searchNav = UINavigationController(rootViewController: searchVC)
        searchNav.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 999)
        currentControllers.append(searchNav)
        tabBarController.setViewControllers(currentControllers, animated: false)
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // Check if user has already completed onboarding
        let didCompleteOnboarding = UserDefaults.standard.bool(forKey: "userDidCompleteOnboarding")
        let isLoggedInWithSupabase = AuthManager.shared.isLoggedIn
        
        if isLoggedInWithSupabase && !AuthNavigationHelper.hasCompletedProfile {
            let window = UIWindow(windowScene: windowScene)
            let completeVC = AuthNavigationHelper.makeCompleteProfileController()
            window.rootViewController = UINavigationController(rootViewController: completeVC)
            self.window = window
            window.makeKeyAndVisible()
            AuthManager.shared.refreshSessionIfNeeded()
        } else if isLoggedInWithSupabase && AuthNavigationHelper.needsLaunchPlan {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = AuthNavigationHelper.makeLaunchPlanController()
            self.window = window
            window.makeKeyAndVisible()
            AuthManager.shared.refreshSessionIfNeeded()
        } else if didCompleteOnboarding || isLoggedInWithSupabase {
            // Skip onboarding — go straight to main app
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = MainTabInstaller.makeRootTabBar()
            self.window = window
            window.makeKeyAndVisible()
            
            // Silently refresh Supabase token if needed
            AuthManager.shared.refreshSessionIfNeeded()
        }
        // Otherwise, the storyboard's initial view controller (onboarding) loads automatically
        
        guard scene is UIWindowScene else { return }

        if let tabBarController = window?.rootViewController as? UITabBarController {
            MainTabInstaller.addSearchTabIfNeeded(on: tabBarController)
        }
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        CloudBackupService.shared.uploadIfDueForDaily()
        setupHotwordListener()
        HotwordListener.shared.start()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        HotwordListener.shared.stop()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // to restore the scene back to its current state.
    }

}

// MARK: - Hotword Navigation
extension SceneDelegate {
    private func setupHotwordListener() {
        // Only set the callback once.
        guard HotwordListener.shared.onHotword == nil else { return }
        HotwordListener.shared.onHotword = { [weak self] in
            guard let self, let window = self.window else { return }
            guard let topVC = Self.topViewController(from: window.rootViewController) else { return }
            // Don't re-present if already on voice entry or live voice.
            if topVC is VoiceEntryViewController || topVC is LiveVoiceViewController { return }
            HotwordListener.shared.pause()
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            guard let voiceVC = storyboard.instantiateViewController(withIdentifier: "VoiceEntryViewController")
                    as? VoiceEntryViewController else { return }
            voiceVC.autoStartListening = true
            voiceVC.modalPresentationStyle = .fullScreen
            voiceVC.onDismiss = {
                HotwordListener.shared.resume()
            }
            topVC.present(voiceVC, animated: true)
        }
    }

    private static func topViewController(from vc: UIViewController?) -> UIViewController? {
        if let presented = vc?.presentedViewController {
            return topViewController(from: presented)
        }
        if let nav = vc as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = vc as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        return vc
    }
}
