import XCTest
@testable import B_easy

@MainActor
final class WalkthroughTests: XCTestCase {

    private let testUserId1 = "test_user_alpha_\(UUID().uuidString)"
    private let testUserId2 = "test_user_beta_\(UUID().uuidString)"

    override func tearDown() {
        super.tearDown()
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
        XCTAssertEqual(steps.count, 8)

        XCTAssertEqual(steps[0], .welcome)
        XCTAssertEqual(steps[1], .dashboardOverview)
        XCTAssertEqual(steps[2], .analytics)
        XCTAssertEqual(steps[3], .creditDetails)
        XCTAssertEqual(steps[4], .stockTab)
        XCTAssertEqual(steps[5], .stockActions)
        XCTAssertEqual(steps[6], .salesActions)
        XCTAssertEqual(steps[7], .completion)

        XCTAssertEqual(steps[0].title, "Welcome to B Easy!")
        XCTAssertEqual(steps[1].title, "Dashboard Overview")
        XCTAssertEqual(steps[2].title, "Analytics & Reports")
        XCTAssertEqual(steps[3].title, "Credit Management")
        XCTAssertEqual(steps[4].title, "Stock Management")
        XCTAssertEqual(steps[5].title, "Adding Stock")
        XCTAssertEqual(steps[6].title, "Recording Sales")
        XCTAssertEqual(steps[7].title, "You're all set!")
    }

    func testWalkthroughStepModalFlags() {
        XCTAssertTrue(WalkthroughStep.welcome.isModal)
        XCTAssertTrue(WalkthroughStep.completion.isModal)

        XCTAssertFalse(WalkthroughStep.dashboardOverview.isModal)
        XCTAssertFalse(WalkthroughStep.analytics.isModal)
        XCTAssertFalse(WalkthroughStep.creditDetails.isModal)
        XCTAssertFalse(WalkthroughStep.stockTab.isModal)
        XCTAssertFalse(WalkthroughStep.stockActions.isModal)
        XCTAssertFalse(WalkthroughStep.salesActions.isModal)
    }

    func testGuidedStepIndices() {
        XCTAssertNil(WalkthroughStep.welcome.stepIndex)
        XCTAssertEqual(WalkthroughStep.dashboardOverview.stepIndex, 1)
        XCTAssertEqual(WalkthroughStep.analytics.stepIndex, 2)
        XCTAssertEqual(WalkthroughStep.creditDetails.stepIndex, 3)
        XCTAssertEqual(WalkthroughStep.stockTab.stepIndex, 4)
        XCTAssertEqual(WalkthroughStep.stockActions.stepIndex, 5)
        XCTAssertEqual(WalkthroughStep.salesActions.stepIndex, 6)
        XCTAssertNil(WalkthroughStep.completion.stepIndex)
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
            case .dashboardOverview:
                targetRect = CGRect(x: 16, y: 120, width: 361, height: 280)
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
        XCTAssertEqual(WalkthroughStep.dashboardOverview.spotlightCornerRadius, 16)
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
}
