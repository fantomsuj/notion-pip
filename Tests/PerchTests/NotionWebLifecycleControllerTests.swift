@testable import Perch
import XCTest

@MainActor
final class NotionWebLifecycleControllerTests: XCTestCase {
    func testHiddenHostedViewSuspendsAndRemainsWarmUntilEvictionIsRequested() {
        var evictionCount = 0
        let controller = NotionWebLifecycleController(initialState: .active)
        controller.onEvictionRequested = { evictionCount += 1 }

        controller.panelDidHide()
        XCTAssertTrue(controller.suspend(hasWebView: true))

        XCTAssertEqual(controller.visibility, .hidden)
        XCTAssertEqual(controller.state, .suspended)
        XCTAssertFalse(controller.shouldHostWebView(hasWebView: true))
        XCTAssertEqual(evictionCount, 0)

        XCTAssertTrue(controller.requestEvictionIfEligible())

        XCTAssertEqual(evictionCount, 1)
    }

    func testShowingDuringWarmRetentionResumesPreviousNavigationState() {
        var evictionCount = 0
        let controller = NotionWebLifecycleController(initialState: .loading)
        controller.onEvictionRequested = { evictionCount += 1 }
        controller.panelDidHide()
        controller.suspend(hasWebView: true)
        controller.publishNavigationState(.active)

        let command = controller.panelDidShow(hasWebView: true, hasActivePage: true)

        XCTAssertEqual(command, .restorePreviousState(.active))
        XCTAssertEqual(controller.state, .active)
        XCTAssertTrue(controller.shouldHostWebView(hasWebView: true))
        XCTAssertEqual(evictionCount, 0)
    }

    func testMemoryPressureEvictionRespectsVisibilityAndProtection() {
        var evictionCount = 0
        let controller = NotionWebLifecycleController(initialState: .active)
        controller.onEvictionRequested = { evictionCount += 1 }
        controller.panelDidHide()
        controller.suspend(hasWebView: true)
        controller.setEvictionProtected(true)

        XCTAssertFalse(controller.requestEvictionIfEligible())
        XCTAssertTrue(controller.requestEvictionIfEligible(ignoringProtection: true))
        XCTAssertEqual(evictionCount, 1)

        evictionCount = 0
        controller.setEvictionProtected(false)
        XCTAssertTrue(controller.requestEvictionIfEligible())
        XCTAssertEqual(evictionCount, 1)
    }

    func testShowingWithoutRetainedViewRequestsActivePageLoad() {
        let controller = NotionWebLifecycleController(initialState: .suspended)
        controller.panelDidHide()

        XCTAssertEqual(
            controller.panelDidShow(hasWebView: false, hasActivePage: true),
            .loadActivePage
        )
    }
}
