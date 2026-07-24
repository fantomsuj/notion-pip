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
    func testLazyPresenterDefersConstructionUntilFirstShowAndReusesPresenter() {
        let window = FakeAppWindow()
        var factoryCount = 0
        let presenter = LazyAppWindowPresenter {
            factoryCount += 1
            return AppWindowPresenter(window: window)
        }

        XCTAssertEqual(factoryCount, 0)

        presenter.hide()
        XCTAssertEqual(factoryCount, 0)
        XCTAssertEqual(window.orderOutCount, 0)

        presenter.show()
        XCTAssertEqual(factoryCount, 1)
        XCTAssertEqual(window.presentCount, 1)

        presenter.show()
        XCTAssertEqual(factoryCount, 1)
        XCTAssertEqual(window.presentCount, 2)

        presenter.hide()
        XCTAssertEqual(factoryCount, 1)
        XCTAssertEqual(window.orderOutCount, 1)
    }

    func testLazyPresenterMeasuresFirstPresentationAcrossConstructionAndForwardedShow() {
        let signposter = PerformanceSignposterSpy()
        let window = FakeAppWindow()
        var factoryCount = 0
        var forwardedShowCount = 0
        window.onPresentAsKey = {
            forwardedShowCount += 1
            guard forwardedShowCount == 1 else { return }
            XCTAssertEqual(signposter.beginCalls, [.firstQuickCapturePresentation])
            XCTAssertTrue(signposter.endCalls.isEmpty)
        }
        let presenter = LazyAppWindowPresenter(
            makePresenter: {
                XCTAssertEqual(signposter.beginCalls, [.firstQuickCapturePresentation])
                XCTAssertTrue(signposter.endCalls.isEmpty)
                factoryCount += 1
                return AppWindowPresenter(window: window)
            },
            performanceSignposter: signposter,
            firstPresentationOperation: .firstQuickCapturePresentation
        )

        XCTAssertTrue(signposter.beginCalls.isEmpty)
        XCTAssertTrue(signposter.endCalls.isEmpty)

        presenter.show()

        XCTAssertEqual(factoryCount, 1)
        XCTAssertEqual(window.presentCount, 1)
        XCTAssertEqual(signposter.beginCalls, [.firstQuickCapturePresentation])
        XCTAssertEqual(signposter.endCalls.count, 1)
        XCTAssertNotNil(signposter.endCalls.first?.token)
        XCTAssertEqual(signposter.endCalls.first?.outcome, .success)

        presenter.show()

        XCTAssertEqual(factoryCount, 1)
        XCTAssertEqual(window.presentCount, 2)
        XCTAssertEqual(signposter.beginCalls, [.firstQuickCapturePresentation])
        XCTAssertEqual(signposter.endCalls.count, 1)
    }

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

    func presentAsKey() {
        isVisible = true
        presentCount += 1
        onPresentAsKey?()
    }

    func orderOut() {
        isVisible = false
        orderOutCount += 1
    }
}
