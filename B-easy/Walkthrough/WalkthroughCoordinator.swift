import UIKit

final class WalkthroughCoordinator: NSObject, WalkthroughOverlayViewDelegate {

    static let shared = WalkthroughCoordinator()

    private(set) var activeOverlay: WalkthroughOverlayView?
    private(set) var currentStep: WalkthroughStep = .welcome
    private weak var hostTabBarController: UITabBarController?
    private(set) var isRunning: Bool = false

    private override init() {
        super.init()
    }

    // MARK: - Entry Points

    /// Checks if first-time walkthrough should be presented, and presents it if eligible.
    func checkAndStartWalkthroughIfNeeded(from viewController: UIViewController) {
        guard !isRunning, activeOverlay == nil else { return }

        let shouldShow = WalkthroughManager.shared.shouldShowWalkthrough()
        guard shouldShow else { return }

        // Start after slight delay so view layout and network fetches stabilize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak viewController] in
            guard let self = self, let vc = viewController, !self.isRunning, self.activeOverlay == nil else { return }
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

        // Remove any existing overlay view from the window or activeOverlay to prevent duplicate overlays
        window.subviews.compactMap { $0 as? WalkthroughOverlayView }.forEach { $0.removeFromSuperview() }
        self.activeOverlay?.removeFromSuperview()
        self.activeOverlay = nil

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
            currentStep = isReplay ? .revenue : .welcome
        }
        #else
        currentStep = isReplay ? .revenue : .welcome
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

        case .revenue:
            tabBar.selectedIndex = 0
            ensureDashboardVisible(tabBar: tabBar) { [weak self, weak overlay] in
                guard let self = self, let overlay = overlay else { return }
                let cutouts = self.resolveRevenueCutout(in: tabBar, overlay: overlay)
                overlay.configure(step: step, cutouts: cutouts, canGoBack: canGoBack, animated: animated)
            }

        case .inventory:
            tabBar.selectedIndex = 0
            ensureDashboardVisible(tabBar: tabBar) { [weak self, weak overlay] in
                guard let self = self, let overlay = overlay else { return }
                let cutouts = self.resolveInventoryCutout(in: tabBar, overlay: overlay)
                overlay.configure(step: step, cutouts: cutouts, canGoBack: canGoBack, animated: animated)
            }

        case .alerts:
            tabBar.selectedIndex = 0
            ensureDashboardVisible(tabBar: tabBar) { [weak self, weak overlay] in
                guard let self = self, let overlay = overlay else { return }
                let cutouts = self.resolveAlertsCutouts(in: tabBar, overlay: overlay)
                overlay.configure(step: step, cutouts: cutouts, canGoBack: canGoBack, animated: animated)
            }

        case .assistant:
            tabBar.selectedIndex = 0
            ensureDashboardVisible(tabBar: tabBar) { [weak self, weak overlay] in
                guard let self = self, let overlay = overlay else { return }
                let cutouts = self.resolveAssistantCutout(in: tabBar, overlay: overlay)
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
        isRunning = false
        guard let overlay = activeOverlay else {
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

    // MARK: - Dashboard Step Resolvers (Revenue, Inventory, Alerts, Assistant)

    private func resolveRevenueCutout(in tabBar: UITabBarController, overlay: UIView) -> [WalkthroughCutout] {
        guard let dashboardVC = findDashboardViewController(in: tabBar),
              let tableView = dashboardVC.tableView else { return [] }

        tableView.setContentOffset(.zero, animated: false)
        tableView.layoutIfNeeded()

        guard let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? DashboardTopTileTableViewCell else {
            let rowRect = tableView.rectForRow(at: IndexPath(row: 0, section: 0))
            let converted = tableView.convert(rowRect, to: overlay)
            return [WalkthroughCutout(rect: converted, cornerRadius: 16)]
        }

        if let cutout = WalkthroughCoordinator.createRevenueSectionCutout(for: cell, in: overlay) {
            return [cutout]
        }

        let cellRect = cell.convert(cell.bounds, to: overlay)
        return [WalkthroughCutout(rect: cellRect, cornerRadius: 16)]
    }

    static func createRevenueSectionCutout(for cell: DashboardTopTileTableViewCell, in overlay: UIView) -> WalkthroughCutout? {
        guard let card = cell.segmentedCardBackground else { return nil }
        let cardRect = card.convert(card.bounds, to: overlay)
        guard cardRect.width > 50, cardRect.height > 50, overlay.bounds.intersects(cardRect) else { return nil }

        let w = card.bounds.width
        let h = card.bounds.height
        let r = card.cornerRadius
        let cw = card.cutoutWidth
        let ch = card.cutoutHeight
        let slantOffset: CGFloat = 34

        // Exact outer contour of the Revenue section, following its curved transition
        // and rounded corners while strictly excluding the Inventory pill at top-right
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: r))
        // Top-left corner
        path.addArc(withCenter: CGPoint(x: r, y: r), radius: r, startAngle: .pi, endAngle: -.pi/2, clockwise: true)
        // Top edge to start of slant
        path.addLine(to: CGPoint(x: w - cw - slantOffset, y: 0))
        // Smooth slanted S-curve down to the lower lip
        path.addCurve(
            to: CGPoint(x: w - cw, y: ch),
            controlPoint1: CGPoint(x: w - cw - slantOffset + 12, y: 0),
            controlPoint2: CGPoint(x: w - cw - 12, y: ch)
        )
        // Lower lip edge
        path.addLine(to: CGPoint(x: w - r, y: ch))
        // Corner below cutout
        path.addArc(withCenter: CGPoint(x: w - r, y: ch + r), radius: r, startAngle: -.pi/2, endAngle: 0, clockwise: true)
        // Right edge
        path.addLine(to: CGPoint(x: w, y: h - r))
        // Bottom-right corner
        path.addArc(withCenter: CGPoint(x: w - r, y: h - r), radius: r, startAngle: 0, endAngle: .pi/2, clockwise: true)
        // Bottom edge
        path.addLine(to: CGPoint(x: r, y: h))
        // Bottom-left corner
        path.addArc(withCenter: CGPoint(x: r, y: h - r), radius: r, startAngle: .pi/2, endAngle: .pi, clockwise: true)
        path.close()

        path.apply(CGAffineTransform(translationX: cardRect.minX, y: cardRect.minY))
        return WalkthroughCutout(rect: cardRect, cornerRadius: r, customPath: path)
    }

    private func resolveInventoryCutout(in tabBar: UITabBarController, overlay: UIView) -> [WalkthroughCutout] {
        guard let dashboardVC = findDashboardViewController(in: tabBar),
              let tableView = dashboardVC.tableView else { return [] }

        tableView.setContentOffset(.zero, animated: false)
        tableView.layoutIfNeeded()

        guard let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? DashboardTopTileTableViewCell else {
            return []
        }

        if let cutout = WalkthroughCoordinator.createInventoryPillCutout(for: cell, in: overlay) {
            return [cutout]
        }

        return []
    }

    static func createInventoryPillCutout(for cell: DashboardTopTileTableViewCell, in overlay: UIView) -> WalkthroughCutout? {
        guard let card = cell.segmentedCardBackground else { return nil }

        // Find right pill button ("Inventory")
        var pillButton: UIButton?
        for subview in card.subviews {
            if let btn = subview as? UIButton, btn.title(for: .normal) == "Inventory" || (btn.layer.cornerRadius == 18 && btn.frame.minX > card.bounds.width / 2) {
                pillButton = btn
                break
            }
        }

        if let btn = pillButton {
            let rect = btn.convert(btn.bounds, to: overlay)
            if rect.width > 20 && rect.height > 10 && overlay.bounds.intersects(rect) {
                let radius = btn.layer.cornerRadius > 0 ? btn.layer.cornerRadius : 18
                let pillPath = UIBezierPath(roundedRect: rect, cornerRadius: radius)
                return WalkthroughCutout(rect: rect, cornerRadius: radius, customPath: pillPath)
            }
        }

        // Fallback: pill frame relative to card
        let cardRect = card.convert(card.bounds, to: overlay)
        let fallbackRect = CGRect(x: cardRect.maxX - 134 - 8, y: cardRect.minY + 2, width: 134, height: 36)
        let pillPath = UIBezierPath(roundedRect: fallbackRect, cornerRadius: 18)
        return WalkthroughCutout(rect: fallbackRect, cornerRadius: 18, customPath: pillPath)
    }

    private func resolveAlertsCutouts(in tabBar: UITabBarController, overlay: UIView) -> [WalkthroughCutout] {
        guard let dashboardVC = findDashboardViewController(in: tabBar),
              let tableView = dashboardVC.tableView else { return [] }

        tableView.setContentOffset(.zero, animated: false)
        tableView.layoutIfNeeded()

        guard let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? DashboardTopTileTableViewCell else {
            return []
        }

        var cutouts: [WalkthroughCutout] = []

        // 1. Low Stock Alert — complete rounded card
        if let lowStockCard = cell.lowStockButton?.superview {
            let rect = lowStockCard.convert(lowStockCard.bounds, to: overlay)
            if rect.width > 50 && rect.height > 30 && overlay.bounds.intersects(rect) {
                let radius = lowStockCard.layer.cornerRadius > 0 ? lowStockCard.layer.cornerRadius : 26
                cutouts.append(WalkthroughCutout(rect: rect, cornerRadius: radius))
            }
        }

        // 2. Expiry Alert — complete rounded card
        if let expiryCard = cell.expiryAlertButton?.superview {
            let rect = expiryCard.convert(expiryCard.bounds, to: overlay)
            if rect.width > 50 && rect.height > 30 && overlay.bounds.intersects(rect) {
                let radius = expiryCard.layer.cornerRadius > 0 ? expiryCard.layer.cornerRadius : 26
                cutouts.append(WalkthroughCutout(rect: rect, cornerRadius: radius))
            }
        }

        if cutouts.count == 2 {
            return cutouts
        }

        // Fallback: estimated alert card positions
        let cardRect = cell.convert(cell.bounds, to: overlay)
        let alertY = cardRect.minY + 230
        let w = (overlay.bounds.width - 36 - 12) / 2
        let lowRect = CGRect(x: 18, y: alertY, width: w, height: 72)
        let expRect = CGRect(x: 18 + w + 12, y: alertY, width: w, height: 72)
        return [
            WalkthroughCutout(rect: lowRect, cornerRadius: 26),
            WalkthroughCutout(rect: expRect, cornerRadius: 26)
        ]
    }

    private func resolveAssistantCutout(in tabBar: UITabBarController, overlay: UIView) -> [WalkthroughCutout] {
        guard let dashboardVC = findDashboardViewController(in: tabBar) else { return [] }

        dashboardVC.view.layoutIfNeeded()

        var assistantBtn: UIButton?
        for subview in dashboardVC.view.subviews {
            if let btn = subview as? UIButton,
               btn.accessibilityLabel == "Assistant" ||
               btn.accessibilityIdentifier == "dashboard_assistant_button" ||
               (btn.layer.cornerRadius == 25 && btn.frame.width == 50) {
                assistantBtn = btn
                break
            }
        }

        if let btn = assistantBtn {
            let rect = btn.convert(btn.bounds, to: overlay)
            if rect.width > 20 && rect.height > 20 && overlay.bounds.intersects(rect) {
                let radius = rect.width / 2
                let circlePath = UIBezierPath(ovalIn: rect)
                return [WalkthroughCutout(rect: rect, cornerRadius: radius, customPath: circlePath)]
            }
        }

        // Fallback: expected position of floating assistant button
        let screenWidth = overlay.bounds.width
        let screenHeight = overlay.bounds.height
        let btnX = screenWidth - overlay.safeAreaInsets.right - 26 - 50
        let btnY = screenHeight - 170
        let fallbackRect = CGRect(x: btnX, y: btnY, width: 50, height: 50)
        let circlePath = UIBezierPath(ovalIn: fallbackRect)
        return [WalkthroughCutout(rect: fallbackRect, cornerRadius: 25, customPath: circlePath)]
    }

    static func createCombinedChartCutout(for cell: DashboardTopTileTableViewCell, in overlay: UIView) -> WalkthroughCutout? {
        guard let card = cell.segmentedCardBackground else { return nil }
        let cardRect = card.convert(card.bounds, to: overlay)
        guard cardRect.width > 50, cardRect.height > 50, overlay.bounds.intersects(cardRect) else { return nil }

        let w = card.bounds.width
        let h = card.bounds.height
        let r = card.cornerRadius
        let cw = card.cutoutWidth
        let slant: CGFloat = 34

        // Locate pill button inside card
        var pillButton: UIButton?
        for subview in card.subviews {
            if let btn = subview as? UIButton, btn.title(for: .normal) == "Inventory" || btn.layer.cornerRadius == 18 {
                pillButton = btn
                break
            }
        }

        let combinedPath = UIBezierPath()

        if card.cutoutOnRight {
            let px = pillButton?.frame.minX ?? (w - cw)
            let py = pillButton?.frame.minY ?? 2
            let pw = pillButton?.frame.width ?? 134
            let pr = pillButton?.layer.cornerRadius ?? 18

            // 1. Top-left corner
            combinedPath.move(to: CGPoint(x: 0, y: r))
            combinedPath.addArc(withCenter: CGPoint(x: r, y: r), radius: r, startAngle: .pi, endAngle: -.pi/2, clockwise: true)

            // 2. Top edge of Revenue section
            combinedPath.addLine(to: CGPoint(x: w - cw - slant, y: 0))

            // 3. Smooth natural bridge from Revenue top into Inventory pill top
            combinedPath.addCurve(
                to: CGPoint(x: px + pr, y: py),
                controlPoint1: CGPoint(x: w - cw - slant + 15, y: 0),
                controlPoint2: CGPoint(x: px + pr - 15, y: py)
            )

            // 4. Top edge of Inventory selector pill
            combinedPath.addLine(to: CGPoint(x: px + pw - pr, y: py))

            // 5. Right cap of Inventory selector pill
            combinedPath.addArc(withCenter: CGPoint(x: px + pw - pr, y: py + pr), radius: pr, startAngle: -.pi/2, endAngle: 0, clockwise: true)

            // 6. Smooth connection down to card's right boundary
            combinedPath.addCurve(
                to: CGPoint(x: w, y: card.cutoutHeight + r),
                controlPoint1: CGPoint(x: px + pw, y: py + pr + 15),
                controlPoint2: CGPoint(x: w, y: card.cutoutHeight)
            )

            // 7. Right edge down to bottom corner
            combinedPath.addLine(to: CGPoint(x: w, y: h - r))

            // 8. Bottom-right corner
            combinedPath.addArc(withCenter: CGPoint(x: w - r, y: h - r), radius: r, startAngle: 0, endAngle: .pi/2, clockwise: true)

            // 9. Bottom edge
            combinedPath.addLine(to: CGPoint(x: r, y: h))

            // 10. Bottom-left corner
            combinedPath.addArc(withCenter: CGPoint(x: r, y: h - r), radius: r, startAngle: .pi/2, endAngle: .pi, clockwise: true)

            // 11. Left edge back to start
            combinedPath.addLine(to: CGPoint(x: 0, y: r))
            combinedPath.close()
        } else {
            // Cutout on left (when Inventory is the active card)
            let px = pillButton?.frame.minX ?? 8
            let py = pillButton?.frame.minY ?? 2
            let pw = pillButton?.frame.width ?? 134
            let pr = pillButton?.layer.cornerRadius ?? 18

            // Start at top-right corner
            combinedPath.move(to: CGPoint(x: w - r, y: 0))
            combinedPath.addArc(withCenter: CGPoint(x: w - r, y: r), radius: r, startAngle: -.pi/2, endAngle: 0, clockwise: true)

            // Right edge down to bottom
            combinedPath.addLine(to: CGPoint(x: w, y: h - r))

            // Bottom-right corner
            combinedPath.addArc(withCenter: CGPoint(x: w - r, y: h - r), radius: r, startAngle: 0, endAngle: .pi/2, clockwise: true)

            // Bottom edge
            combinedPath.addLine(to: CGPoint(x: r, y: h))

            // Bottom-left corner
            combinedPath.addArc(withCenter: CGPoint(x: r, y: h - r), radius: r, startAngle: .pi/2, endAngle: .pi, clockwise: true)

            // Left edge up to cutout
            combinedPath.addLine(to: CGPoint(x: 0, y: card.cutoutHeight + r))

            // Curve to left cap of pill
            combinedPath.addCurve(
                to: CGPoint(x: px, y: py + pr),
                controlPoint1: CGPoint(x: 0, y: card.cutoutHeight),
                controlPoint2: CGPoint(x: px, y: py + pr + 15)
            )

            // Left cap of pill
            combinedPath.addArc(withCenter: CGPoint(x: px + pr, y: py + pr), radius: pr, startAngle: .pi, endAngle: -.pi/2, clockwise: true)

            // Top edge of pill
            combinedPath.addLine(to: CGPoint(x: px + pw - pr, y: py))

            // Smooth bridge into main card top
            combinedPath.addCurve(
                to: CGPoint(x: cw + slant, y: 0),
                controlPoint1: CGPoint(x: px + pw - pr + 15, y: py),
                controlPoint2: CGPoint(x: cw + slant - 15, y: 0)
            )

            combinedPath.addLine(to: CGPoint(x: w - r, y: 0))
            combinedPath.close()
        }

        // Apply translation to overlay coordinate space
        combinedPath.apply(CGAffineTransform(translationX: cardRect.minX, y: cardRect.minY))

        return WalkthroughCutout(rect: cardRect, cornerRadius: card.cornerRadius, customPath: combinedPath)
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
        if tableView.numberOfSections > 2 && tableView.numberOfRows(inSection: 2) > 0 {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 2), at: .middle, animated: false)
            tableView.layoutIfNeeded()
        }

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
                    let label = button.titleLabel ?? button
                    let buttonConverted = label.convert(label.bounds, to: overlay)

                    // Fit to actual text bounds while preserving enough vertical padding (4pt)
                    // so ascenders and descenders ('p', 'g', etc.) are never clipped.
                    // Use a subtle corner radius (3pt) so they read as text highlights,
                    // not like separate pill buttons.
                    let vPadding: CGFloat = 4
                    let hPadding: CGFloat = 5
                    let titleRect = titleConverted.insetBy(dx: -hPadding, dy: -vPadding)
                    let buttonRect = buttonConverted.insetBy(dx: -hPadding, dy: -vPadding)

                    if titleRect.width > 20 && buttonRect.width > 20 &&
                       overlay.bounds.intersects(titleRect) && overlay.bounds.intersects(buttonRect) {
                        completion([
                            WalkthroughCutout(rect: titleRect, cornerRadius: 3),
                            WalkthroughCutout(rect: buttonRect, cornerRadius: 3)
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
                let cardRadius = paySuper.layer.cornerRadius > 0 ? paySuper.layer.cornerRadius : 30
                // Two distinct rounded card cutouts preserve the native gap and roundings
                return [
                    WalkthroughCutout(rect: payRect, cornerRadius: cardRadius),
                    WalkthroughCutout(rect: getRect, cornerRadius: cardRadius)
                ]
            }
        }

        let cellRect = cell.convert(cell.bounds, to: overlay)
        let cardWidth = (cellRect.width - 32 - 12) / 2
        let card1 = CGRect(x: 16, y: cellRect.maxY - 130, width: cardWidth, height: 112)
        let card2 = CGRect(x: 16 + cardWidth + 12, y: cellRect.maxY - 130, width: cardWidth, height: 112)
        return [
            WalkthroughCutout(rect: card1, cornerRadius: 30),
            WalkthroughCutout(rect: card2, cornerRadius: 30)
        ]
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
            if let cutout = self.findTabBarItemCutout(at: stockIdx, in: tabBar, overlay: overlay) {
                completion([cutout])
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

        // Scan and Manual controls:
        // Each consists of a 54pt circular button on top (centerY - 27 to centerY + 27)
        // and a 16pt text label below (centerY + 33 to centerY + 49).
        // With 6pt padding top and bottom:
        // topY = centerY - 33, height = 88pt.
        // With width = 66pt (providing balanced padding for both the 54pt circle and text labels),
        // cornerRadius = 22pt smoothly matches the curvature of the circular button at the top
        // and cleanly encloses the label without clipping.
        let buttonWidth: CGFloat = 66
        let buttonHeight: CGFloat = 88
        let topY = centerY - 33

        let scanCenterX = rowRect.minX + 35
        let scanRect = CGRect(
            x: scanCenterX - (buttonWidth / 2),
            y: topY,
            width: buttonWidth,
            height: buttonHeight
        )
        let scanCutout = WalkthroughCutout(rect: scanRect, cornerRadius: 22)

        let manualCenterX = rowRect.maxX - 35
        let manualRect = CGRect(
            x: manualCenterX - (buttonWidth / 2),
            y: topY,
            width: buttonWidth,
            height: buttonHeight
        )
        let manualCutout = WalkthroughCutout(rect: manualRect, cornerRadius: 22)

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

    private func findTabBarItemCutout(at index: Int, in tabBar: UITabBarController, overlay: UIView) -> WalkthroughCutout? {
        let bar = tabBar.tabBar
        bar.layoutIfNeeded()

        func findRecursiveViews(in root: UIView, matching: (UIView) -> Bool) -> [UIView] {
            var views: [UIView] = []
            if matching(root) { views.append(root) }
            for sub in root.subviews {
                views.append(contentsOf: findRecursiveViews(in: sub, matching: matching))
            }
            return views
        }

        // 1. Check for modern iOS 18 platter item / liquid lens or selection view
        let selectionViews = findRecursiveViews(in: bar) { view in
            let name = "\(type(of: view))"
            return name.contains("LiquidLens") || name.contains("TabSelection") || name.contains("DestOutView")
        }
        for selView in selectionViews {
            let rect = selView.convert(selView.bounds, to: overlay)
            if rect.width > 30 && rect.height > 20 && overlay.bounds.intersects(rect) {
                let radius = selView.layer.cornerRadius > 0 ? selView.layer.cornerRadius : (rect.height / 2)
                return WalkthroughCutout(rect: rect, cornerRadius: radius)
            }
        }

        // 2. Look for tab buttons (_UITabButton or UITabBarButton)
        let tabButtons = findRecursiveViews(in: bar) { view in
            let name = "\(type(of: view))"
            return name.contains("TabButton") || name.contains("TabBarButton")
        }
        let uniqueButtons = tabButtons
            .filter { $0.bounds.width > 30 && $0.bounds.height > 20 }
            .sorted { $0.convert($0.bounds, to: overlay).minX < $1.convert($1.bounds, to: overlay).minX }

        if index < uniqueButtons.count {
            let button = uniqueButtons[index]
            let buttonRect = button.convert(button.bounds, to: overlay)
            let radius = button.layer.cornerRadius > 0 ? button.layer.cornerRadius : (buttonRect.height / 2)
            return WalkthroughCutout(rect: buttonRect, cornerRadius: radius)
        }

        // 3. Fallback: calculate natural tab item bounds
        let totalItems = CGFloat(max(bar.items?.count ?? 4, 1))
        let itemWidth = bar.bounds.width / totalItems
        let itemX = CGFloat(index) * itemWidth
        let fallbackRect = CGRect(x: itemX + 4, y: bar.convert(CGPoint(x: 0, y: 4), to: overlay).y, width: itemWidth - 8, height: 54)
        return WalkthroughCutout(rect: fallbackRect, cornerRadius: 27)
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
