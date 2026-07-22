import AppKit
import XCTest
@testable import NotionPiP

@MainActor
final class AppWindowPresenterTests: XCTestCase {
    func testPresenterShowsAndHidesItsOwnedWindow() {
        let window = FakeAppWindow()
        let presenter = AppWindowPresenter(window: window)

        presenter.show()
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.presentCount, 1)

        presenter.show()
        XCTAssertEqual(window.presentCount, 2)

        presenter.hide()
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.orderOutCount, 1)
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
