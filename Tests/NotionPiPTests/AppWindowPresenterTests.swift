import AppKit
import XCTest
@testable import NotionPiP

@MainActor
final class AppWindowPresenterTests: XCTestCase {
    func testSettingsWindowPresenterForwardsEveryRequestToTheRetainedWindowPresenter() {
        let windowPresenter = FakeAppWindowPresenter()
        let presenter = SettingsWindowPresenter(windowPresenter: windowPresenter)

        presenter.show()
        presenter.show()

        XCTAssertEqual(windowPresenter.showCount, 2)
        XCTAssertEqual(windowPresenter.hideCount, 0)
    }

    func testSettingsWindowPresenterDefersConstructionUntilFirstShow() {
        let windowPresenter = FakeAppWindowPresenter()
        var factoryCount = 0
        let presenter = SettingsWindowPresenter {
            factoryCount += 1
            return windowPresenter
        }

        XCTAssertEqual(factoryCount, 0)
        presenter.show()
        presenter.show()

        XCTAssertEqual(factoryCount, 1)
        XCTAssertEqual(windowPresenter.showCount, 2)
    }

    func testSettingsWindowPresenterRecreatesWindowAfterClose() {
        var closeHandlers: [@MainActor () -> Void] = []
        var windowPresenters: [FakeAppWindowPresenter] = []
        let presenter = SettingsWindowPresenter { closeHandler in
            closeHandlers.append(closeHandler)
            let windowPresenter = FakeAppWindowPresenter()
            windowPresenters.append(windowPresenter)
            return windowPresenter
        }

        presenter.show()
        closeHandlers[0]()
        presenter.show()

        XCTAssertEqual(windowPresenters.count, 2)
        XCTAssertEqual(windowPresenters[0].showCount, 1)
        XCTAssertEqual(windowPresenters[1].showCount, 1)
    }

    func testWindowCloseRequestHidesWindowBeforeRunningCloseHandler() {
        let window = FakeAppWindow()
        var closeHandlerCallCount = 0
        let presenter = AppWindowPresenter(
            window: window,
            closeRequestHandler: {
                XCTAssertFalse(window.isVisible)
                closeHandlerCallCount += 1
            }
        )

        presenter.show()
        window.requestClose()

        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.orderOutCount, 1)
        XCTAssertEqual(closeHandlerCallCount, 1)
    }

}

@MainActor
private final class FakeAppWindowPresenter: AppWindowPresenting {
    private(set) var showCount = 0
    private(set) var hideCount = 0

    func show() { showCount += 1 }
    func hide() { hideCount += 1 }
}

@MainActor
private final class FakeAppWindow: AppWindow {
    private(set) var isVisible = false
    private(set) var presentCount = 0
    private(set) var orderOutCount = 0
    var onPresentAsKey: (() -> Void)?
    var closeRequestHandler: (@MainActor () -> Void)?

    func presentAsKey() {
        isVisible = true
        presentCount += 1
        onPresentAsKey?()
    }

    func orderOut() {
        isVisible = false
        orderOutCount += 1
    }

    func installCloseRequestHandler(_ handler: @escaping @MainActor () -> Void) {
        closeRequestHandler = handler
    }

    func requestClose() {
        closeRequestHandler?()
    }
}
