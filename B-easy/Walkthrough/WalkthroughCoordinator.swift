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

        #if DEBUG
        if let intervalArgIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "--auto-advance-walkthrough"),
           intervalArgIndex + 1 < ProcessInfo.processInfo.arguments.count,
           let interval = Double(ProcessInfo.processInfo.arguments[intervalArgIndex + 1]) {
            scheduleAutoAdvance(interval: interval)
        }
        #endif
    }

    #if DEBUG
    private func scheduleAutoAdvance(interval: TimeInterval) {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self, self.isRunning, let overlay = self.activeOverlay else {
                timer.invalidate()
                return
            }
            self.walkthroughOverlayDidTapNext(overlay)
        }
    }
    #endif

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
            let stockIdx = findStockTabIndex(in: tabBar)
            tabBar.selectedIndex = stockIdx
            let rect = findTabBarItemRect(at: stockIdx, in: tabBar, overlay: overlay)
            overlay.configure(step: step, targetRect: rect, canGoBack: canGoBack, animated: animated)

        case .stockActions:
            let stockIdx = findStockTabIndex(in: tabBar)
            tabBar.selectedIndex = stockIdx
            // Give StockViewController time to load its hosted SwiftUI view
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak overlay, weak tabBar] in
                guard let self = self, let overlay = overlay, let tabBar = tabBar else { return }
                let rect = self.findStockActionsRect(in: tabBar, overlay: overlay)
                overlay.configure(step: step, targetRect: rect, canGoBack: canGoBack, animated: animated)
            }

        case .salesActions:
            let salesIdx = findSalesTabIndex(in: tabBar)
            tabBar.selectedIndex = salesIdx
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

    private func findStockTabIndex(in tabBar: UITabBarController) -> Int {
        if let viewControllers = tabBar.viewControllers {
            for (idx, vc) in viewControllers.enumerated() {
                let rootVC = (vc as? UINavigationController)?.viewControllers.first ?? vc
                if rootVC is StockViewController {
                    return idx
                }
            }
        }
        return 1
    }

    private func findSalesTabIndex(in tabBar: UITabBarController) -> Int {
        if let viewControllers = tabBar.viewControllers {
            for (idx, vc) in viewControllers.enumerated() {
                let rootVC = (vc as? UINavigationController)?.viewControllers.first ?? vc
                if rootVC is SalesViewController {
                    return idx
                }
            }
        }
        return 2
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

        // 1. Precise match on actual header view
        if let headerView = findView(withAccessibilityIdentifier: "dashboard_reports_header", in: tableView) {
            let converted = headerView.convert(headerView.bounds, to: overlay)
            return CGRect(x: 16, y: converted.minY, width: overlay.bounds.width - 32, height: max(converted.height, 44))
        }

        // 2. Relative to the first reports table row
        if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 2)) {
            let converted = cell.convert(cell.bounds, to: overlay)
            return CGRect(x: 16, y: converted.minY - 48, width: overlay.bounds.width - 32, height: 44)
        }

        // 3. Fallback to header rect
        let headerRect = tableView.rectForHeader(inSection: 2)
        if !headerRect.isEmpty {
            let converted = tableView.convert(headerRect, to: overlay)
            return CGRect(x: 16, y: converted.minY - 2, width: overlay.bounds.width - 32, height: max(converted.height, 46) + 4)
        }

        // 4. Fallback to row rect
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

    /// Recalculates and animates the spotlight when view layout finishes or updates.
    func refreshSpotlightIfCurrent(step: WalkthroughStep) {
        guard isRunning, currentStep == step, let overlay = activeOverlay, let tabBar = hostTabBarController else { return }
        let rect: CGRect?
        switch step {
        case .stockActions:
            rect = findStockActionsRect(in: tabBar, overlay: overlay)
        case .salesActions:
            rect = findSalesActionsRect(in: tabBar, overlay: overlay)
        default:
            return
        }
        overlay.updateTargetRect(rect, for: step, animated: true)
    }

    /// Tightly fits the spotlight around the actual Scan, Voice, and Manual controls.
    /// The Voice button's 130x130 circle is centered vertically inside the 150pt row (y=10 to y=140).
    /// Scan and Manual 54pt circles and labels span vertically within the same height.
    private func fittedActionPanelRect(from rawRect: CGRect) -> CGRect {
        let width: CGFloat = min(316, rawRect.width - 12)
        let height: CGFloat = 134
        let originX = rawRect.midX - (width / 2)
        let originY = rawRect.minY + 8
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private func findStockActionsRect(in tabBar: UITabBarController, overlay: UIView) -> CGRect {
        let stockIdx = findStockTabIndex(in: tabBar)
        if let controllers = tabBar.viewControllers, stockIdx < controllers.count,
           let nav = controllers[stockIdx] as? UINavigationController,
           let stockVC = nav.viewControllers.first as? StockViewController {
            stockVC.view.layoutIfNeeded()

            if let globalFrame = stockVC.actionButtonsGlobalFrame,
               globalFrame.width > 50, globalFrame.height > 50 {
                let rectInOverlay = overlay.convert(globalFrame, from: nil)
                return fittedActionPanelRect(from: rectInOverlay)
            }

            if let actionRow = findView(withAccessibilityIdentifier: "stock_action_buttons_row", in: stockVC.view) {
                let rectInOverlay = actionRow.convert(actionRow.bounds, to: overlay)
                return fittedActionPanelRect(from: rectInOverlay)
            }
        }

        // Precise fallback matching StockTabView layout (actionButtonsRow centered above Spacer(228)):
        let screenWidth = overlay.bounds.width
        let screenHeight = overlay.bounds.height
        let width: CGFloat = min(316, screenWidth - 32)
        let height: CGFloat = 134
        let originX = (screenWidth - width) / 2
        let originY = screenHeight - 228 - 150 + 8

        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private func findSalesActionsRect(in tabBar: UITabBarController, overlay: UIView) -> CGRect {
        let salesIdx = findSalesTabIndex(in: tabBar)
        if let controllers = tabBar.viewControllers, salesIdx < controllers.count,
           let nav = controllers[salesIdx] as? UINavigationController,
           let salesVC = nav.viewControllers.first as? SalesViewController {
            salesVC.view.layoutIfNeeded()

            if let globalFrame = salesVC.actionButtonsGlobalFrame,
               globalFrame.width > 50, globalFrame.height > 50 {
                let rectInOverlay = overlay.convert(globalFrame, from: nil)
                return fittedActionPanelRect(from: rectInOverlay)
            }

            if let actionRow = findView(withAccessibilityIdentifier: "sales_action_buttons_row", in: salesVC.view) {
                let rectInOverlay = actionRow.convert(actionRow.bounds, to: overlay)
                return fittedActionPanelRect(from: rectInOverlay)
            }
        }

        // Precise fallback matching SalesTabView layout (actionButtonsRow centered above Spacer(228)):
        let screenWidth = overlay.bounds.width
        let screenHeight = overlay.bounds.height
        let width: CGFloat = min(316, screenWidth - 32)
        let height: CGFloat = 134
        let originX = (screenWidth - width) / 2
        let originY = screenHeight - 228 - 150 + 8

        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    /// Recursively walks the UIKit view hierarchy to find a view with the given accessibility identifier.
    private func findView(withAccessibilityIdentifier identifier: String, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == identifier {
            return root
        }
        for subview in root.subviews {
            if let match = findView(withAccessibilityIdentifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }
}
