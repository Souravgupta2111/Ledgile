import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        CrashLog.install()
        ProductFingerprintManager.shared.prepareEmbeddingsForCurrentExtractor()
        Task { @MainActor in
            ProStore.shared.start()
        }
        LedgerIO.queue.async {
            let items = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            InventoryMatcher.shared.indexInventory(items)
            AppDataModel.shared.dataModel.reconcileAllStock()
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}
