
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
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // to restore the scene back to its current state.
    }

}
