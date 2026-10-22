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

        #if DEBUG
        if let stepArgIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "--walkthrough-step"),
           stepArgIndex + 1 < ProcessInfo.processInfo.arguments.count,
           let stepRaw = Int(ProcessInfo.processInfo.arguments[stepArgIndex + 1]),
           let requestedStep = WalkthroughStep(rawValue: stepRaw) {
            currentStep = requestedStep
        } else {
            currentStep = isReplay ? .dashboardOverview : .welcome
        }
        #else
        currentStep = isReplay ? .dashboardOverview : .welcome
        #endif
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
            overlay.configure(step: step, cutouts: [], canGoBack: canGoBack, animated: animated)

        case .dashboardOverview:
            tabBar.selectedIndex = 0
            ensureDashboardVisible(tabBar: tabBar) { [weak self, weak overlay] in
                guard let self = self, let overlay = overlay else { return }
                let cutouts = self.resolveDashboardOverviewCutouts(in: tabBar, overlay: overlay)
                overlay.configure(step: step, cutouts: cutouts, canGoBack: canGoBack, animated: animated)
            }

        case .analytics:
            tabBar.selectedIndex = 0
            ensureDashboardVisible(tabBar: tabBar) { [weak self, weak overlay] in
                guard let self = self, let overlay = overlay else { return }
                self.resolveAnalyticsReportsCutouts(in: tabBar, overlay: overlay) { cutouts in
                    overlay.configure(step: step, cutouts: cutouts, canGoBack: canGoBack, animated: animated)
                }
            }

        case .creditDetails:
            tabBar.selectedIndex = 0
            ensureDashboardVisible(tabBar: tabBar) { [weak self, weak overlay] in
                guard let self = self, let overlay = overlay else { return }
                let cutouts = self.resolveCreditDetailsCutouts(in: tabBar, overlay: overlay)
                overlay.configure(step: step, cutouts: cutouts, canGoBack: canGoBack, animated: animated)
            }

        case .stockTab:
            resolveStockTabCutouts(in: tabBar, overlay: overlay) { [weak overlay] cutouts in
                overlay?.configure(step: step, cutouts: cutouts, canGoBack: canGoBack, animated: animated)
            }

        case .stockActions:
            resolveStockActionsCutouts(in: tabBar, overlay: overlay) { [weak overlay] cutouts in
                overlay?.configure(step: step, cutouts: cutouts, canGoBack: canGoBack, animated: animated)
            }

        case .salesActions:
            resolveSalesActionsCutouts(in: tabBar, overlay: overlay) { [weak overlay] cutouts in
                overlay?.configure(step: step, cutouts: cutouts, canGoBack: canGoBack, animated: animated)
            }

        case .completion:
            tabBar.selectedIndex = 0
            overlay.configure(step: step, cutouts: [], canGoBack: canGoBack, animated: animated)
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

    // MARK: - Target Rect & Cutout Resolvers

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

    func findStockTabIndex(in tabBar: UITabBarController) -> Int {
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

    func findSalesTabIndex(in tabBar: UITabBarController) -> Int {
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

    private func resolveDashboardOverviewCutouts(in tabBar: UITabBarController, overlay: UIView) -> [WalkthroughCutout] {
        guard let dashboardVC = findDashboardViewController(in: tabBar),
              let tableView = dashboardVC.tableView else { return [] }

        // Scroll to top cell
        tableView.setContentOffset(.zero, animated: false)
        tableView.layoutIfNeeded()

        guard let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? DashboardTopTileTableViewCell else {
            let rowRect = tableView.rectForRow(at: IndexPath(row: 0, section: 0))
            let converted = tableView.convert(rowRect, to: overlay)
            return [WalkthroughCutout(rect: converted, cornerRadius: 16)]
        }

        if let card = cell.segmentedCardBackground {
            let rect = card.convert(card.bounds, to: overlay)
            if rect.width > 50 && rect.height > 50 && overlay.bounds.intersects(rect) {
                return [WalkthroughCutout(rect: rect, cornerRadius: 16)]
            }
        }

        let cellRect = cell.convert(cell.bounds, to: overlay)
        return [WalkthroughCutout(rect: cellRect, cornerRadius: 16)]
    }

    private func resolveAnalyticsReportsCutouts(
        in tabBar: UITabBarController,
        overlay: UIView,
        completion: @escaping ([WalkthroughCutout]) -> Void
    ) {
        guard let dashboardVC = findDashboardViewController(in: tabBar),
              let tableView = dashboardVC.tableView else {
            completion([])
            return
        }

        // Scroll so Reports section header is in clear view
        tableView.scrollToRow(at: IndexPath(row: 0, section: 2), at: .middle, animated: false)
        tableView.layoutIfNeeded()

        DispatchQueue.main.async { [weak self, weak overlay] in
            guard let self = self, let overlay = overlay else {
                completion([])
                return
            }
            tableView.layoutIfNeeded()

            if let headerView = self.findView(withAccessibilityIdentifier: "dashboard_reports_header", in: tableView) {
                let titleLabel = self.findFirstSubview(ofType: UILabel.self, in: headerView)
                let viewAllButton = self.findFirstSubview(ofType: UIButton.self, in: headerView)

                if let title = titleLabel, let button = viewAllButton {
                    let titleConverted = title.convert(title.bounds, to: overlay)
                    let buttonConverted = button.convert(button.bounds, to: overlay)
                    let labelRect = button.titleLabel?.convert(button.titleLabel?.bounds ?? button.bounds, to: overlay) ?? buttonConverted
                    let midY = (titleConverted.midY + labelRect.midY) / 2
                    let targetHeight: CGFloat = 26
                    let titleRect = CGRect(
                        x: titleConverted.minX - 5,
                        y: midY - (targetHeight / 2),
                        width: titleConverted.width + 10,
                        height: targetHeight
                    )
                    let buttonRect = CGRect(
                        x: labelRect.minX - 6,
                        y: midY - (targetHeight / 2),
                        width: labelRect.width + 12,
                        height: targetHeight
                    )

                    if titleRect.width > 20 && buttonRect.width > 20 &&
                       overlay.bounds.intersects(titleRect) && overlay.bounds.intersects(buttonRect) {
                        completion([
                            WalkthroughCutout(rect: titleRect, cornerRadius: 6),
                            WalkthroughCutout(rect: buttonRect, cornerRadius: 6)
                        ])
                        return
                    }
                }

                // If individual labels aren't isolated, frame the header compactly with natural insets
                let converted = headerView.convert(headerView.bounds, to: overlay)
                let snugRect = CGRect(x: 16, y: converted.minY, width: overlay.bounds.width - 32, height: max(converted.height, 44))
                completion([WalkthroughCutout(rect: snugRect, cornerRadius: 12)])
                return
            }

            // Fallback: table header rect
            let headerRect = tableView.rectForHeader(inSection: 2)
            if !headerRect.isEmpty {
                let converted = tableView.convert(headerRect, to: overlay)
                if overlay.bounds.intersects(converted) && converted.minY > 0 {
                    let snugRect = CGRect(x: 16, y: converted.minY, width: overlay.bounds.width - 32, height: max(converted.height, 44))
                    completion([WalkthroughCutout(rect: snugRect, cornerRadius: 12)])
                    return
                }
            }

            completion([])
        }
    }

    private func resolveCreditDetailsCutouts(in tabBar: UITabBarController, overlay: UIView) -> [WalkthroughCutout] {
        guard let dashboardVC = findDashboardViewController(in: tabBar),
              let tableView = dashboardVC.tableView else { return [] }

        tableView.setContentOffset(.zero, animated: false)
        tableView.layoutIfNeeded()

        guard let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? DashboardTopTileTableViewCell else {
            return []
        }

        // Locate credit cards via labels superviews
        if let paySuper = cell.youWillPayLabel?.superview,
           let getSuper = cell.youWillGetLabel?.superview {
            let payRect = paySuper.convert(paySuper.bounds, to: overlay)
            let getRect = getSuper.convert(getSuper.bounds, to: overlay)

            if payRect.width > 40 && getRect.width > 40 &&
               overlay.bounds.intersects(payRect) && overlay.bounds.intersects(getRect) {
                let cardRadius = paySuper.layer.cornerRadius > 0 ? paySuper.layer.cornerRadius : 26
                // Two distinct rounded card cutouts preserve the native gap and roundings
                return [
                    WalkthroughCutout(rect: payRect, cornerRadius: cardRadius),
                    WalkthroughCutout(rect: getRect, cornerRadius: cardRadius)
                ]
            }
        }

        let cellRect = cell.convert(cell.bounds, to: overlay)
        let fallback = CGRect(x: 16, y: cellRect.maxY - 140, width: cellRect.width - 32, height: 125)
        return [WalkthroughCutout(rect: fallback, cornerRadius: 26)]
    }

    private func resolveStockTabCutouts(
        in tabBar: UITabBarController,
        overlay: UIView,
        completion: @escaping ([WalkthroughCutout]) -> Void
    ) {
        let stockIdx = findStockTabIndex(in: tabBar)
        tabBar.selectedIndex = stockIdx

        DispatchQueue.main.async { [weak self, weak overlay] in
            guard let self = self, let overlay = overlay else {
                completion([])
                return
            }
            let rect = self.findTabBarItemRect(at: stockIdx, in: tabBar, overlay: overlay)
            if rect.width > 12 && rect.height > 12 && overlay.bounds.intersects(rect) {
                let radius: CGFloat = 8
                completion([WalkthroughCutout(rect: rect, cornerRadius: radius)])
            } else {
                completion([])
            }
        }
    }

    private func resolveStockActionsCutouts(
        in tabBar: UITabBarController,
        overlay: UIView,
        retryCount: Int = 0,
        completion: @escaping ([WalkthroughCutout]) -> Void
    ) {
        let stockIdx = findStockTabIndex(in: tabBar)
        if tabBar.selectedIndex != stockIdx {
            tabBar.selectedIndex = stockIdx
        }

        guard let controllers = tabBar.viewControllers, stockIdx < controllers.count,
              let nav = controllers[stockIdx] as? UINavigationController,
              let stockVC = nav.viewControllers.first as? StockViewController else {
            completion([])
            return
        }

        stockVC.view.layoutIfNeeded()

        // 1. Check if stockVC has reported a valid global frame from SwiftUI
        if let globalFrame = stockVC.actionButtonsGlobalFrame,
           globalFrame.width > 100, globalFrame.height > 40 {
            let rectInOverlay = overlay.convert(globalFrame, from: nil)
            if isValidActionPanelRect(rectInOverlay, in: overlay) {
                let cutouts = generateActionPanelCutouts(from: rectInOverlay)
                completion(cutouts)
                return
            }
        }

        // 2. Check if the accessibility view can be located in the view hierarchy
        if let actionRow = findView(withAccessibilityIdentifier: "stock_action_buttons_row", in: stockVC.view) {
            let rectInOverlay = actionRow.convert(actionRow.bounds, to: overlay)
            if isValidActionPanelRect(rectInOverlay, in: overlay) {
                let cutouts = generateActionPanelCutouts(from: rectInOverlay)
                completion(cutouts)
                return
            }
        }

        // 3. Retry while SwiftUI completes first rendering pass
        if retryCount < 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.resolveStockActionsCutouts(
                    in: tabBar,
                    overlay: overlay,
                    retryCount: retryCount + 1,
                    completion: completion
                )
            }
            return
        }

        // 4. Safe fallback: derive from stockVC.view bounds
        let viewRect = stockVC.view.convert(stockVC.view.bounds, to: overlay)
        let fallback = generateFallbackActionPanelCutouts(in: viewRect, overlay: overlay)
        completion(fallback)
    }

    private func resolveSalesActionsCutouts(
        in tabBar: UITabBarController,
        overlay: UIView,
        retryCount: Int = 0,
        completion: @escaping ([WalkthroughCutout]) -> Void
    ) {
        let salesIdx = findSalesTabIndex(in: tabBar)
        if tabBar.selectedIndex != salesIdx {
            tabBar.selectedIndex = salesIdx
        }

        guard let controllers = tabBar.viewControllers, salesIdx < controllers.count,
              let nav = controllers[salesIdx] as? UINavigationController,
              let salesVC = nav.viewControllers.first as? SalesViewController else {
            completion([])
            return
        }

        salesVC.view.layoutIfNeeded()

        // 1. Check if salesVC has reported a valid global frame from SwiftUI
        if let globalFrame = salesVC.actionButtonsGlobalFrame,
           globalFrame.width > 100, globalFrame.height > 40 {
            let rectInOverlay = overlay.convert(globalFrame, from: nil)
            if isValidActionPanelRect(rectInOverlay, in: overlay) {
                let cutouts = generateActionPanelCutouts(from: rectInOverlay)
                completion(cutouts)
                return
            }
        }

        // 2. Check if the accessibility view can be located in the view hierarchy
        if let actionRow = findView(withAccessibilityIdentifier: "sales_action_buttons_row", in: salesVC.view) {
            let rectInOverlay = actionRow.convert(actionRow.bounds, to: overlay)
            if isValidActionPanelRect(rectInOverlay, in: overlay) {
                let cutouts = generateActionPanelCutouts(from: rectInOverlay)
                completion(cutouts)
                return
            }
        }

        // 3. Retry while SwiftUI completes first rendering pass
        if retryCount < 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.resolveSalesActionsCutouts(
                    in: tabBar,
                    overlay: overlay,
                    retryCount: retryCount + 1,
                    completion: completion
                )
            }
            return
        }

        // 4. Safe fallback: derive from salesVC.view bounds
        let viewRect = salesVC.view.convert(salesVC.view.bounds, to: overlay)
        let fallback = generateFallbackActionPanelCutouts(in: viewRect, overlay: overlay)
        completion(fallback)
    }

    /// Recalculates and animates the spotlight when view layout finishes or updates.
    func refreshSpotlightIfCurrent(step: WalkthroughStep) {
        guard isRunning, currentStep == step, let overlay = activeOverlay, let tabBar = hostTabBarController else { return }
        switch step {
        case .stockActions:
            resolveStockActionsCutouts(in: tabBar, overlay: overlay) { [weak overlay] cutouts in
                overlay?.updateCutouts(cutouts, for: step, animated: true)
            }
        case .salesActions:
            resolveSalesActionsCutouts(in: tabBar, overlay: overlay) { [weak overlay] cutouts in
                overlay?.updateCutouts(cutouts, for: step, animated: true)
            }
        default:
            return
        }
    }

    // MARK: - Action Panel Spotlight Geometry

    private func isValidActionPanelRect(_ rect: CGRect, in overlay: UIView) -> Bool {
        guard rect.width >= 100, rect.height >= 40 else { return false }
        guard overlay.bounds.intersects(rect) else { return false }
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        guard overlay.bounds.contains(mid) else { return false }
        guard rect.minY >= overlay.safeAreaInsets.top + 40 else { return false }
        guard rect.maxY <= overlay.bounds.height - overlay.safeAreaInsets.bottom + 20 else { return false }
        return true
    }

    /// Produces distinct, clean circular and rounded-rectangle cutouts for Scan, Voice, and Manual controls.
    private func generateActionPanelCutouts(from rowRect: CGRect) -> [WalkthroughCutout] {
        let centerY = rowRect.midY

        // Voice button: circular cutout closely framing the 130x130 mic
        let voiceDiameter: CGFloat = 130
        let voiceRect = CGRect(
            x: rowRect.midX - (voiceDiameter / 2),
            y: centerY - (voiceDiameter / 2),
            width: voiceDiameter,
            height: voiceDiameter
        )
        let voiceCutout = WalkthroughCutout(rect: voiceRect, cornerRadius: voiceDiameter / 2)

        // Scan button: circle (54pt) + text ("Scan")
        let scanWidth: CGFloat = 56
        let scanHeight: CGFloat = 74
        let scanCenterX = rowRect.minX + 35
        let scanRect = CGRect(
            x: scanCenterX - (scanWidth / 2),
            y: centerY - 27 - 2,
            width: scanWidth,
            height: scanHeight
        )
        let scanCutout = WalkthroughCutout(rect: scanRect, cornerRadius: 14)

        // Manual button: circle (54pt) + text ("Manual")
        let manualWidth: CGFloat = 56
        let manualHeight: CGFloat = 74
        let manualCenterX = rowRect.maxX - 35
        let manualRect = CGRect(
            x: manualCenterX - (manualWidth / 2),
            y: centerY - 27 - 2,
            width: manualWidth,
            height: manualHeight
        )
        let manualCutout = WalkthroughCutout(rect: manualRect, cornerRadius: 14)

        return [scanCutout, voiceCutout, manualCutout]
    }

    private func generateFallbackActionPanelCutouts(in viewRect: CGRect, overlay: UIView) -> [WalkthroughCutout] {
        let screenWidth = overlay.bounds.width
        let rowWidth: CGFloat = min(330, screenWidth - 32)
        let rowHeight: CGFloat = 150
        let originX = (screenWidth - rowWidth) / 2
        // Default position: centered above bottom sheet area
        let originY = viewRect.maxY - 228 - rowHeight

        let rowRect = CGRect(x: originX, y: originY, width: rowWidth, height: rowHeight)
        return generateActionPanelCutouts(from: rowRect)
    }

    // MARK: - Tab Bar Button Geometry

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
            var contentRect: CGRect = .null
            for sub in button.subviews {
                let typeName = "\(type(of: sub))"
                if typeName.contains("ImageView") || typeName.contains("Label") {
                    let converted = sub.convert(sub.bounds, to: overlay)
                    contentRect = contentRect.isNull ? converted : contentRect.union(converted)
                }
            }

            if !contentRect.isNull && contentRect.width > 12 && contentRect.height > 12 {
                let padX: CGFloat = 8
                let padY: CGFloat = 4
                let width: CGFloat = contentRect.width + (padX * 2)
                let height: CGFloat = contentRect.height + (padY * 2)
                let originX = contentRect.midX - (width / 2)
                let originY = contentRect.midY - (height / 2)
                return CGRect(x: originX, y: originY, width: width, height: height)
            }

            let buttonRect = button.convert(button.bounds, to: overlay)
            let width: CGFloat = 48
            let height: CGFloat = 44
            let originX = buttonRect.midX - (width / 2)
            let originY = buttonRect.midY - (height / 2)
            return CGRect(x: originX, y: originY, width: width, height: height)
        }

        let width: CGFloat = 48
        let height: CGFloat = 44
        let originX = itemX + (itemWidth - width) / 2
        let originY = bar.convert(CGPoint(x: 0, y: 2), to: overlay).y
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    // MARK: - Hierarchy Inspection Helpers

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

    private func findFirstSubview<T: UIView>(ofType type: T.Type, in root: UIView) -> T? {
        if let match = root as? T {
            return match
        }
        for subview in root.subviews {
            if let match = findFirstSubview(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
