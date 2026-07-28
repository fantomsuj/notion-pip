import AppKit
import Foundation
import XCTest
@testable import NotionPiP

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

        handle.restore()

        XCTAssertFalse(handle.isVisible)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.presentCount, 2)
        XCTAssertEqual(loader.activatedPages, [page])
        XCTAssertEqual(coordinator.currentPage, page)
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

    func testScreenChangeRepositionsVisibleStashHandleWithoutChangingPanelFrame() throws {
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
        XCTAssertEqual(handle.placements.last?.side, .right)
        XCTAssertEqual(handle.placements.last?.frame, CGRect(x: 964, y: 604, width: 36, height: 96))
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

    func testScreenChangePreservesMovedStashHandlePlacement() throws {
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

        XCTAssertEqual(
            handle.placements.last,
            PanelStashPlacement(
                side: .left,
                frame: CGRect(x: 0, y: 100, width: 36, height: 96)
            )
        )
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
                frame: CGRect(x: 964, y: 262, width: 36, height: 96)
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

    func testPanelCoordinatorDefersContextualPlacementUntilFirstPresentationAndRunsItOnce() throws {
        let initialFrame = CGRect(x: 896, y: 171, width: 520, height: 680)
        let panel = FakePanelWindow(frame: CGRect(origin: .zero, size: initialFrame.size))
        var placementCount = 0
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: FakePageLoader(),
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

        XCTAssertEqual(panel.frame, CGRect(x: 640, y: 380, width: 360, height: 420))
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
                string: "notion-pip://pin?url=https%3A%2F%2Fwww.notion.so%2F\(firstPageID)&source=chrome-extension"
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
                string: "notion-pip://pin?url=https%3A%2F%2Fwww.notion.so%2F\(firstPageID)&source=chrome-extension"
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
    }

    func testAppRuntimeRegistersShortcutOnlyOnce() {
        let shortcut = FakeShortcutRegistrar()
        let runtime = AppRuntime(
            panelCoordinator: FakePanelCoordinator(),
            pasteboard: FakePasteboard(value: nil),
            shortcutRegistrar: shortcut,
            pageURLInputPresenter: FakePageURLInputPresenter()
        )

        runtime.start()
        runtime.start()

        XCTAssertEqual(shortcut.registerCount, 1)
        XCTAssertNotNil(shortcut.handler)
    }

    private func makePage(id: String, title: String) throws -> NotionPageReference {
        try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/\(title)-\(id)"))
        )
    }
}

@MainActor
private final class FakePanelWindow: PiPPanelWindow {
    private(set) var presentCount = 0
    private(set) var orderOutCount = 0
    private(set) var frame: CGRect
    private(set) var isVisible = false
    private(set) var setFrames: [CGRect] = []
    var onClose: (@MainActor () -> Void)?
    private let recordEvent: (String) -> Void

    init(
        frame: CGRect = .zero,
        recordEvent: @escaping (String) -> Void = { _ in }
    ) {
        self.frame = frame
        self.recordEvent = recordEvent
    }

    func present() {
        recordEvent("panel.present")
        presentCount += 1
        isVisible = true
    }

    func orderOut() {
        recordEvent("panel.orderOut")
        orderOutCount += 1
        isVisible = false
    }

    func setFrame(_ frame: CGRect, display: Bool) {
        self.frame = frame
        setFrames.append(frame)
    }

    func requestClose() {
        onClose?()
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
}

@MainActor
private final class FakeStashHandle: PiPStashHandle {
    private(set) var isVisible = false
    private(set) var placements: [PanelStashPlacement] = []
    private(set) var orderOutCount = 0
    private var onRestore: (@MainActor () -> Void)?
    private var onPlacementChange: (@MainActor (PanelStashPlacement) -> Void)?
    private let recordEvent: (String) -> Void

    init(recordEvent: @escaping (String) -> Void = { _ in }) {
        self.recordEvent = recordEvent
    }

    func present(
        placement: PanelStashPlacement,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void
    ) {
        recordEvent("handle.present")
        placements.append(placement)
        self.onRestore = onRestore
        self.onPlacementChange = onPlacementChange
        isVisible = true
    }

    func orderOut() {
        recordEvent("handle.orderOut")
        orderOutCount += 1
        isVisible = false
        onRestore = nil
        onPlacementChange = nil
    }

    func restore() {
        onRestore?()
    }

    func move(to placement: PanelStashPlacement) {
        onPlacementChange?(placement)
    }
}

@MainActor
final class FakePanelCoordinator: PiPPanelCoordinating {
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

    func unregister() {}
}
