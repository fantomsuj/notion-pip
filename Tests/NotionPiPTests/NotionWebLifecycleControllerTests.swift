import Combine
import XCTest
@testable import NotionPiP

@MainActor
final class NotionWebLifecycleControllerTests: XCTestCase {
    func testHiddenHostedViewSuspendsForWarmRetentionAndThenRequestsEviction() {
        var interval: TimeInterval?
        var scheduledAction: (@MainActor () -> Void)?
        var evictionCount = 0
        let controller = NotionWebLifecycleController(
            initialState: .active,
            scheduleEviction: { scheduledInterval, action in
                interval = scheduledInterval
                scheduledAction = action
                return AnyCancellable {}
            }
        )
        controller.onEvictionRequested = { evictionCount += 1 }

        controller.panelDidHide()
        XCTAssertTrue(controller.suspend(hasWebView: true))

        XCTAssertEqual(controller.visibility, .hidden)
        XCTAssertEqual(controller.state, .suspended)
        XCTAssertEqual(interval, 60)
        XCTAssertFalse(controller.shouldHostWebView(hasWebView: true))

        scheduledAction?()

        XCTAssertEqual(evictionCount, 1)
    }

    func testShowingDuringWarmRetentionResumesPreviousNavigationState() {
        var scheduledAction: (@MainActor () -> Void)?
        var evictionCount = 0
        let controller = NotionWebLifecycleController(
            initialState: .loading,
            scheduleEviction: { _, action in
                scheduledAction = action
                return AnyCancellable {}
            }
        )
        controller.onEvictionRequested = { evictionCount += 1 }
        controller.panelDidHide()
        controller.suspend(hasWebView: true)
        controller.publishNavigationState(.active)

        let command = controller.panelDidShow(hasWebView: true, hasActivePage: true)
        scheduledAction?()

        XCTAssertEqual(command, .restorePreviousState(.active))
        XCTAssertEqual(controller.state, .active)
        XCTAssertTrue(controller.shouldHostWebView(hasWebView: true))
        XCTAssertEqual(evictionCount, 0)
    }

    func testMemoryPressureEvictionRespectsVisibilityAndProtection() {
        var evictionCount = 0
        let controller = NotionWebLifecycleController(
            initialState: .active,
            scheduleEviction: { _, _ in AnyCancellable {} }
        )
        controller.onEvictionRequested = { evictionCount += 1 }
        controller.panelDidHide()
        controller.suspend(hasWebView: true)
        controller.setEvictionProtected(true)

        XCTAssertFalse(controller.requestEvictionIfEligible())
        controller.setEvictionProtected(false)
        XCTAssertTrue(controller.requestEvictionIfEligible())
        XCTAssertEqual(evictionCount, 1)
    }

    func testShowingWithoutRetainedViewRequestsActivePageLoad() {
        let controller = NotionWebLifecycleController(
            initialState: .suspended,
            scheduleEviction: { _, _ in AnyCancellable {} }
        )
        controller.panelDidHide()

        XCTAssertEqual(
            controller.panelDidShow(hasWebView: false, hasActivePage: true),
            .loadActivePage
        )
    }
}
