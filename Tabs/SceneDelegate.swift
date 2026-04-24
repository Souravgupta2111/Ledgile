
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // Check if user has already completed onboarding
        let didCompleteOnboarding = UserDefaults.standard.bool(forKey: "userDidCompleteOnboarding")
        let isLoggedInWithSupabase = AuthManager.shared.isLoggedIn
        
        if didCompleteOnboarding || isLoggedInWithSupabase {
            // Skip onboarding — go straight to main app
            let window = UIWindow(windowScene: windowScene)
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let mainTabBarController = storyboard.instantiateViewController(withIdentifier: "MainTabBarController")
            window.rootViewController = mainTabBarController
            self.window = window
            window.makeKeyAndVisible()
        }
        // Otherwise, the storyboard's initial view controller (onboarding) loads automatically
        
        guard scene is UIWindowScene else { return }

        if let tabBarController = window?.rootViewController as? UITabBarController {
            addSearchTabIfNeeded(on: tabBarController)
        }
    }

    private func addSearchTabIfNeeded(on tabBarController: UITabBarController) {
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

        let insertIndex = min(1, currentControllers.count)
        currentControllers.insert(searchNav, at: insertIndex)
        tabBarController.setViewControllers(currentControllers, animated: false)
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
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
