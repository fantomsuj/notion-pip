import AppKit
import XCTest
@testable import NotionPiP

@MainActor
final class AppWindowPresenterTests: XCTestCase {
    func testPresenterMeasuresOnlyFirstPresentationWhileShowingWindowEveryTime() {
        let window = FakeAppWindow()
        let signposter = PerformanceSignposterSpy()
        let presenter = AppWindowPresenter(
            window: window,
            performanceSignposter: signposter,
            firstPresentationOperation: .firstQuickCapturePresentation
        )

        presenter.show()
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.presentCount, 1)

        presenter.show()
        XCTAssertEqual(window.presentCount, 2)

        presenter.hide()
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.orderOutCount, 1)
        XCTAssertEqual(signposter.beginCalls, [.firstQuickCapturePresentation])
        XCTAssertEqual(signposter.endCalls.count, 1)
        XCTAssertNotNil(signposter.endCalls.first?.token)
        XCTAssertEqual(signposter.endCalls.first?.outcome, .success)
    }
}

@MainActor
private final class FakeAppWindow: AppWindow {
    private(set) var isVisible = false
    private(set) var presentCount = 0
    private(set) var orderOutCount = 0

    func presentAsKey() {
        isVisible = true
        presentCount += 1
    }

    func orderOut() {
        isVisible = false
        orderOutCount += 1
    }
}
