import Foundation
import AppIntents

extension Notification.Name {
    static let ledgerCatalogDidChange = Notification.Name("LedgerCatalogDidChange")
}

@MainActor
enum AppShortcutRefresher {
    private static var observer: NSObjectProtocol?
    private static var pendingWork: DispatchWorkItem?

    static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .ledgerCatalogDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                schedule()
            }
        }
        schedule()
    }

    static func schedule() {
        pendingWork?.cancel()
        let work = DispatchWorkItem {
            BEasyAppShortcuts.updateAppShortcutParameters()
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
