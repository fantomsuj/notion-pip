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

    func testLazyPresenterHasNoTerminationParticipantUntilWindowIsLive() async throws {
        let window = FakeAppWindow()
        var terminationCallCount = 0
        let presenter = LazyAppWindowPresenter {
            AppWindowPresenter(
                window: window,
                terminationHandler: {
                    terminationCallCount += 1
                    return true
                }
            )
        }

        XCTAssertNil(presenter.terminationParticipant)

        presenter.show()
        let participant = try XCTUnwrap(presenter.terminationParticipant)
        let firstResult = await participant.prepareForTermination()
        XCTAssertTrue(firstResult)
        XCTAssertEqual(terminationCallCount, 1)

        presenter.hide()
        let hiddenResult = await participant.prepareForTermination()
        XCTAssertTrue(hiddenResult)
        XCTAssertEqual(terminationCallCount, 1)
    }

    func testSuccessfulCloseReleaseDisposesHiddenPresenterAfterScheduledDelay() {
        var scheduledRelease: (() -> Void)?
        var scheduledDelay: TimeInterval?
        var cancellationCount = 0
        var factoryCount = 0
        let resource = ResourceDisposalSpy()
        let presenter = LazyAppWindowPresenter(
            makePresenter: {
                factoryCount += 1
                return resource
            },
            releaseScheduler: { delay, action in
                scheduledDelay = delay
                scheduledRelease = action
                return { cancellationCount += 1 }
            }
        )

        presenter.show()
        presenter.hide()
        presenter.scheduleReleaseAfterSuccessfulClose()

        XCTAssertEqual(factoryCount, 1)
        XCTAssertEqual(scheduledDelay, 60)
        XCTAssertEqual(cancellationCount, 0)
        XCTAssertEqual(resource.disposeCount, 0)

        scheduledRelease?()

        XCTAssertEqual(resource.disposeCount, 1)
        XCTAssertNil(presenter.terminationParticipant)
    }

    func testReopeningBeforeReleaseExpiryCancelsPendingRelease() {
        var scheduledRelease: (() -> Void)?
        var cancellationCount = 0
        let resource = ResourceDisposalSpy()
        let presenter = LazyAppWindowPresenter(
            makePresenter: { resource },
            releaseScheduler: { _, action in
                scheduledRelease = action
                return { cancellationCount += 1 }
            }
        )

        presenter.show()
        presenter.hide()
        presenter.scheduleReleaseAfterSuccessfulClose()
        presenter.show()
        scheduledRelease?()

        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(resource.showCount, 2)
        XCTAssertEqual(resource.disposeCount, 0)
    }

    func testReopeningAfterReleaseExpiryConstructsANewPresenter() {
        var scheduledRelease: (() -> Void)?
        var createdResources: [ResourceDisposalSpy] = []
        let presenter = LazyAppWindowPresenter(
            makePresenter: {
                let resource = ResourceDisposalSpy()
                createdResources.append(resource)
                return resource
            },
            releaseScheduler: { _, action in
                scheduledRelease = action
                return {}
            }
        )

        presenter.show()
        presenter.hide()
        presenter.scheduleReleaseAfterSuccessfulClose()
        scheduledRelease?()
        presenter.show()

        XCTAssertEqual(createdResources.count, 2)
        XCTAssertEqual(createdResources[0].disposeCount, 1)
        XCTAssertEqual(createdResources[1].showCount, 1)
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
private final class ResourceDisposalSpy: AppWindowPresenting, AppWindowResourceDisposing {
    private(set) var showCount = 0
    private(set) var disposeCount = 0

    func show() { showCount += 1 }
    func hide() {}
    func disposeResources() { disposeCount += 1 }
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
