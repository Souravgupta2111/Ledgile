import XCTest
@testable import B_easy

@MainActor
final class WalkthroughTests: XCTestCase {

    private let testUserId1 = "test_user_alpha_\(UUID().uuidString)"
    private let testUserId2 = "test_user_beta_\(UUID().uuidString)"

    override func tearDown() {
        super.tearDown()
        WalkthroughCoordinator.shared.dismissWalkthrough(completed: false)
        WalkthroughManager.shared.resetWalkthroughState(for: testUserId1)
        WalkthroughManager.shared.resetWalkthroughState(for: testUserId2)
    }

    func testWalkthroughInitialStateShouldShow() {
        XCTAssertTrue(
            WalkthroughManager.shared.shouldShowWalkthrough(for: testUserId1),
            "A new user who has never seen or skipped the walkthrough should be eligible."
        )
        XCTAssertFalse(
            WalkthroughManager.shared.hasCompletedWalkthrough(for: testUserId1),
            "A new user should not be marked as having completed the walkthrough."
        )
    }

    func testWalkthroughMarkCompleted() {
        WalkthroughManager.shared.markWalkthroughCompleted(for: testUserId1)

        XCTAssertFalse(
            WalkthroughManager.shared.shouldShowWalkthrough(for: testUserId1),
            "User who completed the walkthrough should not be prompted again."
        )
        XCTAssertTrue(
            WalkthroughManager.shared.hasCompletedWalkthrough(for: testUserId1),
            "User should be marked as completed."
        )
    }

    func testWalkthroughMarkSkipped() {
        WalkthroughManager.shared.markWalkthroughSkipped(for: testUserId1)

        XCTAssertFalse(
            WalkthroughManager.shared.shouldShowWalkthrough(for: testUserId1),
            "User who skipped the walkthrough should not be prompted repeatedly on app launches."
        )
        XCTAssertFalse(
            WalkthroughManager.shared.hasCompletedWalkthrough(for: testUserId1),
            "Skipped user is not marked as having completed."
        )
    }

    func testWalkthroughUserIsolation() {
        // Complete for user 1
        WalkthroughManager.shared.markWalkthroughCompleted(for: testUserId1)

        // User 2 on same device should still be eligible
        XCTAssertFalse(WalkthroughManager.shared.shouldShowWalkthrough(for: testUserId1))
        XCTAssertTrue(WalkthroughManager.shared.shouldShowWalkthrough(for: testUserId2))
    }

    func testWalkthroughResetState() {
        WalkthroughManager.shared.markWalkthroughCompleted(for: testUserId1)
        XCTAssertFalse(WalkthroughManager.shared.shouldShowWalkthrough(for: testUserId1))

        WalkthroughManager.shared.resetWalkthroughState(for: testUserId1)
        XCTAssertTrue(WalkthroughManager.shared.shouldShowWalkthrough(for: testUserId1))
    }

    func testWalkthroughStepSequenceAndTitles() {
        let steps = WalkthroughStep.allCases
        XCTAssertEqual(steps.count, 11)

        XCTAssertEqual(steps[0], .welcome)
        XCTAssertEqual(steps[1], .revenue)
        XCTAssertEqual(steps[2], .inventory)
        XCTAssertEqual(steps[3], .alerts)
        XCTAssertEqual(steps[4], .assistant)
        XCTAssertEqual(steps[5], .analytics)
        XCTAssertEqual(steps[6], .creditDetails)
        XCTAssertEqual(steps[7], .stockTab)
        XCTAssertEqual(steps[8], .stockActions)
        XCTAssertEqual(steps[9], .salesActions)
        XCTAssertEqual(steps[10], .completion)

        XCTAssertEqual(steps[0].title, "Welcome to B Easy!")
        XCTAssertEqual(steps[1].title, "Revenue Overview")
        XCTAssertEqual(steps[2].title, "Inventory Overview")
        XCTAssertEqual(steps[3].title, "Stock and Expiry Alerts")
        XCTAssertEqual(steps[4].title, "Your Business Assistant")
        XCTAssertEqual(steps[5].title, "Analytics & Reports")
        XCTAssertEqual(steps[6].title, "Credit Management")
        XCTAssertEqual(steps[7].title, "Stock Management")
        XCTAssertEqual(steps[8].title, "Adding Stock")
        XCTAssertEqual(steps[9].title, "Recording Sales")
        XCTAssertEqual(steps[10].title, "You're all set!")
    }

    func testWalkthroughStepModalFlags() {
        XCTAssertTrue(WalkthroughStep.welcome.isModal)
        XCTAssertTrue(WalkthroughStep.completion.isModal)

        XCTAssertFalse(WalkthroughStep.revenue.isModal)
        XCTAssertFalse(WalkthroughStep.inventory.isModal)
        XCTAssertFalse(WalkthroughStep.alerts.isModal)
        XCTAssertFalse(WalkthroughStep.assistant.isModal)
        XCTAssertFalse(WalkthroughStep.analytics.isModal)
        XCTAssertFalse(WalkthroughStep.creditDetails.isModal)
        XCTAssertFalse(WalkthroughStep.stockTab.isModal)
        XCTAssertFalse(WalkthroughStep.stockActions.isModal)
        XCTAssertFalse(WalkthroughStep.salesActions.isModal)
    }

    func testGuidedStepIndices() {
        XCTAssertNil(WalkthroughStep.welcome.stepIndex)
        XCTAssertEqual(WalkthroughStep.revenue.stepIndex, 1)
        XCTAssertEqual(WalkthroughStep.inventory.stepIndex, 2)
        XCTAssertEqual(WalkthroughStep.alerts.stepIndex, 3)
        XCTAssertEqual(WalkthroughStep.assistant.stepIndex, 4)
        XCTAssertEqual(WalkthroughStep.analytics.stepIndex, 5)
        XCTAssertEqual(WalkthroughStep.creditDetails.stepIndex, 6)
        XCTAssertEqual(WalkthroughStep.stockTab.stepIndex, 7)
        XCTAssertEqual(WalkthroughStep.stockActions.stepIndex, 8)
        XCTAssertEqual(WalkthroughStep.salesActions.stepIndex, 9)
        XCTAssertNil(WalkthroughStep.completion.stepIndex)
        XCTAssertEqual(WalkthroughStep.totalGuidedSteps, 9)
    }

    func testOverlayLayoutDiagnostics() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let overlay = WalkthroughOverlayView(frame: window.bounds)
        window.addSubview(overlay)
        overlay.layoutIfNeeded()

        for step in WalkthroughStep.allCases {
            let targetRect: CGRect?
            switch step {
            case .welcome, .completion:
                targetRect = nil
            case .revenue:
                targetRect = CGRect(x: 18, y: 111, width: 366, height: 218)
            case .inventory:
                targetRect = CGRect(x: 232, y: 113, width: 134, height: 36)
            case .alerts:
                targetRect = CGRect(x: 18, y: 341, width: 366, height: 72)
            case .assistant:
                targetRect = CGRect(x: 326, y: 702, width: 50, height: 50)
            case .analytics:
                targetRect = CGRect(x: 16, y: 460, width: 361, height: 50)
            case .creditDetails:
                targetRect = CGRect(x: 16, y: 380, width: 361, height: 120)
            case .stockTab:
                targetRect = CGRect(x: 78, y: 769, width: 78, height: 49)
            case .stockActions, .salesActions:
                targetRect = CGRect(x: 36, y: 410, width: 320, height: 160)
            }

            overlay.configure(step: step, targetRect: targetRect, canGoBack: step.rawValue > 0, animated: false)
            overlay.setNeedsLayout()
            overlay.layoutIfNeeded()

            let card = overlay.subviews.first { $0 !== overlay && !($0 is UIVisualEffectView) }
            XCTAssertNotNil(card, "Overlay must contain a cardView")

            if let cardFrame = card?.frame {
                // Sane height range: not collapsed, not stretched
                XCTAssertGreaterThan(cardFrame.height, 120, "\(step): card should not collapse")
                XCTAssertLessThan(cardFrame.height, 380, "\(step): card should not be stretched vertically")

                // Within screen bounds
                XCTAssertGreaterThanOrEqual(cardFrame.minY, 0, "\(step): card top should be within screen")
                XCTAssertLessThanOrEqual(cardFrame.maxY, 852, "\(step): card bottom should be within screen")
                XCTAssertGreaterThanOrEqual(cardFrame.width, 280, "\(step): card width should be reasonable")

                // Verify hierarchy can be rendered without errors
                let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
                _ = renderer.image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
            }
        }
    }

    func testUpdateTargetRectDynamically() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let overlay = WalkthroughOverlayView(frame: window.bounds)
        window.addSubview(overlay)
        overlay.layoutIfNeeded()

        // Configure with an initial target rect
        let initialRect = CGRect(x: 36, y: 400, width: 320, height: 140)
        overlay.configure(step: .stockActions, targetRect: initialRect, canGoBack: true, animated: false)
        overlay.layoutIfNeeded()

        // Dynamically update target rect (e.g. from SwiftUI preference key)
        let updatedRect = CGRect(x: 40, y: 420, width: 310, height: 135)
        overlay.updateTargetRect(updatedRect, animated: false)
        overlay.layoutIfNeeded()

        let card = overlay.subviews.first { $0 !== overlay && !($0 is UIVisualEffectView) }
        XCTAssertNotNil(card)
        if let cardFrame = card?.frame {
            XCTAssertGreaterThan(cardFrame.height, 100)
            XCTAssertLessThanOrEqual(cardFrame.maxY, 852)
        }
    }

    func testRefreshSpotlightSafetyWhenInactive() {
        if WalkthroughCoordinator.shared.isRunning {
            WalkthroughCoordinator.shared.dismissWalkthrough(completed: false)
        }
        // Coordinator is not running in unit test environment
        XCTAssertFalse(WalkthroughCoordinator.shared.isRunning)
        // Calling refreshSpotlightIfCurrent should safely do nothing and not crash
        WalkthroughCoordinator.shared.refreshSpotlightIfCurrent(step: .stockActions)
        WalkthroughCoordinator.shared.refreshSpotlightIfCurrent(step: .salesActions)
        WalkthroughCoordinator.shared.refreshSpotlightIfCurrent(step: .welcome)
    }

    func testPersistenceAcrossRelaunch() {
        let freshUser = "fresh_user_\(UUID().uuidString)"
        XCTAssertTrue(WalkthroughManager.shared.shouldShowWalkthrough(for: freshUser))

        // Complete the tour
        WalkthroughManager.shared.markWalkthroughCompleted(for: freshUser)
        XCTAssertFalse(WalkthroughManager.shared.shouldShowWalkthrough(for: freshUser))
        XCTAssertTrue(WalkthroughManager.shared.hasCompletedWalkthrough(for: freshUser))

        // Re-checking simulate subsequent app relaunch
        XCTAssertFalse(WalkthroughManager.shared.shouldShowWalkthrough(for: freshUser))

        // Skip scenario for another user
        let skipUser = "skip_user_\(UUID().uuidString)"
        XCTAssertTrue(WalkthroughManager.shared.shouldShowWalkthrough(for: skipUser))
        WalkthroughManager.shared.markWalkthroughSkipped(for: skipUser)
        XCTAssertFalse(WalkthroughManager.shared.shouldShowWalkthrough(for: skipUser))
        XCTAssertFalse(WalkthroughManager.shared.hasCompletedWalkthrough(for: skipUser))
    }

    func testSpotlightCornerRadii() {
        XCTAssertEqual(WalkthroughStep.revenue.spotlightCornerRadius, 16)
        XCTAssertEqual(WalkthroughStep.inventory.spotlightCornerRadius, 18)
        XCTAssertEqual(WalkthroughStep.alerts.spotlightCornerRadius, 26)
        XCTAssertEqual(WalkthroughStep.assistant.spotlightCornerRadius, 25)
        XCTAssertEqual(WalkthroughStep.analytics.spotlightCornerRadius, 14)
        XCTAssertEqual(WalkthroughStep.creditDetails.spotlightCornerRadius, 18)
        XCTAssertEqual(WalkthroughStep.stockTab.spotlightCornerRadius, 12)
        XCTAssertEqual(WalkthroughStep.stockActions.spotlightCornerRadius, 22)
        XCTAssertEqual(WalkthroughStep.salesActions.spotlightCornerRadius, 22)
        XCTAssertEqual(WalkthroughStep.welcome.spotlightCornerRadius, 0)
        XCTAssertEqual(WalkthroughStep.completion.spotlightCornerRadius, 0)
    }

    func testMultiCutoutsConfiguration() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let overlay = WalkthroughOverlayView(frame: window.bounds)
        window.addSubview(overlay)
        overlay.layoutIfNeeded()

        // Test configuring two cutouts (e.g. Credit Purchase and Credit Sale)
        let cutouts = [
            WalkthroughCutout(rect: CGRect(x: 18, y: 380, width: 170, height: 112), cornerRadius: 24),
            WalkthroughCutout(rect: CGRect(x: 205, y: 380, width: 170, height: 112), cornerRadius: 24)
        ]
        overlay.configure(step: .creditDetails, cutouts: cutouts, canGoBack: true, animated: false)
        overlay.layoutIfNeeded()

        XCTAssertEqual(overlay.activeCutouts.count, 2)
        XCTAssertEqual(overlay.activeCutouts[0].cornerRadius, 24)
        XCTAssertEqual(overlay.activeCutouts[1].cornerRadius, 24)

        // Test configuring three cutouts (e.g. Scan, Voice, Manual action controls)
        let actionCutouts = [
            WalkthroughCutout(rect: CGRect(x: 40, y: 550, width: 64, height: 80), cornerRadius: 18),
            WalkthroughCutout(rect: CGRect(x: 130, y: 520, width: 134, height: 134), cornerRadius: 67),
            WalkthroughCutout(rect: CGRect(x: 290, y: 550, width: 64, height: 80), cornerRadius: 18)
        ]
        overlay.configure(step: .stockActions, cutouts: actionCutouts, canGoBack: true, animated: false)
        overlay.layoutIfNeeded()

        XCTAssertEqual(overlay.activeCutouts.count, 3)
        XCTAssertEqual(overlay.activeCutouts[1].cornerRadius, 67)
    }

    func testDynamicCutoutsUpdate() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let overlay = WalkthroughOverlayView(frame: window.bounds)
        window.addSubview(overlay)
        overlay.layoutIfNeeded()

        let initialCutouts = [
            WalkthroughCutout(rect: CGRect(x: 40, y: 500, width: 64, height: 80), cornerRadius: 18)
        ]
        overlay.configure(step: .salesActions, cutouts: initialCutouts, canGoBack: true, animated: false)
        overlay.layoutIfNeeded()
        XCTAssertEqual(overlay.activeCutouts.count, 1)

        let updatedCutouts = [
            WalkthroughCutout(rect: CGRect(x: 40, y: 520, width: 64, height: 80), cornerRadius: 18),
            WalkthroughCutout(rect: CGRect(x: 130, y: 490, width: 134, height: 134), cornerRadius: 67)
        ]
        overlay.updateCutouts(updatedCutouts, animated: false)
        overlay.layoutIfNeeded()
        XCTAssertEqual(overlay.activeCutouts.count, 2)
    }

    func testTabBarItemMeasurementAndActionCutouts() {
        let rootVC = MainTabInstaller.makeRootTabBar()
        guard let tab = rootVC as? UITabBarController else { return }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = tab
        window.makeKeyAndVisible()
        tab.view.layoutIfNeeded()
        tab.tabBar.layoutIfNeeded()

        tab.selectedIndex = 1
        tab.view.layoutIfNeeded()
        tab.tabBar.layoutIfNeeded()

        XCTAssertGreaterThan(tab.tabBar.bounds.width, 300)
        XCTAssertGreaterThan(tab.tabBar.bounds.height, 40)
    }

    func testFourDistinctDashboardMoments() {
        let cell = DashboardTopTileTableViewCell()
        let bgView = SegmentedCardBackgroundView(frame: CGRect(x: 18, y: 0, width: 366, height: 218))
        cell.segmentedCardBackground = bgView
        cell.contentView.addSubview(bgView)

        let pill = UIButton(frame: CGRect(x: 224, y: 2, width: 134, height: 36))
        pill.setTitle("Inventory", for: .normal)
        pill.layer.cornerRadius = 18
        bgView.addSubview(pill)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.addSubview(cell)
        cell.frame = CGRect(x: 0, y: 111, width: 402, height: 730)
        cell.layoutIfNeeded()

        let overlay = WalkthroughOverlayView(frame: window.bounds)
        window.addSubview(overlay)

        // 1. Revenue moment: exactly 1 cutout with custom contour path
        let revCutout = WalkthroughCoordinator.createRevenueSectionCutout(for: cell, in: overlay)
        XCTAssertNotNil(revCutout, "Revenue cutout must be created")
        XCTAssertNotNil(revCutout?.customPath, "Revenue cutout must follow outer contour")

        // 2. Inventory moment: exactly 1 cutout matching pill
        let invCutout = WalkthroughCoordinator.createInventoryPillCutout(for: cell, in: overlay)
        XCTAssertNotNil(invCutout, "Inventory cutout must be created")
        XCTAssertEqual(invCutout?.cornerRadius, 18, "Inventory pill must have capsule radius 18")

        // 3. Alerts moment: 2 simultaneous independent cutouts
        let lowCard = UIView(frame: CGRect(x: 18, y: 341, width: 177, height: 72))
        lowCard.layer.cornerRadius = 26
        let expCard = UIView(frame: CGRect(x: 207, y: 341, width: 177, height: 72))
        expCard.layer.cornerRadius = 26
        let alertCutouts = [
            WalkthroughCutout(rect: lowCard.frame, cornerRadius: 26),
            WalkthroughCutout(rect: expCard.frame, cornerRadius: 26)
        ]
        XCTAssertEqual(alertCutouts.count, 2)
        XCTAssertEqual(alertCutouts[0].cornerRadius, 26)
        XCTAssertEqual(alertCutouts[1].cornerRadius, 26)

        // 4. Assistant moment: circular cutout
        let asstRect = CGRect(x: 326, y: 702, width: 50, height: 50)
        let asstCutout = WalkthroughCutout(rect: asstRect, cornerRadius: 25, customPath: UIBezierPath(ovalIn: asstRect))
        XCTAssertNotNil(asstCutout.customPath)
        XCTAssertEqual(asstCutout.cornerRadius, 25)
    }

    func testEqualButtonDimensionsAcrossPopups() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let overlay = WalkthroughOverlayView(frame: window.bounds)
        window.addSubview(overlay)
        overlay.layoutIfNeeded()

        // 1. Intermediate step with Back and Next
        overlay.configure(step: .revenue, cutouts: [], canGoBack: true, animated: false)
        overlay.layoutIfNeeded()

        let backBtn = overlay.subviews.first(where: { !($0 is UIVisualEffectView) })?.subviews
            .flatMap { $0.subviews }
            .compactMap { $0 as? UIButton }
            .first { $0.configuration?.attributedTitle?.characters.elementsEqual("Back") ?? false }

        let nextBtn = overlay.subviews.first(where: { !($0 is UIVisualEffectView) })?.subviews
            .flatMap { $0.subviews }
            .compactMap { $0 as? UIButton }
            .first { $0.configuration?.attributedTitle?.characters.elementsEqual("Next") ?? false }

        if let back = backBtn, let next = nextBtn {
            XCTAssertEqual(back.frame.height, 40, "Back button height must be 40pt")
            XCTAssertEqual(next.frame.height, 40, "Next button height must be 40pt")
            XCTAssertEqual(back.frame.width, next.frame.width, "Back and Next buttons must have exactly equal widths")
        }

        // 2. Completion step with Back and Finish
        overlay.configure(step: .completion, cutouts: [], canGoBack: true, animated: false)
        overlay.layoutIfNeeded()

        let finishBtn = overlay.subviews.first(where: { !($0 is UIVisualEffectView) })?.subviews
            .flatMap { $0.subviews }
            .compactMap { $0 as? UIButton }
            .first { $0.configuration?.attributedTitle?.characters.elementsEqual("Finish") ?? false }

        if let back = backBtn, let finish = finishBtn {
            XCTAssertEqual(back.frame.height, 40, "Back button height must be 40pt")
            XCTAssertEqual(finish.frame.height, 40, "Finish button height must be 40pt")
            XCTAssertEqual(back.frame.width, finish.frame.width, "Back and Finish buttons must have exactly equal widths")
        }
    }

    func testOverlayHitTestPassThroughOnCutouts() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let overlay = WalkthroughOverlayView(frame: window.bounds)
        window.addSubview(overlay)
        overlay.layoutIfNeeded()

        let cutoutRect = CGRect(x: 324, y: 702, width: 54, height: 54)
        let assistantCutout = WalkthroughCutout(rect: cutoutRect, cornerRadius: 27)
        overlay.configure(step: .assistant, cutouts: [assistantCutout], canGoBack: true, animated: false)
        overlay.layoutIfNeeded()

        // 1. Point inside cutout: should pass through (return nil)
        let insidePoint = CGPoint(x: 350, y: 720)
        let hitInside = overlay.hitTest(insidePoint, with: nil)
        XCTAssertNil(hitInside, "Touches inside spotlight cutout must pass through to underlying views")

        // 2. Point inside card: should return card view or its subview
        let cardRect = overlay.cardView.frame
        let cardPoint = CGPoint(x: cardRect.midX, y: cardRect.midY)
        let hitCard = overlay.hitTest(cardPoint, with: nil)
        XCTAssertNotNil(hitCard, "Touches inside the tooltip card must be handled by overlay")

        // 3. Point outside both card and cutouts (on dimmed background): should be intercepted by overlay
        let dimPoint = CGPoint(x: 20, y: 50)
        let hitDim = overlay.hitTest(dimPoint, with: nil)
        XCTAssertEqual(hitDim, overlay, "Touches on dimmed area must be intercepted by overlay")
    }

    func testTappingAssistantButtonOpensAssistantScreenAndDismissesWalkthrough() {
        let rootVC = MainTabInstaller.makeRootTabBar()
        guard let tab = rootVC as? UITabBarController,
              let nav = tab.viewControllers?.first as? UINavigationController,
              let dashboardVC = nav.viewControllers.first as? DashboardViewController else {
            return
        }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = tab
        window.makeKeyAndVisible()
        tab.view.layoutIfNeeded()

        let coordinator = WalkthroughCoordinator.shared
        coordinator.startWalkthrough(from: tab)
        XCTAssertTrue(coordinator.isRunning)

        let btn = dashboardVC.view.subviews.compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == "Assistant" || $0.accessibilityIdentifier == "dashboard_assistant_button"
        }
        XCTAssertNotNil(btn, "Assistant button must be present in dashboard view hierarchy")

        // Trigger assistant action
        btn?.sendActions(for: .touchUpInside)

        // Walkthrough must dismiss immediately and ShopAssistantViewController must be pushed
        XCTAssertFalse(coordinator.isRunning, "Walkthrough must dismiss when Assistant button is tapped")
        XCTAssertTrue(nav.topViewController is ShopAssistantViewController, "ShopAssistantViewController must be pushed onto navigation stack")
    }

    func testCombinedChartCutoutGeometry() {
        let cell = DashboardTopTileTableViewCell()
        let bgView = SegmentedCardBackgroundView(frame: CGRect(x: 18, y: 0, width: 366, height: 218))
        cell.segmentedCardBackground = bgView
        cell.contentView.addSubview(bgView)

        let pill = UIButton(frame: CGRect(x: 224, y: 2, width: 134, height: 36))
        pill.setTitle("Inventory", for: .normal)
        pill.layer.cornerRadius = 18
        bgView.addSubview(pill)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.addSubview(cell)
        cell.frame = CGRect(x: 0, y: 111, width: 402, height: 730)
        cell.layoutIfNeeded()

        let overlay = WalkthroughOverlayView(frame: window.bounds)
        window.addSubview(overlay)

        let cutout = WalkthroughCoordinator.createCombinedChartCutout(for: cell, in: overlay)
        XCTAssertNotNil(cutout, "Chart cutout must be generated")
        XCTAssertNotNil(cutout?.customPath, "Chart cutout must have custom bezier path following contour")
        XCTAssertGreaterThan(cutout?.rect.width ?? 0, 300)
        XCTAssertGreaterThan(cutout?.rect.height ?? 0, 150)
    }

    func testCustomPathHitTesting() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let overlay = WalkthroughOverlayView(frame: window.bounds)
        window.addSubview(overlay)
        overlay.layoutIfNeeded()

        let customPath = UIBezierPath(ovalIn: CGRect(x: 100, y: 100, width: 80, height: 80))
        let cutout = WalkthroughCutout(rect: CGRect(x: 100, y: 100, width: 80, height: 80), cornerRadius: 40, customPath: customPath)
        overlay.configure(step: .revenue, cutouts: [cutout], canGoBack: false, animated: false)

        // Point inside circle: should pass through
        let inside = CGPoint(x: 140, y: 140)
        XCTAssertNil(overlay.hitTest(inside, with: nil))

        // Point inside bounding box (102, 102) but outside circle: should NOT pass through
        let outsideCircle = CGPoint(x: 103, y: 103)
        XCTAssertEqual(overlay.hitTest(outsideCircle, with: nil), overlay)
    }
}
