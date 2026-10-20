import UIKit

final class WalkthroughCoordinator: NSObject, WalkthroughOverlayViewDelegate {

    static let shared = WalkthroughCoordinator()

    private var activeOverlay: WalkthroughOverlayView?
    private(set) var currentStep: WalkthroughStep = .welcome
    private weak var hostTabBarController: UITabBarController?
    private(set) var isRunning: Bool = false

    private override init() {
        super.init()
    }

    // MARK: - Entry Points

    /// Checks if first-time walkthrough should be presented, and presents it if eligible.
    func checkAndStartWalkthroughIfNeeded(from viewController: UIViewController) {
        guard !isRunning else { return }

        let shouldShow = WalkthroughManager.shared.shouldShowWalkthrough()
        guard shouldShow else { return }

        // Start after slight delay so view layout and network fetches stabilize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak viewController] in
            guard let self = self, let vc = viewController, !self.isRunning else { return }
            guard WalkthroughManager.shared.shouldShowWalkthrough() else { return }
            self.startWalkthrough(from: vc)
        }
    }

    /// Explicitly starts or replays the walkthrough from any view controller.
    func startWalkthrough(from viewController: UIViewController, isReplay: Bool = false) {
        guard !isRunning else { return }

        let tabBar = (viewController as? UITabBarController)
            ?? viewController.tabBarController
            ?? (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController as? UITabBarController

        guard let targetTabBar = tabBar else {
            print("[Walkthrough] Could not find root UITabBarController.")
            return
        }

        self.hostTabBarController = targetTabBar
        self.isRunning = true

        guard let window = targetTabBar.view.window ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            isRunning = false
            return
        }

        // Ensure we start on tab 0 (Dashboard)
        targetTabBar.selectedIndex = 0

        let overlay = WalkthroughOverlayView(frame: window.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.alpha = 0
        overlay.delegate = self
        window.addSubview(overlay)
        self.activeOverlay = overlay

        UIView.animate(withDuration: 0.25) {
            overlay.alpha = 1
        }

        currentStep = isReplay ? .dashboardOverview : .welcome
        presentStep(currentStep, animated: false)
    }

    // MARK: - Step Presentation & Navigation

    private func presentStep(_ step: WalkthroughStep, animated: Bool) {
        guard let overlay = activeOverlay, let tabBar = hostTabBarController else { return }

        let canGoBack = (step.rawValue > 0)

        switch step {
        case .welcome:
            tabBar.selectedIndex = 0
            overlay.configure(step: step, targetRect: nil, canGoBack: canGoBack, animated: animated)

        case .dashboardOverview:
            tabBar.selectedIndex = 0
            ensureDashboardVisible(tabBar: tabBar) { [weak self, weak overlay] in
                guard let self = self, let overlay = overlay else { return }
                let rect = self.findDashboardOverviewRect(in: tabBar, overlay: overlay)
                overlay.configure(step: step, targetRect: rect, canGoBack: canGoBack, animated: animated)
            }

        case .analytics:
            tabBar.selectedIndex = 0
            ensureDashboardVisible(tabBar: tabBar) { [weak self, weak overlay] in
                guard let self = self, let overlay = overlay else { return }
                let rect = self.findAnalyticsReportsRect(in: tabBar, overlay: overlay)
                overlay.configure(step: step, targetRect: rect, canGoBack: canGoBack, animated: animated)
            }

        case .creditDetails:
            tabBar.selectedIndex = 0
            ensureDashboardVisible(tabBar: tabBar) { [weak self, weak overlay] in
                guard let self = self, let overlay = overlay else { return }
                let rect = self.findCreditDetailsRect(in: tabBar, overlay: overlay)
                overlay.configure(step: step, targetRect: rect, canGoBack: canGoBack, animated: animated)
            }

        case .stockTab:
            tabBar.selectedIndex = 0
            let rect = findTabBarItemRect(at: 1, in: tabBar, overlay: overlay)
            overlay.configure(step: step, targetRect: rect, canGoBack: canGoBack, animated: animated)

        case .stockActions:
            tabBar.selectedIndex = 1
            // Give StockViewController time to load its hosted SwiftUI view
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak overlay, weak tabBar] in
                guard let self = self, let overlay = overlay, let tabBar = tabBar else { return }
                let rect = self.findStockActionsRect(in: tabBar, overlay: overlay)
                overlay.configure(step: step, targetRect: rect, canGoBack: canGoBack, animated: animated)
            }

        case .salesActions:
            tabBar.selectedIndex = 3
            // Give SalesViewController time to load its hosted SwiftUI view
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak overlay, weak tabBar] in
                guard let self = self, let overlay = overlay, let tabBar = tabBar else { return }
                let rect = self.findSalesActionsRect(in: tabBar, overlay: overlay)
                overlay.configure(step: step, targetRect: rect, canGoBack: canGoBack, animated: animated)
            }

        case .completion:
            tabBar.selectedIndex = 0
            overlay.configure(step: step, targetRect: nil, canGoBack: canGoBack, animated: animated)
        }
    }

    // MARK: - Overlay Delegate Callbacks

    func walkthroughOverlayDidTapNext(_ overlay: WalkthroughOverlayView) {
        let allSteps = WalkthroughStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: currentStep) else { return }

        let nextIndex = currentIndex + 1
        if nextIndex < allSteps.count {
            currentStep = allSteps[nextIndex]
            presentStep(currentStep, animated: true)
        } else {
            // Finished
            dismissWalkthrough(completed: true)
        }
    }

    func walkthroughOverlayDidTapBack(_ overlay: WalkthroughOverlayView) {
        let allSteps = WalkthroughStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: currentStep) else { return }

        let prevIndex = currentIndex - 1
        if prevIndex >= 0 {
            currentStep = allSteps[prevIndex]
            presentStep(currentStep, animated: true)
        }
    }

    func walkthroughOverlayDidTapSkip(_ overlay: WalkthroughOverlayView) {
        dismissWalkthrough(completed: false)
    }

    // MARK: - Dismissal

    func dismissWalkthrough(completed: Bool) {
        guard let overlay = activeOverlay else {
            isRunning = false
            return
        }

        if completed {
            WalkthroughManager.shared.markWalkthroughCompleted()
        } else {
            WalkthroughManager.shared.markWalkthroughSkipped()
        }

        // Return user safely to Dashboard tab
        hostTabBarController?.selectedIndex = 0

        UIView.animate(withDuration: 0.25, animations: {
            overlay.alpha = 0
        }) { [weak self] _ in
            overlay.removeFromSuperview()
            self?.activeOverlay = nil
            self?.isRunning = false
        }
    }

    // MARK: - Target Rect Resolvers

    private func ensureDashboardVisible(tabBar: UITabBarController, completion: @escaping () -> Void) {
        guard let nav = tabBar.viewControllers?.first as? UINavigationController ?? (tabBar.selectedViewController as? UINavigationController) else {
            completion()
            return
        }

        if nav.viewControllers.count > 1 {
            nav.popToRootViewController(animated: false)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            completion()
        }
    }

    private func findDashboardViewController(in tabBar: UITabBarController) -> DashboardViewController? {
        if let nav = tabBar.viewControllers?.first as? UINavigationController {
            return nav.viewControllers.first as? DashboardViewController
        }
        return tabBar.viewControllers?.first as? DashboardViewController
    }

    private func findDashboardOverviewRect(in tabBar: UITabBarController, overlay: UIView) -> CGRect? {
        guard let dashboardVC = findDashboardViewController(in: tabBar) else { return nil }
        guard let tableView = dashboardVC.tableView else { return nil }

        // Scroll to top cell
        tableView.setContentOffset(.zero, animated: false)
        tableView.layoutIfNeeded()

        guard let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? DashboardTopTileTableViewCell else {
            let rowRect = tableView.rectForRow(at: IndexPath(row: 0, section: 0))
            return tableView.convert(rowRect, to: overlay)
        }

        if let card = cell.segmentedCardBackground {
            return card.convert(card.bounds, to: overlay)
        }

        return cell.convert(cell.bounds, to: overlay)
    }

    private func findAnalyticsReportsRect(in tabBar: UITabBarController, overlay: UIView) -> CGRect? {
        guard let dashboardVC = findDashboardViewController(in: tabBar) else { return nil }
        guard let tableView = dashboardVC.tableView else { return nil }

        // Scroll so Reports section is in view
        tableView.scrollToRow(at: IndexPath(row: 0, section: 2), at: .middle, animated: false)
        tableView.layoutIfNeeded()

        // Try to find the section 2 header view or rect
        let headerRect = tableView.rectForHeader(inSection: 2)
        if !headerRect.isEmpty {
            let converted = tableView.convert(headerRect, to: overlay)
            // Expand slightly to embrace the View All button nicely
            return CGRect(x: 16, y: converted.minY - 2, width: overlay.bounds.width - 32, height: max(converted.height, 46) + 4)
        }

        // Fallback to first row of reports
        let rowRect = tableView.rectForRow(at: IndexPath(row: 0, section: 2))
        return tableView.convert(rowRect, to: overlay)
    }

    private func findCreditDetailsRect(in tabBar: UITabBarController, overlay: UIView) -> CGRect? {
        guard let dashboardVC = findDashboardViewController(in: tabBar) else { return nil }
        guard let tableView = dashboardVC.tableView else { return nil }

        tableView.setContentOffset(.zero, animated: false)
        tableView.layoutIfNeeded()

        guard let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? DashboardTopTileTableViewCell else {
            return nil
        }

        // Locate credit container via label superview
        if let paySuper = cell.youWillPayLabel?.superview,
           let getSuper = cell.youWillGetLabel?.superview {
            let payRect = paySuper.convert(paySuper.bounds, to: overlay)
            let getRect = getSuper.convert(getSuper.bounds, to: overlay)
            return payRect.union(getRect)
        }

        // Fallback rect within cell
        let cellRect = cell.convert(cell.bounds, to: overlay)
        return CGRect(x: 16, y: cellRect.maxY - 140, width: cellRect.width - 32, height: 125)
    }

    private func findTabBarItemRect(at index: Int, in tabBar: UITabBarController, overlay: UIView) -> CGRect {
        let bar = tabBar.tabBar
        bar.layoutIfNeeded()

        let totalItems = CGFloat(max(bar.items?.count ?? 5, 1))
        let itemWidth = bar.bounds.width / totalItems
        let itemX = CGFloat(index) * itemWidth

        // Look for actual UITabBarButton subviews
        let buttons = bar.subviews
            .filter { "\(type(of: $0))".contains("TabBarButton") }
            .sorted { $0.frame.minX < $1.frame.minX }

        if index < buttons.count {
            let button = buttons[index]
            var rect = button.convert(button.bounds, to: overlay)
            rect.size.height = min(rect.height, 52)
            return rect
        }

        // Fallback: calculate evenly distributed item frame (top 48pt of bar)
        let itemFrame = CGRect(
            x: itemX + 4,
            y: 2,
            width: itemWidth - 8,
            height: 48
        )
        return bar.convert(itemFrame, to: overlay)
    }

    private func findStockActionsRect(in tabBar: UITabBarController, overlay: UIView) -> CGRect {
        let screenWidth = overlay.bounds.width
        let screenHeight = overlay.bounds.height
        let actionWidth: CGFloat = min(320, screenWidth - 32)
        let actionHeight: CGFloat = 160

        let bottomOffset: CGFloat = tabBar.tabBar.bounds.height + overlay.safeAreaInsets.bottom + 180
        let originY = max(overlay.safeAreaInsets.top + 80, screenHeight - bottomOffset - actionHeight)
        let originX = (screenWidth - actionWidth) / 2

        return CGRect(x: originX, y: originY, width: actionWidth, height: actionHeight)
    }

    private func findSalesActionsRect(in tabBar: UITabBarController, overlay: UIView) -> CGRect {
        let screenWidth = overlay.bounds.width
        let screenHeight = overlay.bounds.height
        let actionWidth: CGFloat = min(320, screenWidth - 32)
        let actionHeight: CGFloat = 160

        let bottomOffset: CGFloat = tabBar.tabBar.bounds.height + overlay.safeAreaInsets.bottom + 180
        let originY = max(overlay.safeAreaInsets.top + 80, screenHeight - bottomOffset - actionHeight)
        let originX = (screenWidth - actionWidth) / 2

        return CGRect(x: originX, y: originY, width: actionWidth, height: actionHeight)
    }
}
