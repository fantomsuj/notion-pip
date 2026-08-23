import AppKit
import Foundation
import XCTest

@testable import Perch

@MainActor
final class PinCoordinatorTests: XCTestCase {
    private let firstPageID = "0123456789abcdef0123456789abcdef"
    private let secondPageID = "fedcba9876543210fedcba9876543210"

    func testPanelCoordinatorDeduplicatesSamePageLoadWhileForegroundingPanel() throws {
        let panel = FakePanelWindow()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: loader)
        let page = try makePage(id: firstPageID, title: "Roadmap")

        coordinator.show(page: page)
        coordinator.show(page: page)

        XCTAssertEqual(loader.activatedPages.map(\.pageID), [firstPageID])
        XCTAssertEqual(panel.presentCount, 2)
        XCTAssertEqual(coordinator.currentPage?.pageID, firstPageID)
    }

    func testPanelCoordinatorNotifiesSamePageReselectionWithoutReactivating() throws {
        let panel = FakePanelWindow()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: loader)
        let page = try makePage(id: firstPageID, title: "Roadmap")

        coordinator.show(page: page)
        coordinator.show(page: page)

        XCTAssertEqual(loader.activatedPages, [page])
        XCTAssertEqual(loader.reselectedPages, [page])
        XCTAssertEqual(panel.presentCount, 2)
    }

    func testPanelCoordinatorReloadPinnedPageForceLoadsAndPresentsCurrentPage() throws {
        let panel = FakePanelWindow()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: loader)
        let page = try makePage(id: firstPageID, title: "Roadmap")

        coordinator.show(page: page)
        coordinator.reloadPinnedPage(page)

        XCTAssertEqual(loader.reloadedPages, [page])
        XCTAssertEqual(loader.lifecycleEvents, [.activated, .shown, .shown, .reloaded])
        XCTAssertEqual(panel.presentCount, 2)
        XCTAssertEqual(coordinator.currentPage, page)
    }

    func testPanelCoordinatorLoadsSamePageIDWhenCanonicalRouteChanges() throws {
        let panel = FakePanelWindow()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: loader)
        let oldPage = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/Roadmap-\(firstPageID)"))
        )
        let correctedPage = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/acme/Roadmap-\(firstPageID)"))
        )

        coordinator.show(page: oldPage)
        coordinator.show(page: correctedPage)

        XCTAssertEqual(loader.activatedPages, [oldPage, correctedPage])
        XCTAssertTrue(loader.reselectedPages.isEmpty)
        XCTAssertEqual(coordinator.currentPage, correctedPage)
    }

    func testPanelCoordinatorReplacesPageInExistingPanel() throws {
        let panel = FakePanelWindow()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: loader)
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")

        coordinator.show(page: firstPage)
        coordinator.replace(page: secondPage)

        XCTAssertEqual(loader.activatedPages.map(\.pageID), [firstPageID, secondPageID])
        XCTAssertEqual(panel.presentCount, 2)
        XCTAssertEqual(coordinator.currentPage?.pageID, secondPageID)
    }

    func testPanelCoordinatorStashesWithoutReleasingItsSessionOrCurrentPage() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 300, height: 400)
        )
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let signposter = PerformanceSignposterSpy()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle,
            performanceSignposter: signposter
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")

        coordinator.show(page: page)
        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )
        coordinator.show(page: page)

        XCTAssertEqual(panel.orderOutCount, 1)
        XCTAssertEqual(panel.presentCount, 2)
        XCTAssertEqual(loader.activatedPages.map(\.pageID), [firstPageID])
        XCTAssertEqual(coordinator.currentPage?.pageID, firstPageID)
        XCTAssertEqual(signposter.beginCalls, [.firstPiPPresentation])
        XCTAssertEqual(signposter.endCalls.count, 1)
        XCTAssertNotNil(signposter.endCalls.first?.token)
        XCTAssertEqual(signposter.endCalls.first?.outcome, .success)
    }

    func testPanelShowStashAndRestoreNotifyWebLifecycle() throws {
        let panel = FakePanelWindow(frame: CGRect(x: 620, y: 100, width: 300, height: 400))
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )
        handle.restore()

        XCTAssertEqual(loader.panelShowCount, 2)
        XCTAssertEqual(loader.panelHideCount, 1)
    }

    func testEdgeHandleRestoreRequestsContextBeforePresentingPanel() throws {
        let panel = FakePanelWindow(frame: CGRect(x: 620, y: 100, width: 300, height: 400))
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())
        var revealPresentationCounts: [Int] = []
        coordinator.onWillReveal = {
            revealPresentationCounts.append(panel.presentCount)
        }

        handle.restore()

        XCTAssertEqual(revealPresentationCounts, [1])
        XCTAssertEqual(panel.presentCount, 2)
    }

    func testPanelCoordinatorStashesAndRestoresLoadedPageWithoutReloading() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 300, height: 400)
        )
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")

        coordinator.show(page: page)
        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())
        XCTAssertEqual(coordinator.presentationState, .stashed)
        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())

        XCTAssertEqual(coordinator.presentationState, .visible)
        XCTAssertEqual(loader.activatedPages.map(\.pageID), [firstPageID])
        XCTAssertEqual(coordinator.currentPage, page)
    }

    func testPanelCoordinatorCannotStashOrRestoreWithoutCurrentPage() {
        let panel = FakePanelWindow()
        let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: FakePageLoader())

        XCTAssertFalse(coordinator.stashOrRestoreCurrentPage())
        XCTAssertEqual(coordinator.presentationState, .unavailable)
        XCTAssertFalse(panel.isVisible)
    }

    func testPanelCoordinatorStashesWithoutReloadingOrChangingPanelFrame() throws {
        let originalFrame = CGRect(x: 620, y: 100, width: 300, height: 400)
        let panel = FakePanelWindow(frame: originalFrame)
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        coordinator.show(page: page)

        let stashed = coordinator.stash(
            visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
        )

        XCTAssertTrue(stashed)
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(handle.isVisible)
        XCTAssertEqual(
            handle.placements,
            [PanelStashPlacement(side: .right, frame: CGRect(x: 964, y: 252, width: 36, height: 96))]
        )
        XCTAssertEqual(panel.frame, originalFrame)
        XCTAssertEqual(loader.activatedPages, [page])
        XCTAssertEqual(coordinator.currentPage, page)
    }

    func testStashHandleRestoresSamePanelWithoutReloading() throws {
        let panel = FakePanelWindow(frame: CGRect(x: 80, y: 220, width: 400, height: 360))
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        coordinator.show(page: page)
        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )
        XCTAssertEqual(handle.entrances, [.coordinated])
        XCTAssertEqual(panel.stashTransitionPlacements, handle.placements)

        handle.restore()

        XCTAssertEqual(panel.restoreTransitionPlacements, handle.placements)
        XCTAssertEqual(handle.dismissForRestoreCount, 1)
        XCTAssertFalse(handle.isVisible)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.presentCount, 2)
        XCTAssertEqual(loader.activatedPages, [page])
        XCTAssertEqual(coordinator.currentPage, page)
    }

    func testRestashingDuringRestoreTransitionPreservesCommittedFrame() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let originalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let panel = FakePanelWindow(
            frame: originalFrame,
            defersRestorePresentation: true
        )
        let handle = FakeStashHandle()
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] },
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))

        handle.restore()
        XCTAssertNotEqual(panel.frame, originalFrame)
        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))

        XCTAssertEqual(geometryStore.load()?.frame, originalFrame)
    }

    func testImmediateRestashDuringRestoreTransitionPreservesCommittedFrame() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let originalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let panel = FakePanelWindow(
            frame: originalFrame,
            defersRestorePresentation: true
        )
        let handle = FakeStashHandle()
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] },
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))

        handle.restore()
        XCTAssertNotEqual(panel.frame, originalFrame)
        XCTAssertTrue(coordinator.stashCurrentPageImmediately())

        XCTAssertEqual(geometryStore.load()?.frame, originalFrame)
    }

    func testLateStashCompletionCannotHideRestoredPanel() throws {
        let originalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let panel = FakePanelWindow(
            frame: originalFrame,
            defersStashDismissal: true
        )
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))
        handle.restore()
        panel.completeStashDismissal()

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame, originalFrame)
    }

    func testLiveResizeDuringStashAnimationDoesNotShrinkCommittedFrame() async throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let originalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let panel = FakePanelWindow(
            frame: originalFrame,
            defersStashDismissal: true,
            usesStashTransitionFrame: true
        )
        let handle = FakeStashHandle()
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] },
            geometryStore: geometryStore
        )
        var recordedManualSizes: [CGSize] = []
        coordinator.onManualResizeCompletion = { recordedManualSizes.append($0) }
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))
        XCTAssertLessThan(panel.frame.width, originalFrame.width)
        XCTAssertLessThan(panel.frame.height, originalFrame.height)

        NotificationCenter.default.post(
            name: NSWindow.didEndLiveResizeNotification,
            object: panel
        )
        await Task.yield()

        XCTAssertTrue(recordedManualSizes.isEmpty)
        XCTAssertEqual(geometryStore.load()?.frame, originalFrame)

        panel.completeStashDismissal()
        handle.restore()

        XCTAssertEqual(panel.frame, originalFrame)
    }

    func testLiveResizeDuringRestoreAnimationDoesNotShrinkCommittedFrame() async throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let originalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let panel = FakePanelWindow(
            frame: originalFrame,
            defersRestorePresentation: true
        )
        let handle = FakeStashHandle()
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] },
            geometryStore: geometryStore
        )
        var recordedManualSizes: [CGSize] = []
        coordinator.onManualResizeCompletion = { recordedManualSizes.append($0) }
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))

        handle.restore()
        XCTAssertLessThan(panel.frame.width, originalFrame.width)
        XCTAssertLessThan(panel.frame.height, originalFrame.height)

        NotificationCenter.default.post(
            name: NSWindow.didEndLiveResizeNotification,
            object: panel
        )
        await Task.yield()

        XCTAssertTrue(recordedManualSizes.isEmpty)
        XCTAssertEqual(geometryStore.load()?.frame, originalFrame)
        XCTAssertEqual(
            geometryStore.load()?.desiredContentSize.cgSize,
            originalFrame.size
        )
    }

    func testRepeatedStashRestoreCyclesPreserveCommittedFrame() async throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let originalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let panel = FakePanelWindow(
            frame: originalFrame,
            defersStashDismissal: true,
            usesStashTransitionFrame: true
        )
        let handle = FakeStashHandle()
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] },
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        for _ in 1...5 {
            XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))
            XCTAssertLessThan(panel.frame.width, originalFrame.width)
            NotificationCenter.default.post(
                name: NSWindow.didEndLiveResizeNotification,
                object: panel
            )
            await Task.yield()
            panel.completeStashDismissal()
            handle.restore()
            NotificationCenter.default.post(
                name: NSWindow.didEndLiveResizeNotification,
                object: panel
            )
            await Task.yield()
            XCTAssertEqual(panel.frame.size, originalFrame.size)
            XCTAssertEqual(geometryStore.load()?.frame.size, originalFrame.size)
        }

        XCTAssertEqual(panel.frame, originalFrame)
    }

    func testMoveNotificationDuringStashAnimationDoesNotReplaceCommittedFrame() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let originalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let panel = FakePanelWindow(
            frame: originalFrame,
            defersStashDismissal: true,
            usesStashTransitionFrame: true
        )
        let handle = FakeStashHandle()
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] },
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))
        XCTAssertNotEqual(panel.frame, originalFrame)

        coordinator.recordPanelMove()

        XCTAssertEqual(geometryStore.load()?.frame, originalFrame)
        XCTAssertNotEqual(panel.frame.size, originalFrame.size)
    }

    func testRestoreUsesCommittedFrameEvenIfLivePanelWasLeftCompressed() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let originalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let panel = FakePanelWindow(frame: originalFrame)
        let handle = FakeStashHandle()
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] },
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))

        panel.move(
            to: PanelStashTransition.panelTargetFrame(
                from: originalFrame,
                toward: try XCTUnwrap(handle.placements.last)
            )
        )
        handle.restore()

        XCTAssertEqual(panel.frame, originalFrame)
        XCTAssertEqual(geometryStore.load()?.frame, originalFrame)
    }

    func testSameDisplayMoveDoesNotPersistTransientlyCompressedSize() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let originalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let panel = FakePanelWindow(frame: originalFrame)
        let handle = FakeStashHandle()
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] },
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        panel.move(
            to: CGRect(
                x: originalFrame.minX + 12,
                y: originalFrame.minY - 8,
                width: originalFrame.width * 0.88,
                height: originalFrame.height * 0.94
            )
        )
        coordinator.recordPanelMove()

        XCTAssertEqual(panel.frame.size, originalFrame.size)
        XCTAssertEqual(geometryStore.load()?.frame.size, originalFrame.size)
        XCTAssertEqual(panel.frame.origin, CGPoint(x: originalFrame.minX + 12, y: originalFrame.minY - 8))

        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))
        handle.restore()
        XCTAssertEqual(panel.frame.size, originalFrame.size)
    }

    func testLiveResizeStillReplacesCommittedSizeAfterMoveLock() async throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let originalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let resizedFrame = CGRect(x: 600, y: 300, width: 500, height: 600)
        let panel = FakePanelWindow(frame: originalFrame)
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { [visibleFrame] },
            geometryStore: geometryStore
        )
        let resizeRecorded = expectation(description: "Manual resize recorded")
        coordinator.onManualResizeCompletion = { contentSize in
            XCTAssertEqual(contentSize, resizedFrame.size)
            resizeRecorded.fulfill()
        }
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        panel.move(to: resizedFrame)
        NotificationCenter.default.post(
            name: NSWindow.didEndLiveResizeNotification,
            object: panel
        )
        await fulfillment(of: [resizeRecorded], timeout: 1)

        XCTAssertEqual(geometryStore.load()?.frame.size, resizedFrame.size)
    }

    func testStashRestorePreservesCommittedHorizontalFrameWhenLegacySizeConflicts() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let horizontalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let panel = FakePanelWindow(frame: horizontalFrame)
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] },
            initialPreferredContentSize: CGSize(width: 480, height: 720)
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))
        handle.restore()

        XCTAssertEqual(panel.frame, horizontalFrame)
    }

    func testStashRestorePreservesExactVerticalFrame() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let verticalFrame = CGRect(x: 936, y: 156, width: 480, height: 720)
        let panel = FakePanelWindow(frame: verticalFrame)
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))
        handle.restore()

        XCTAssertEqual(panel.frame, verticalFrame)
    }

    func testApplyingHorizontalThenStashingRestoresAppliedFrame() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let panel = FakePanelWindow(
            frame: CGRect(x: 936, y: 156, width: 480, height: 720)
        )
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertTrue(
            coordinator.applyPanelContentSize(CGSize(width: 760, height: 520))
        )
        let appliedFrame = panel.frame
        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))
        handle.restore()

        XCTAssertEqual(panel.frame, appliedFrame)
        XCTAssertEqual(panel.frame.size, CGSize(width: 760, height: 520))
    }

    func testGeometrySaveFailureDoesNotBlockRestoreAndReportsValidationFailure() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let originalFrame = CGRect(x: 656, y: 356, width: 760, height: 520)
        let panel = FakePanelWindow(frame: originalFrame)
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] },
            geometryStore: FailingPanelGeometryStore()
        )
        var failureCount = 0
        coordinator.onGeometryPersistenceFailure = { failureCount += 1 }
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))
        handle.restore()

        XCTAssertEqual(failureCount, 1)
        XCTAssertEqual(panel.frame, originalFrame)
        XCTAssertTrue(panel.isVisible)
    }

    func testShowingCurrentPageDismissesStashHandle() throws {
        let panel = FakePanelWindow(frame: CGRect(x: 80, y: 220, width: 400, height: 360))
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )

        XCTAssertTrue(coordinator.showCurrentPage())

        XCTAssertFalse(handle.isVisible)
        XCTAssertTrue(panel.isVisible)
    }

    func testShowingReplacingAndReloadingDismissStashHandle() throws {
        let panel = FakePanelWindow(frame: CGRect(x: 80, y: 220, width: 400, height: 360))
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )

        let secondPage = try makePage(id: secondPageID, title: "Notes")
        coordinator.replace(page: secondPage)

        XCTAssertFalse(handle.isVisible)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(coordinator.presentationState, .visible)

        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )
        coordinator.reloadPinnedPage(secondPage)

        XCTAssertFalse(handle.isVisible)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(coordinator.presentationState, .visible)
    }

    func testScreenChangePreservesStashEdgeAndRelativeVerticalIntent() throws {
        let originalFrame = CGRect(x: 1_600, y: 800, width: 400, height: 360)
        let panel = FakePanelWindow(frame: originalFrame)
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080)]
            )
        )

        coordinator.reclampPanelFrame(
            visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 700)]
        )

        XCTAssertEqual(panel.frame, originalFrame)
        XCTAssertEqual(handle.placements.last?.side, .left)
        XCTAssertEqual(handle.placements.last?.frame.minX, 0)
        XCTAssertEqual(handle.placements.last?.frame.minY ?? 0, 572.081_300_813, accuracy: 0.001)
        XCTAssertEqual(handle.placements.last?.frame.size, CGSize(width: 36, height: 96))
        XCTAssertTrue(handle.isVisible)
    }

    func testScreenChangeDuringStashTransitionRepositionsHandleAsStashed() throws {
        let originalScreen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let replacementScreen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 360, height: 680),
            defersStashDismissal: true,
            usesStashTransitionFrame: true
        )
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [originalScreen] }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stash(visibleFrames: [originalScreen]))
        XCTAssertTrue(panel.isVisible)

        coordinator.reclampPanelFrame(visibleFrames: [replacementScreen])

        XCTAssertEqual(handle.placements.count, 2)
        XCTAssertEqual(handle.placements.last?.frame.maxX, replacementScreen.maxX)
        XCTAssertEqual(handle.pullRevealTravels, [151.2, 151.2])
        XCTAssertTrue(handle.isVisible)
    }

    func testEmptyScreenConfigurationRetainsHandleUntilAValidScreenReturns() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 300, height: 400)
        )
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )
        let retainedPlacement = handle.placements.last

        coordinator.reclampPanelFrame(visibleFrames: [])

        XCTAssertEqual(coordinator.presentationState, .stashed)
        XCTAssertTrue(handle.isVisible)
        XCTAssertEqual(handle.placements.last, retainedPlacement)

        coordinator.reclampPanelFrame(
            visibleFrames: [CGRect(x: 0, y: 0, width: 800, height: 600)]
        )

        XCTAssertTrue(handle.isVisible)
        XCTAssertEqual(handle.placements.last?.frame.maxX, 800)
    }

    func testRestorePreservesPreStashGeometryAfterTemporarySmallerScreen() throws {
        let originalFrame = CGRect(x: 620, y: 80, width: 360, height: 680)
        let largeScreen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let smallScreen = CGRect(x: 0, y: 0, width: 800, height: 400)
        var currentVisibleFrames = [largeScreen]
        let panel = FakePanelWindow(frame: originalFrame)
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { currentVisibleFrames }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stash(visibleFrames: currentVisibleFrames))

        currentVisibleFrames = [smallScreen]
        coordinator.reclampPanelFrame(visibleFrames: currentVisibleFrames)
        currentVisibleFrames = [largeScreen]
        coordinator.reclampPanelFrame(visibleFrames: currentVisibleFrames)
        handle.restore()

        XCTAssertEqual(panel.frame, originalFrame)
        XCTAssertTrue(panel.isVisible)
    }

    func testScreenChangePreservesMovedHandleRelativeVerticalIntent() throws {
        let panel = FakePanelWindow(frame: CGRect(x: 620, y: 100, width: 300, height: 400))
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )
        handle.move(
            to: PanelStashPlacement(
                side: .left,
                frame: CGRect(x: 0, y: 100, width: 36, height: 96)
            )
        )

        coordinator.reclampPanelFrame(
            visibleFrames: [CGRect(x: 0, y: 0, width: 1_200, height: 900)]
        )

        XCTAssertEqual(handle.placements.last?.side, .left)
        XCTAssertEqual(handle.placements.last?.frame.minX, 0)
        XCTAssertEqual(handle.placements.last?.frame.minY ?? 0, 114.204_545_455, accuracy: 0.001)
    }

    func testNewStashAfterRestoreUsesMainPanelPlacementInsteadOfPreviousMove() throws {
        let panel = FakePanelWindow(frame: CGRect(x: 620, y: 100, width: 300, height: 400))
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        let visibleFrames = [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
        XCTAssertTrue(coordinator.stash(visibleFrames: visibleFrames))
        handle.move(
            to: PanelStashPlacement(
                side: .left,
                frame: CGRect(x: 0, y: 100, width: 36, height: 96)
            )
        )
        handle.restore()

        XCTAssertTrue(coordinator.stash(visibleFrames: visibleFrames))

        XCTAssertEqual(
            handle.placements.last,
            PanelStashPlacement(
                side: .right,
                frame: CGRect(x: 964, y: 252, width: 36, height: 96)
            )
        )
    }

    func testStashWithoutVisibleScreenLeavesPanelVisible() throws {
        let panel = FakePanelWindow(frame: CGRect(x: 80, y: 220, width: 400, height: 360))
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertFalse(coordinator.stash(visibleFrames: []))

        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(handle.isVisible)
    }

    func testShortcutStyleActionStashesVisiblePanelAndRestoresIt() throws {
        let panel = FakePanelWindow(frame: CGRect(x: 620, y: 100, width: 300, height: 400))
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        coordinator.show(page: page)

        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(handle.isVisible)

        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(handle.isVisible)
        XCTAssertEqual(loader.activatedPages, [page])
    }

    func testGlobalShortcutRestoresExpandedPanelWithoutStashingIt() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            isExpanded: true
        )
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertTrue(coordinator.performGlobalShortcutAction())

        XCTAssertFalse(panel.isExpanded)
        XCTAssertEqual(panel.restoreFromExpandedStateCount, 1)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.orderOutCount, 0)
        XCTAssertFalse(handle.isVisible)
        XCTAssertEqual(loader.panelHideCount, 0)
    }

    func testRepresentationTransitionsPresentIncomingBeforeRemovingOutgoing() throws {
        var events: [String] = []
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 300, height: 400),
            recordEvent: { events.append($0) }
        )
        let handle = FakeStashHandle(recordEvent: { events.append($0) })
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        events.removeAll()

        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())
        XCTAssertEqual(events, ["handle.present", "panel.orderOut"])

        events.removeAll()
        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())
        XCTAssertEqual(events, ["panel.present", "handle.orderOut"])
    }

    func testTemporaryPeekRestashOrdersOutImmediatelyAfterPresentingHandle() throws {
        var events: [String] = []
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 300, height: 400),
            defersStashDismissal: true,
            recordEvent: { events.append($0) }
        )
        let handle = FakeStashHandle(recordEvent: { events.append($0) })
        let loader = FakePageLoader()
        let signposter = PerformanceSignposterSpy()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle,
            performanceSignposter: signposter,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        events.removeAll()

        XCTAssertTrue(coordinator.stashCurrentPageImmediately())

        XCTAssertEqual(events, ["handle.present", "panel.orderOut"])
        XCTAssertEqual(loader.panelHideCount, 1)
        XCTAssertEqual(signposter.beginCalls.last, .peekRestash)
        XCTAssertEqual(signposter.endCalls.last?.outcome, .success)
    }

    func testShortcutPresentationMeasuresRequestAndWarmUsefulContent() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 300, height: 400)
        )
        let loader = FakePageLoader()
        loader.webViewRetention = .warm
        let signposter = PerformanceSignposterSpy()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: FakeStashHandle(),
            performanceSignposter: signposter,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        _ = coordinator.stashOrRestoreCurrentPage()

        let measurement = ShortcutPresentationMeasurement(
            signposter: signposter,
            requestToken: signposter.begin(.shortcutPressToPresentationRequest),
            usefulContentToken: signposter.begin(.shortcutPressToUsefulContent)
        )
        XCTAssertTrue(coordinator.showCurrentPageFromShortcut(measurement: measurement))

        XCTAssertEqual(
            Array(signposter.beginCalls.suffix(2)),
            [.shortcutPressToPresentationRequest, .shortcutPressToUsefulContent]
        )
        XCTAssertEqual(loader.shortcutMeasurementRetentions, [.warm])
        XCTAssertEqual(signposter.endCalls.last?.metadata.webViewRetention, .warm)
        XCTAssertEqual(panel.locateHaloCount, 1)
        XCTAssertTrue(panel.restoreTransitionPlacements.isEmpty)
    }

    func testPullRevealScrubsRetainedPanelAndRestoresPastThreshold() throws {
        let originalFrame = CGRect(x: 620, y: 100, width: 300, height: 400)
        let panel = FakePanelWindow(frame: originalFrame)
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle,
            reducesMotion: { false },
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())

        handle.pull(to: 75)

        XCTAssertEqual(panel.pullRevealPresentationCount, 1)
        XCTAssertEqual(panel.frame.origin.x, 803.448, accuracy: 0.001)
        XCTAssertEqual(panel.frame.origin.y, 100)
        XCTAssertEqual(panel.frame.size, CGSize(width: 300, height: 400))
        XCTAssertTrue(handle.finishPull(at: 75))
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(handle.isVisible)
        XCTAssertEqual(panel.animatedSetFrames.last, originalFrame)
        XCTAssertEqual(loader.panelShowCount, 2)
    }

    func testCompletedEdgePullRequestsContextBeforePresentingPanel() throws {
        let panel = FakePanelWindow(frame: CGRect(x: 620, y: 100, width: 300, height: 400))
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())
        handle.pull(to: 75)
        var revealCount = 0
        coordinator.onWillReveal = { revealCount += 1 }

        XCTAssertTrue(handle.finishPull(at: 75))

        XCTAssertEqual(revealCount, 1)
        XCTAssertTrue(panel.isVisible)
    }

    func testPullRevealBelowThresholdReturnsPanelAndHandleToStashedState() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 300, height: 400)
        )
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())

        handle.pull(to: 40)

        XCTAssertFalse(handle.finishPull(at: 40))
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(handle.isVisible)
        XCTAssertEqual(coordinator.presentationState, .stashed)
    }

    func testPullRevealDuringStashAnimationDoesNotDuplicateWebLifecycleShow() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 300, height: 400),
            defersStashDismissal: true
        )
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())

        handle.pull(to: 75)
        XCTAssertTrue(handle.finishPull(at: 75))

        XCTAssertEqual(loader.panelHideCount, 0)
        XCTAssertEqual(loader.panelShowCount, 1)
        panel.completeStashDismissal()
        XCTAssertTrue(panel.isVisible)
    }

    func testDraggingNearCornerPresentsTargetOnlyWhileMouseIsPressed() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 870, y: 220, width: 520, height: 600)
        )
        let snapTargets = FakeSnapTargetPresenter()
        let mouse = MutableBoolean(true)
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            snapTargetPresenter: snapTargets,
            isPrimaryMouseButtonPressed: { mouse.value },
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_440, height: 875)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        coordinator.recordPanelMove()

        XCTAssertEqual(snapTargets.presentedTargets.last?.corner, .topRight)
        mouse.value = false
        coordinator.recordPanelMove()
        XCTAssertEqual(snapTargets.dismissCount, 1)
    }

    func testCornerSnapWaitsUntilTrackpadMoveEnds() async throws {
        let originalFrame = CGRect(x: 870, y: 220, width: 520, height: 600)
        let panel = FakePanelWindow(frame: originalFrame)
        panel.isTrackpadMoveActive = true
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            isPrimaryMouseButtonPressed: { false },
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_440, height: 875)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        coordinator.recordPanelMove()
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(panel.frame, originalFrame)

        panel.isTrackpadMoveActive = false
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(panel.frame, CGRect(x: 920, y: 275, width: 520, height: 600))
    }

    func testDoubleTapFullScreenDoesNotGetPinchedBackByCornerSnap() async throws {
        let expandedFrame = CGRect(x: 0, y: 0, width: 1_440, height: 875)
        let panel = FakePanelWindow(
            frame: CGRect(x: 870, y: 220, width: 520, height: 600)
        )
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            isPrimaryMouseButtonPressed: { false },
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_440, height: 875)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        panel.isExpanded = true
        panel.move(to: expandedFrame)
        coordinator.recordPanelMove()

        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(panel.frame, expandedFrame)
    }

    func testDraggingPastStashThresholdDismissesCornerSnapTarget() throws {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let panel = FakePanelWindow(
            frame: CGRect(x: 576, y: 276, width: 400, height: 500)
        )
        let snapTargets = FakeSnapTargetPresenter()
        let mouse = MutableBoolean(true)
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            snapTargetPresenter: snapTargets,
            isPrimaryMouseButtonPressed: { mouse.value },
            visibleFramesProvider: { [screen] }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        coordinator.recordPanelMove()
        XCTAssertEqual(snapTargets.presentedTargets.last?.corner, .topRight)

        panel.move(to: CGRect(x: 760, y: 276, width: 400, height: 500))
        coordinator.recordPanelMove()

        XCTAssertGreaterThanOrEqual(snapTargets.dismissCount, 1)
        XCTAssertEqual(snapTargets.presentedTargets.count, 1)
    }

    func testFinishingDragBeyondOuterEdgeStashesAndPersistsVisibleRestoreFrame() throws {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let panel = FakePanelWindow(
            frame: CGRect(x: 0, y: 150, width: 400, height: 500)
        )
        let handle = FakeStashHandle()
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [screen] },
            initialPreferredContentSize: panel.frame.size,
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        panel.move(to: CGRect(x: -160, y: 150, width: 400, height: 500))

        coordinator.finishPanelMove()

        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(handle.isVisible)
        XCTAssertEqual(handle.placements.last?.side, .left)
        XCTAssertEqual(
            geometryStore.load()?.frame,
            CGRect(x: 0, y: 150, width: 400, height: 500)
        )
        XCTAssertEqual(coordinator.presentationState, .stashed)
    }

    func testFinishingDragAtStashThresholdWinsOverCornerSnap() throws {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let panel = FakePanelWindow(
            frame: CGRect(x: 600, y: 24, width: 400, height: 500)
        )
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: FakeStashHandle(),
            visibleFramesProvider: { [screen] },
            initialPreferredContentSize: panel.frame.size,
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        panel.move(to: CGRect(x: 760, y: 24, width: 400, height: 500))

        coordinator.finishPanelMove()

        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(
            geometryStore.load()?.frame,
            CGRect(x: 600, y: 24, width: 400, height: 500)
        )
    }

    func testDraggingBeyondEdgeDoesNotStashUntilMouseIsReleased() async throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 0, y: 150, width: 400, height: 500)
        )
        let mouse = MutableBoolean(true)
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: FakeStashHandle(),
            isPrimaryMouseButtonPressed: { mouse.value },
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        panel.move(to: CGRect(x: -160, y: 150, width: 400, height: 500))

        coordinator.recordPanelMove()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(panel.isVisible)

        mouse.value = false
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(panel.isVisible)
    }

    func testDragStashWaitsUntilTrackpadMoveEnds() async throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 600, y: 150, width: 400, height: 500)
        )
        panel.isTrackpadMoveActive = true
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: FakeStashHandle(),
            isPrimaryMouseButtonPressed: { false },
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        panel.move(to: CGRect(x: 760, y: 150, width: 400, height: 500))

        coordinator.recordPanelMove()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(panel.isVisible)

        panel.isTrackpadMoveActive = false
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(panel.isVisible)
    }

    func testFinishingDragBelowThresholdLeavesPanelVisible() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 0, y: 150, width: 400, height: 500)
        )
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: FakeStashHandle(),
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        panel.move(to: CGRect(x: -159, y: 150, width: 400, height: 500))

        coordinator.finishPanelMove()

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(coordinator.presentationState, .visible)
        XCTAssertEqual(panel.frame, CGRect(x: 0, y: 150, width: 400, height: 500))
    }

    func testFinishingDragTowardAGappedNeighborLeavesThePanelVisible() throws {
        let primary = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let secondary = CGRect(x: 1_050, y: 0, width: 1_000, height: 800)
        let panel = FakePanelWindow(
            frame: CGRect(x: 600, y: 150, width: 400, height: 500)
        )
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: FakeStashHandle(),
            visibleFramesProvider: { [primary, secondary] }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        panel.move(to: CGRect(x: 760, y: 150, width: 400, height: 500))

        coordinator.finishPanelMove()

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(coordinator.presentationState, .visible)
        XCTAssertEqual(panel.frame.origin.x, 600)
    }

    func testFullyOffscreenMoveStillStashesOnceTheDragEnds() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 0, y: 150, width: 400, height: 500)
        )
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: FakeStashHandle(),
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        panel.move(to: CGRect(x: -400, y: 150, width: 400, height: 500))

        coordinator.recordPanelMove()
        coordinator.finishPanelMove()

        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(coordinator.presentationState, .stashed)
    }

    func testRedCloseRequestsTheSameStashTransition() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 300, height: 400)
        )
        let handle = FakeStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        panel.requestClose()

        XCTAssertEqual(coordinator.presentationState, .stashed)
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(handle.isVisible)
    }

    func testShortcutStyleActionLeavesPanelVisibleWhenStashPlacementIsUnavailable() throws {
        let panel = FakePanelWindow(frame: CGRect(x: 620, y: 100, width: 300, height: 400))
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: FakeStashHandle(),
            visibleFramesProvider: { [] }
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(coordinator.presentationState, .visible)
    }

    func testPinCoordinatorExposesNarrowStashOrRestoreAction() throws {
        let panel = FakePanelCoordinator()
        let coordinator = PinCoordinator(
            panelCoordinator: panel,
            pasteboard: FakePasteboard(value: nil),
            requestPageURLFocus: {}
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        coordinator.pin(page: page)

        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.presentationState, .stashed)
    }

    func testPanelCoordinatorReclampsItsFrameAfterScreenConfigurationChange() {
        let panel = FakePanelWindow(frame: CGRect(x: 1_500, y: 800, width: 600, height: 700))
        let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: FakePageLoader())

        coordinator.reclampPanelFrame(visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 700)])

        XCTAssertEqual(panel.frame, CGRect(x: 400, y: 0, width: 600, height: 700))
    }

    func testTopologyObserverRepositionsVisiblePanelAndIgnoresStaleDeliveryWithoutReloading() throws {
        let original = displayTopology(revision: 1)
        let geometry = try secondaryGeometry(in: original)
        let observer = FakeDisplayTopologyObserver(currentTopology: original)
        let panel = FakePanelWindow(frame: geometry.frame)
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            displayTopologyObserver: observer,
            displayTopologyProvider: { observer.currentTopology },
            initialGeometry: geometry
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        coordinator.show(page: page)
        let lifecycleEvents = loader.lifecycleEvents

        observer.emit(
            DisplayTopology(
                revision: 2,
                displays: [primaryDisplay(width: 500, height: 400)]
            )
        )
        XCTAssertEqual(panel.frame, CGRect(x: 0, y: 0, width: 500, height: 375))

        observer.emit(displayTopology(revision: 3))
        XCTAssertEqual(panel.frame, geometry.frame)
        let appliedFrameCount = panel.setFrames.count

        observer.emit(
            DisplayTopology(
                revision: 2,
                displays: [primaryDisplay(width: 800, height: 600)]
            )
        )

        XCTAssertEqual(panel.setFrames.count, appliedFrameCount)
        XCTAssertEqual(loader.lifecycleEvents, lifecycleEvents)
        XCTAssertTrue(loader.reloadedPages.isEmpty)
        XCTAssertEqual(coordinator.currentPage, page)
    }

    func testTopologyObserverMovesOnlyExistingHandleWhileStashed() throws {
        let original = displayTopology(revision: 1)
        let geometry = try secondaryGeometry(in: original)
        let observer = FakeDisplayTopologyObserver(currentTopology: original)
        let panel = FakePanelWindow(frame: geometry.frame)
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle,
            displayTopologyObserver: observer,
            displayTopologyProvider: { observer.currentTopology },
            initialGeometry: geometry
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.stashOrRestoreCurrentPage())
        let panelFrame = panel.frame
        let panelPresentCount = panel.presentCount
        let lifecycleEvents = loader.lifecycleEvents
        let panelHideCount = loader.panelHideCount

        observer.emit(
            DisplayTopology(
                revision: 2,
                displays: [primaryDisplay(width: 1_000, height: 800)]
            )
        )

        XCTAssertEqual(panel.frame, panelFrame)
        XCTAssertEqual(panel.presentCount, panelPresentCount)
        XCTAssertTrue(handle.isVisible)
        XCTAssertEqual(handle.placements.count, 2)
        XCTAssertEqual(handle.placements.last?.frame.maxX, 1_000)
        XCTAssertEqual(loader.lifecycleEvents, lifecycleEvents)
        XCTAssertEqual(loader.panelHideCount, panelHideCount)
    }

    func testTopologyObserverRepositionsHiddenPanelWithoutPresentingIt() throws {
        let original = displayTopology(revision: 1)
        let geometry = try secondaryGeometry(in: original)
        let observer = FakeDisplayTopologyObserver(currentTopology: original)
        let panel = FakePanelWindow(frame: geometry.frame)
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle,
            displayTopologyObserver: observer,
            displayTopologyProvider: { observer.currentTopology },
            initialGeometry: geometry
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        panel.orderOut()
        let panelPresentCount = panel.presentCount
        let lifecycleEvents = loader.lifecycleEvents

        observer.emit(
            DisplayTopology(
                revision: 2,
                displays: [primaryDisplay(width: 1_000, height: 800)]
            )
        )

        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.presentCount, panelPresentCount)
        XCTAssertEqual(panel.setFrameDisplays.last, false)
        XCTAssertFalse(handle.isVisible)
        XCTAssertEqual(loader.lifecycleEvents, lifecycleEvents)
    }

    func testTopologyObserverLeavesExpandedPanelFrameToAppKit() throws {
        let original = displayTopology(revision: 1)
        let geometry = try secondaryGeometry(in: original)
        let observer = FakeDisplayTopologyObserver(currentTopology: original)
        let panel = FakePanelWindow(frame: geometry.frame, isExpanded: true)
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            displayTopologyObserver: observer,
            displayTopologyProvider: { observer.currentTopology },
            initialGeometry: geometry
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        let appliedFrameCount = panel.setFrames.count
        let lifecycleEvents = loader.lifecycleEvents

        observer.emit(
            DisplayTopology(
                revision: 2,
                displays: [primaryDisplay(width: 1_000, height: 800)]
            )
        )

        XCTAssertEqual(panel.setFrames.count, appliedFrameCount)
        XCTAssertTrue(panel.isExpanded)
        XCTAssertEqual(loader.lifecycleEvents, lifecycleEvents)
    }

    func testPanelCoordinatorDefersContextualPlacementUntilFirstPresentationAndRunsItOnce() throws {
        let initialFrame = CGRect(x: 896, y: 171, width: 520, height: 680)
        let panel = FakePanelWindow(frame: CGRect(origin: .zero, size: initialFrame.size))
        var placementCount = 0
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_440, height: 900)]
            },
            initialFrameProvider: {
                placementCount += 1
                return initialFrame
            }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")

        XCTAssertEqual(placementCount, 0)
        XCTAssertTrue(panel.setFrames.isEmpty)

        coordinator.show(page: page)
        XCTAssertTrue(coordinator.showCurrentPage())

        XCTAssertEqual(placementCount, 1)
        XCTAssertEqual(panel.setFrames, [initialFrame])
    }

    func testPanelCoordinatorPreservesAutosavedGeometryWhenContextualPlacementIsDisabled() throws {
        let autosavedFrame = CGRect(x: 120, y: 80, width: 600, height: 700)
        let panel = FakePanelWindow(frame: autosavedFrame)
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_440, height: 900)]
            },
            initialFrameProvider: nil
        )

        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertEqual(panel.frame, autosavedFrame)
        XCTAssertTrue(panel.setFrames.isEmpty)
    }

    func testPanelCoordinatorNormalizesMinimumSizeAfterScreenConfigurationChange() {
        let panel = FakePanelWindow(frame: CGRect(x: 800, y: 380, width: 200, height: 300))
        let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: FakePageLoader())

        coordinator.reclampPanelFrame(
            visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
        )

        XCTAssertEqual(panel.frame, CGRect(x: 640, y: 260, width: 360, height: 420))
    }

    func testPinCoordinatorUsesReplaceForDifferentActivePage() throws {
        let panel = FakePanelCoordinator()
        let coordinator = PinCoordinator(
            panelCoordinator: panel,
            pasteboard: FakePasteboard(value: nil),
            requestPageURLFocus: {}
        )
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")

        coordinator.pin(page: firstPage)
        coordinator.pin(page: secondPage)

        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
        XCTAssertEqual(panel.replacedPages.map(\.pageID), [secondPageID])
    }

    func testExternalRouteParsingReturnsCanonicalPageForRuntimeActivation() throws {
        let panel = FakePanelCoordinator()
        let coordinator = PinCoordinator(
            panelCoordinator: panel,
            pasteboard: FakePasteboard(value: nil),
            requestPageURLFocus: {}
        )
        let routeURL = try XCTUnwrap(
            URL(
                string:
                    "perch://pin?url=https%3A%2F%2Fwww.notion.so%2F\(firstPageID)&source=chrome-extension"
            )
        )

        let pages = coordinator.externalPages(from: [routeURL])

        XCTAssertEqual(pages.map(\.0.pageID), [firstPageID])
        XCTAssertTrue(panel.shownPages.isEmpty)
    }

    func testAppDelegateBuffersOpenURLsUntilBindingAndDrainsOnlyOnce() throws {
        let appDelegate = AppDelegate()
        let handler = FakeApplicationURLHandler()
        let routeURL = try XCTUnwrap(
            URL(
                string:
                    "perch://pin?url=https%3A%2F%2Fwww.notion.so%2F\(firstPageID)&source=chrome-extension"
            )
        )

        appDelegate.application(NSApplication.shared, open: [routeURL])
        XCTAssertTrue(handler.deliveries.isEmpty)

        appDelegate.bind(urlHandler: handler)
        appDelegate.bind(urlHandler: handler)

        XCTAssertEqual(handler.deliveries, [[routeURL]])
    }

    func testMenuDisplayTitleIsLimitedToThirtyCharacters() throws {
        let page = try makePage(
            id: firstPageID,
            title: "12345678901234567890123456789012345"
        )

        let title = PagePickerDisplay.title(for: page)

        XCTAssertEqual(title, "12345678901234567890123456789…")
        XCTAssertEqual(title.count, 30)
        XCTAssertEqual(
            PagePickerDisplay.helpText(for: page),
            "12345678901234567890123456789012345"
        )
        XCTAssertEqual(
            PagePickerDisplay.fullTitle(for: page),
            "12345678901234567890123456789012345"
        )
    }

    func testAppRuntimeRegistersShortcutOnlyOnce() {
        let shortcut = FakeShortcutRegistrar()
        let runtime = AppRuntime(
            panelCoordinator: FakePanelCoordinator(),
            pasteboard: FakePasteboard(value: nil),
            shortcutRegistrar: shortcut
        )

        runtime.start()
        runtime.start()

        XCTAssertEqual(shortcut.registerCount, 1)
        XCTAssertNotNil(shortcut.handler)
    }

    func testPanelSizeApplyRequiresAPinnedPage() {
        let panel = FakePanelWindow(
            frame: CGRect(x: 100, y: 100, width: 520, height: 680)
        )
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )

        XCTAssertFalse(
            coordinator.applyPanelContentSize(
                CGSize(width: 680, height: 720)
            )
        )
        XCTAssertTrue(panel.setFrames.isEmpty)
        XCTAssertFalse(panel.isVisible)
    }

    func testMovePanelSupportsEveryExplicitCornerAndCommitsSelection() throws {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let panel = FakePanelWindow(
            frame: CGRect(x: 300, y: 150, width: 400, height: 500)
        )
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { [screen] },
            initialPreferredContentSize: panel.frame.size,
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        let expectedFrames: [PanelCorner: CGRect] = [
            .topLeft: CGRect(x: 0, y: 300, width: 400, height: 500),
            .topRight: CGRect(x: 600, y: 300, width: 400, height: 500),
            .bottomLeft: CGRect(x: 0, y: 0, width: 400, height: 500),
            .bottomRight: CGRect(x: 600, y: 0, width: 400, height: 500),
        ]

        for corner in PanelCorner.allCases {
            XCTAssertTrue(coordinator.movePanel(to: corner))
            XCTAssertEqual(panel.frame, expectedFrames[corner])
            XCTAssertEqual(coordinator.selectedCorner, corner)
            XCTAssertEqual(panel.animatedSetFrames.last, expectedFrames[corner])
            XCTAssertEqual(geometryStore.load()?.anchor, corner.anchor())
            XCTAssertEqual(
                geometryStore.load()?.desiredContentSize.cgSize,
                CGSize(width: 400, height: 500)
            )
        }
    }

    func testMovePanelCommitsTargetWhileFrameAnimationIsInFlight() throws {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let originalFrame = CGRect(x: 300, y: 150, width: 400, height: 500)
        let targetFrame = CGRect(x: 0, y: 300, width: 400, height: 500)
        let panel = FakePanelWindow(
            frame: originalFrame,
            defersAnimatedFrameChanges: true
        )
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { [screen] },
            initialPreferredContentSize: originalFrame.size,
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertTrue(coordinator.movePanel(to: .topLeft))

        XCTAssertEqual(panel.frame, originalFrame)
        XCTAssertEqual(geometryStore.load()?.frame, targetFrame)
        XCTAssertEqual(coordinator.selectedCorner, .topLeft)
    }

    func testRestashingDuringFrameAnimationUsesTargetGeometry() throws {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let originalFrame = CGRect(x: 300, y: 150, width: 400, height: 500)
        let targetFrame = CGRect(x: 600, y: 300, width: 400, height: 500)
        let panel = FakePanelWindow(
            frame: originalFrame,
            defersAnimatedFrameChanges: true
        )
        let handle = FakeStashHandle()
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [screen] },
            initialPreferredContentSize: originalFrame.size,
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.movePanel(to: .topRight))

        XCTAssertTrue(coordinator.stash(visibleFrames: [screen]))

        XCTAssertEqual(panel.frame, targetFrame)
        XCTAssertEqual(geometryStore.load()?.frame, targetFrame)
    }

    func testProgrammaticMoveNotificationsRemainSuppressedUntilAnimationCompletes() async throws {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let originalFrame = CGRect(x: 300, y: 150, width: 400, height: 500)
        let targetFrame = CGRect(x: 0, y: 300, width: 400, height: 500)
        let panel = FakePanelWindow(
            frame: originalFrame,
            defersAnimatedFrameChanges: true
        )
        let geometryStore = TransientPanelGeometryStore()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { [screen] },
            initialPreferredContentSize: originalFrame.size,
            geometryStore: geometryStore
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.movePanel(to: .topLeft))
        await Task.yield()

        panel.move(to: CGRect(x: 160, y: 220, width: 400, height: 500))
        coordinator.recordPanelMove()

        XCTAssertEqual(geometryStore.load()?.frame, targetFrame)
        panel.completeFrameAnimation()
        XCTAssertEqual(panel.frame, targetFrame)
    }

    func testStaleTopologyDoesNotSettleActiveFrameAnimation() throws {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let originalFrame = CGRect(x: 300, y: 150, width: 400, height: 500)
        let panel = FakePanelWindow(
            frame: originalFrame,
            defersAnimatedFrameChanges: true
        )
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { [screen] },
            initialPreferredContentSize: originalFrame.size
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        XCTAssertTrue(coordinator.movePanel(to: .topLeft))

        coordinator.applyDisplayTopology(
            DisplayTopology(
                revision: 0,
                displays: [
                    DisplayDescriptor(
                        identifier: 11,
                        frame: screen,
                        visibleFrame: screen,
                        backingScaleFactor: 2,
                        isPrimary: true
                    )
                ]
            )
        )

        XCTAssertEqual(panel.frame, originalFrame)
    }

    func testManualMoveAwayFromExplicitCornerClearsPublishedSelection() async throws {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let panel = FakePanelWindow(
            frame: CGRect(x: 300, y: 150, width: 400, height: 500)
        )
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { [screen] },
            initialPreferredContentSize: panel.frame.size
        )
        coordinator.show(page: try makePage(id: firstPageID, title: "Roadmap"))
        var publishedCorners: [PanelCorner?] = []
        coordinator.onPanelPositionChange = {
            publishedCorners.append(coordinator.selectedCorner)
        }

        XCTAssertTrue(coordinator.movePanel(to: .topLeft))
        await Task.yield()
        panel.move(to: CGRect(x: 300, y: 150, width: 400, height: 500))
        coordinator.recordPanelMove()

        XCTAssertEqual(publishedCorners, [.topLeft, nil])
        XCTAssertNil(coordinator.selectedCorner)
    }

    func testMovePanelRequiresPinnedPageAndVisibleDisplay() throws {
        let panelWithoutPage = FakePanelWindow(
            frame: CGRect(x: 300, y: 150, width: 400, height: 500)
        )
        let coordinatorWithoutPage = PiPPanelCoordinator(
            panel: panelWithoutPage,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )

        XCTAssertFalse(coordinatorWithoutPage.movePanel(to: .topLeft))
        XCTAssertTrue(panelWithoutPage.animatedSetFrames.isEmpty)

        let panelWithoutDisplay = FakePanelWindow(
            frame: CGRect(x: 300, y: 150, width: 400, height: 500)
        )
        let coordinatorWithoutDisplay = PiPPanelCoordinator(
            panel: panelWithoutDisplay,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { [] }
        )
        coordinatorWithoutDisplay.show(
            page: try makePage(id: secondPageID, title: "Notes")
        )

        XCTAssertFalse(coordinatorWithoutDisplay.movePanel(to: .topLeft))
        XCTAssertTrue(panelWithoutDisplay.animatedSetFrames.isEmpty)
    }

    func testApplyingSizeToNonvisiblePanelShowsRetainedPageWithoutReloading() throws {
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 360, height: 680)
        )
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        coordinator.show(page: page)
        panel.orderOut()

        XCTAssertTrue(
            coordinator.applyPanelContentSize(
                CGSize(width: 680, height: 720)
            )
        )

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.presentCount, 2)
        XCTAssertEqual(loader.activatedPages, [page])
        XCTAssertTrue(loader.reloadedPages.isEmpty)
        XCTAssertEqual(loader.panelShowCount, 2)
    }

    func testApplyingSizeToStashedPanelDismissesHandleWithoutReloading() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let panel = FakePanelWindow(
            frame: CGRect(x: 620, y: 100, width: 360, height: 680)
        )
        let handle = FakeStashHandle()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        coordinator.show(page: page)
        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))

        XCTAssertTrue(
            coordinator.applyPanelContentSize(
                CGSize(width: 420, height: 520)
            )
        )

        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(handle.isVisible)
        XCTAssertEqual(loader.activatedPages, [page])
        XCTAssertTrue(loader.reloadedPages.isEmpty)
        XCTAssertEqual(loader.panelShowCount, 2)
    }

    func testTemporaryDisplayClampRestoresPreferredSizeAndEdgeAnchor() {
        let largeScreen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let smallScreen = CGRect(x: 0, y: 0, width: 500, height: 400)
        let screens = MutableVisibleFrames([largeScreen])
        let preferredFrame = CGRect(x: 300, y: 60, width: 680, height: 720)
        let panel = FakePanelWindow(frame: preferredFrame)
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { screens.value },
            initialPreferredContentSize: preferredFrame.size
        )

        screens.value = [smallScreen]
        coordinator.reclampPanelFrame(visibleFrames: screens.value)
        XCTAssertEqual(panel.frame, smallScreen)

        screens.value = [largeScreen]
        coordinator.reclampPanelFrame(visibleFrames: screens.value)
        XCTAssertEqual(panel.frame, preferredFrame)
    }

    func testCornerAutoFitRestoresPreferredSizeAndAnchorAfterScreenRepositionsFrame() {
        let smallScreen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let largeScreen = CGRect(x: 0, y: 0, width: 1_600, height: 1_200)
        let screens = MutableVisibleFrames([smallScreen])
        let preferredFrame = CGRect(x: 100, y: 100, width: 1_200, height: 900)
        let panel = FakePanelWindow(frame: preferredFrame)
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { screens.value },
            initialPreferredContentSize: preferredFrame.size
        )

        coordinator.snapPanelToCorner()
        XCTAssertEqual(panel.frame, CGRect(x: 0, y: 0, width: 1_000, height: 800))

        screens.value = [largeScreen]
        panel.move(to: CGRect(x: 0, y: 400, width: 1_000, height: 800))
        coordinator.reclampPanelFrame(visibleFrames: screens.value)

        XCTAssertEqual(panel.frame, CGRect(x: 400, y: 300, width: 1_200, height: 900))
    }

    func testManualResizeAfterCornerAutoFitReplacesPreferredSize() async {
        let smallScreen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let largeScreen = CGRect(x: 0, y: 0, width: 1_600, height: 1_200)
        let screens = MutableVisibleFrames([smallScreen])
        let panel = FakePanelWindow(
            frame: CGRect(x: 100, y: 100, width: 1_200, height: 900)
        )
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { screens.value },
            initialPreferredContentSize: panel.frame.size
        )
        let resizeRecorded = expectation(description: "Manual resize recorded")
        coordinator.onManualResizeCompletion = { contentSize in
            XCTAssertEqual(contentSize, CGSize(width: 500, height: 600))
            resizeRecorded.fulfill()
        }

        coordinator.snapPanelToCorner()
        await Task.yield()
        panel.move(to: CGRect(x: 476, y: 176, width: 500, height: 600))
        NotificationCenter.default.post(
            name: NSWindow.didEndLiveResizeNotification,
            object: panel
        )
        await fulfillment(of: [resizeRecorded], timeout: 1)

        screens.value = [largeScreen]
        coordinator.reclampPanelFrame(visibleFrames: screens.value)

        XCTAssertEqual(panel.frame, CGRect(x: 1_076, y: 576, width: 500, height: 600))
    }

    func testExpandedResizeCompletionDoesNotReplacePreferredFloatingSize() async {
        let panel = FakePanelWindow(
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            isExpanded: true
        )
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            },
            initialPreferredContentSize: CGSize(width: 520, height: 680)
        )
        var recordedSizes: [CGSize] = []
        coordinator.onManualResizeCompletion = { recordedSizes.append($0) }

        NotificationCenter.default.post(
            name: NSWindow.didEndLiveResizeNotification,
            object: panel
        )
        await Task.yield()

        XCTAssertTrue(recordedSizes.isEmpty)
        XCTAssertEqual(coordinator.currentPanelContentSize, CGSize(width: 1_000, height: 800))
    }

    func testManualMoveToAnotherDisplayUpdatesPreferredDisplayAnchor() {
        let firstScreen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let secondScreen = CGRect(x: 1_000, y: 0, width: 1_000, height: 800)
        let screens = MutableVisibleFrames([firstScreen, secondScreen])
        let firstFrame = CGRect(x: 500, y: 180, width: 480, height: 600)
        let secondFrame = CGRect(x: 1_500, y: 180, width: 480, height: 600)
        let panel = FakePanelWindow(frame: firstFrame)
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { screens.value },
            initialPreferredContentSize: firstFrame.size
        )

        panel.move(to: secondFrame)
        coordinator.recordPanelMove()
        coordinator.reclampPanelFrame(visibleFrames: screens.value)

        XCTAssertEqual(panel.frame, secondFrame)
    }

    func testManualMoveClampsOnSmallerDisplayAndRestoresOnLargerDisplay() async {
        let largeScreen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let smallScreen = CGRect(x: 1_000, y: 0, width: 500, height: 400)
        let screens = MutableVisibleFrames([largeScreen, smallScreen])
        let preferredFrame = CGRect(x: 300, y: 60, width: 680, height: 720)
        let panel = FakePanelWindow(frame: preferredFrame)
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
            visibleFramesProvider: { screens.value },
            initialPreferredContentSize: preferredFrame.size
        )

        panel.move(to: CGRect(x: 1_000, y: 0, width: 680, height: 720))
        coordinator.recordPanelMove()
        XCTAssertEqual(panel.frame, smallScreen)
        await Task.yield()

        panel.move(to: CGRect(x: 0, y: 0, width: 500, height: 400))
        coordinator.recordPanelMove()
        XCTAssertEqual(panel.frame, CGRect(x: 0, y: 0, width: 680, height: 720))
    }

    private func makePage(id: String, title: String) throws -> NotionPageReference {
        try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/\(title)-\(id)"))
        )
    }

    private func secondaryGeometry(in topology: DisplayTopology) throws -> PanelGeometry {
        let secondary = try XCTUnwrap(topology.displays.last)
        return try PanelGeometry(
            desiredContentSize: PanelContentSize(width: 680, height: 720),
            frame: CGRect(x: 2_656, y: 311, width: 680, height: 720),
            visibleFrame: secondary.visibleFrame,
            anchor: PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: 24,
                verticalEdge: .top,
                verticalInset: 24
            ),
            displayAffinity: secondary.affinity(in: topology)
        )
    }

    private func displayTopology(revision: UInt64) -> DisplayTopology {
        DisplayTopology(
            revision: revision,
            displays: [
                primaryDisplay(),
                DisplayDescriptor(
                    identifier: 22,
                    frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
                    visibleFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_055),
                    backingScaleFactor: 1,
                    isPrimary: false
                ),
            ]
        )
    }

    private func primaryDisplay(
        width: CGFloat = 1_440,
        height: CGFloat = 900
    ) -> DisplayDescriptor {
        DisplayDescriptor(
            identifier: 11,
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            visibleFrame: CGRect(x: 0, y: 0, width: width, height: height - 25),
            backingScaleFactor: 2,
            isPrimary: true
        )
    }
}

@MainActor
private final class MutableVisibleFrames {
    var value: [CGRect]

    init(_ value: [CGRect]) {
        self.value = value
    }
}

private struct FailingPanelGeometryStore: PanelGeometryPersisting {
    struct SaveError: Error {}

    func load() -> PanelGeometry? {
        nil
    }

    func save(_ geometry: PanelGeometry) throws {
        throw SaveError()
    }
}

@MainActor
private final class FakePanelWindow: PiPPanelWindow {
    private(set) var presentCount = 0
    private(set) var orderOutCount = 0
    private(set) var frame: CGRect
    private(set) var isVisible = false
    var isExpanded: Bool
    var isTrackpadMoveActive = false
    var isInLiveResize = false
    private(set) var restoreFromExpandedStateCount = 0
    private(set) var setFrames: [CGRect] = []
    private(set) var setFrameDisplays: [Bool] = []
    private(set) var animatedSetFrames: [CGRect] = []
    private(set) var locateHaloCount = 0
    private(set) var pullRevealPresentationCount = 0
    private(set) var stashTransitionPlacements: [PanelStashPlacement] = []
    private(set) var restoreTransitionPlacements: [PanelStashPlacement] = []
    var onClose: (@MainActor () -> Void)?
    private let recordEvent: (String) -> Void
    private let defersStashDismissal: Bool
    private let defersRestorePresentation: Bool
    private let defersAnimatedFrameChanges: Bool
    private let usesStashTransitionFrame: Bool
    private var pendingStashCompletion: (@MainActor () -> Void)?
    private var pendingStashOriginalFrame: CGRect?
    private var pendingRestoreOriginalFrame: CGRect?
    private var pendingAnimatedFrame: CGRect?
    private var pendingFrameAnimationCompletion: (@MainActor () -> Void)?

    init(
        frame: CGRect = .zero,
        isExpanded: Bool = false,
        defersStashDismissal: Bool = false,
        defersRestorePresentation: Bool = false,
        defersAnimatedFrameChanges: Bool = false,
        usesStashTransitionFrame: Bool = false,
        recordEvent: @escaping (String) -> Void = { _ in }
    ) {
        self.frame = frame
        self.isExpanded = isExpanded
        self.defersStashDismissal = defersStashDismissal
        self.defersRestorePresentation = defersRestorePresentation
        self.defersAnimatedFrameChanges = defersAnimatedFrameChanges
        self.usesStashTransitionFrame = usesStashTransitionFrame
        self.recordEvent = recordEvent
    }

    func present() {
        recordEvent("panel.present")
        presentCount += 1
        isVisible = true
    }

    func presentFromStash(
        placement: PanelStashPlacement,
        restoredFrame: CGRect,
        completion: @escaping @MainActor () -> Void
    ) {
        restoreTransitionPlacements.append(placement)
        pendingRestoreOriginalFrame = restoredFrame
        guard defersRestorePresentation else {
            frame = restoredFrame
            present()
            completion()
            return
        }
        frame = PanelStashTransition.panelTargetFrame(from: restoredFrame, toward: placement)
        present()
    }

    func presentForPullReveal(at frame: CGRect) {
        pullRevealPresentationCount += 1
        self.frame = frame
        isVisible = true
    }

    func pulseLocateHalo() {
        locateHaloCount += 1
    }

    func orderOut() {
        recordEvent("panel.orderOut")
        orderOutCount += 1
        isVisible = false
    }

    func restoreFromExpandedState() {
        restoreFromExpandedStateCount += 1
        isExpanded = false
    }

    func setFrame(_ frame: CGRect, display: Bool) {
        pendingAnimatedFrame = nil
        pendingFrameAnimationCompletion = nil
        self.frame = frame
        setFrames.append(frame)
        setFrameDisplays.append(display)
    }

    func setFrame(_ frame: CGRect, display: Bool, animate: Bool) {
        setFrame(frame, display: display, animate: animate, completion: {})
    }

    func setFrame(
        _ frame: CGRect,
        display: Bool,
        animate: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        if animate, defersAnimatedFrameChanges {
            animatedSetFrames.append(frame)
            pendingAnimatedFrame = frame
            pendingFrameAnimationCompletion = completion
            return
        }
        setFrame(frame, display: display)
        if animate {
            animatedSetFrames.append(frame)
        }
        completion()
    }

    func completeFrameAnimation() {
        guard let pendingAnimatedFrame else { return }
        self.pendingAnimatedFrame = nil
        frame = pendingAnimatedFrame
        let completion = pendingFrameAnimationCompletion
        pendingFrameAnimationCompletion = nil
        completion?()
    }

    func move(to frame: CGRect) {
        self.frame = frame
    }

    func requestClose() {
        onClose?()
    }

    func dismissForStash(
        toward placement: PanelStashPlacement,
        restoring restoreFrame: CGRect,
        completion: @escaping @MainActor () -> Void
    ) {
        stashTransitionPlacements.append(placement)
        pendingStashOriginalFrame = restoreFrame
        guard defersStashDismissal else {
            orderOut()
            frame = restoreFrame
            completion()
            return
        }
        if usesStashTransitionFrame {
            frame = PanelStashTransition.panelTargetFrame(from: restoreFrame, toward: placement)
        }
        pendingStashCompletion = completion
    }

    func completeStashDismissal() {
        guard let completion = pendingStashCompletion else { return }
        orderOut()
        if let pendingStashOriginalFrame {
            frame = pendingStashOriginalFrame
        }
        pendingStashOriginalFrame = nil
        completion()
        pendingStashCompletion = nil
    }

    func cancelPendingStashDismissal() {
        pendingStashCompletion = nil
        if let pendingStashOriginalFrame {
            frame = pendingStashOriginalFrame
        }
        pendingStashOriginalFrame = nil
        if let pendingRestoreOriginalFrame {
            frame = pendingRestoreOriginalFrame
        }
        pendingRestoreOriginalFrame = nil
    }
}

@MainActor
private final class FakeDisplayTopologyObserver: DisplayTopologyObserving {
    private(set) var currentTopology: DisplayTopology
    private var handler: (@MainActor (DisplayTopology) -> Void)?

    init(currentTopology: DisplayTopology) {
        self.currentTopology = currentTopology
    }

    func start(_ handler: @escaping @MainActor (DisplayTopology) -> Void) {
        self.handler = handler
    }

    func stop() {
        handler = nil
    }

    func emit(_ topology: DisplayTopology) {
        currentTopology = topology
        handler?(topology)
    }
}

@MainActor
private final class FakePageLoader: NotionPageLoading {
    enum LifecycleEvent: Equatable {
        case activated
        case reloaded
        case shown
    }

    private(set) var activatedPages: [NotionPageReference] = []
    private(set) var reloadedPages: [NotionPageReference] = []
    private(set) var reselectedPages: [NotionPageReference] = []
    private(set) var lifecycleEvents: [LifecycleEvent] = []
    private(set) var panelShowCount = 0
    private(set) var panelHideCount = 0
    var webViewRetention = WebViewRetention.unknown
    private(set) var shortcutMeasurementRetentions: [WebViewRetention] = []

    func activate(page: NotionPageReference) {
        activatedPages.append(page)
        lifecycleEvents.append(.activated)
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        reloadedPages.append(page)
        lifecycleEvents.append(.reloaded)
    }

    func reselect(page: NotionPageReference) {
        reselectedPages.append(page)
    }

    func panelDidShow() {
        panelShowCount += 1
        lifecycleEvents.append(.shown)
    }

    func panelDidHide() {
        panelHideCount += 1
    }

    func beginShortcutPresentationMeasurement(
        signposter: any PerformanceSignposting,
        token: PerformanceIntervalToken?,
        retention: WebViewRetention
    ) {
        shortcutMeasurementRetentions.append(retention)
    }
}

@MainActor
private final class FakeStashHandle: PiPStashHandle {
    private(set) var isVisible = false
    private(set) var placements: [PanelStashPlacement] = []
    private(set) var entrances: [PiPStashHandleEntrance] = []
    private(set) var orderOutCount = 0
    private(set) var dismissForRestoreCount = 0
    private(set) var pullRevealTravels: [CGFloat] = []
    private var onRestore: (@MainActor () -> Void)?
    private var onPlacementChange: (@MainActor (PanelStashPlacement) -> Void)?
    private var onPullRevealChange: (@MainActor (CGFloat) -> Void)?
    private var onPullRevealEnd: (@MainActor (CGFloat) -> Bool)?
    private let recordEvent: (String) -> Void

    init(recordEvent: @escaping (String) -> Void = { _ in }) {
        self.recordEvent = recordEvent
    }

    func configurePullRevealTravel(_ travel: CGFloat) {
        pullRevealTravels.append(travel)
    }

    func present(
        placement: PanelStashPlacement,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void,
        onPullRevealChange: @escaping @MainActor (CGFloat) -> Void,
        onPullRevealEnd: @escaping @MainActor (CGFloat) -> Bool
    ) {
        recordEvent("handle.present")
        placements.append(placement)
        self.onRestore = onRestore
        self.onPlacementChange = onPlacementChange
        self.onPullRevealChange = onPullRevealChange
        self.onPullRevealEnd = onPullRevealEnd
        isVisible = true
    }

    func present(
        placement: PanelStashPlacement,
        entrance: PiPStashHandleEntrance,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void,
        onPullRevealChange: @escaping @MainActor (CGFloat) -> Void,
        onPullRevealEnd: @escaping @MainActor (CGFloat) -> Bool
    ) {
        entrances.append(entrance)
        present(
            placement: placement,
            onRestore: onRestore,
            onPlacementChange: onPlacementChange,
            onPullRevealChange: onPullRevealChange,
            onPullRevealEnd: onPullRevealEnd
        )
    }

    func dismissForRestore() {
        dismissForRestoreCount += 1
        orderOut()
    }

    func orderOut() {
        recordEvent("handle.orderOut")
        orderOutCount += 1
        isVisible = false
        onRestore = nil
        onPlacementChange = nil
        onPullRevealChange = nil
        onPullRevealEnd = nil
    }

    func restore() {
        onRestore?()
    }

    func move(to placement: PanelStashPlacement) {
        onPlacementChange?(placement)
    }

    func pull(to inwardDistance: CGFloat) {
        onPullRevealChange?(inwardDistance)
    }

    @discardableResult
    func finishPull(at inwardDistance: CGFloat) -> Bool {
        onPullRevealEnd?(inwardDistance) ?? false
    }
}

@MainActor
private final class FakeSnapTargetPresenter: PanelSnapTargetPresenting {
    private(set) var presentedTargets: [PanelCornerSnapTarget] = []
    private(set) var dismissCount = 0

    func present(_ target: PanelCornerSnapTarget) {
        presentedTargets.append(target)
    }

    func dismiss() {
        dismissCount += 1
    }
}

@MainActor
private final class MutableBoolean {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

@MainActor
final class FakePanelCoordinator: PiPPanelCoordinating {
    var onPresentationStateChange: (@MainActor () -> Void)?
    private(set) var currentPage: NotionPageReference?
    private(set) var shownPages: [NotionPageReference] = []
    private(set) var replacedPages: [NotionPageReference] = []
    private(set) var isVisible = false
    private(set) var isStashed = false

    var presentationState: PiPPresentationState {
        guard currentPage != nil else { return .unavailable }
        return isVisible ? .visible : .stashed
    }

    func show(page: NotionPageReference) {
        currentPage = page
        shownPages.append(page)
        isVisible = true
        isStashed = false
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        currentPage = page
    }

    func replace(page: NotionPageReference) {
        currentPage = page
        replacedPages.append(page)
        isVisible = true
        isStashed = false
    }

    func showCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        isVisible = true
        isStashed = false
        return true
    }

    func stashOrRestoreCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        if isVisible {
            isVisible = false
            isStashed = true
        } else {
            _ = showCurrentPage()
        }
        return true
    }
}

struct FakePasteboard: PasteboardReading {
    let value: String?

    func readString() -> String? {
        value
    }
}

@MainActor
private final class FakeApplicationURLHandler: ApplicationURLHandling {
    private(set) var deliveries: [[URL]] = []

    func handleOpenURLs(_ urls: [URL]) {
        deliveries.append(urls)
    }
}

@MainActor
private final class FakeShortcutRegistrar: GlobalShortcutRegistering {
    private(set) var registerCount = 0
    private(set) var handler: (@MainActor () -> Void)?

    func register(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        registerCount += 1
        self.handler = handler
    }

    func revalidate() throws {}
    func unregister() {}
}
