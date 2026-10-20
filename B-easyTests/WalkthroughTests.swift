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
}
