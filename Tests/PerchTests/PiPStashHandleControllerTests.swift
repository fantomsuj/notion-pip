import AppKit
import SwiftUI
import XCTest
@testable import Perch

@MainActor
final class PiPStashHandleControllerTests: XCTestCase {
    func testInjectedTransparentPanelsRemainTransparentWhenPresented() async throws {
        let handlePanel = makePanel()
        let shelfPanel = makePanel()
        handlePanel.alphaValue = 0
        shelfPanel.alphaValue = 0
        let recent = PiPRecentPagesShelfController(
            store: ControllerRecentStore(snapshot: try makeSnapshot(count: 2))
        )
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            recentPagesController: recent,
            handlePanel: handlePanel,
            shelfPanel: shelfPanel,
            shelfDismissDelay: .zero
        )

        present(controller)
        controller.handleHoverChanged(true)
        await waitUntil { shelfPanel.isVisible }

        XCTAssertTrue(handlePanel.isVisible)
        XCTAssertTrue(shelfPanel.isVisible)
        XCTAssertEqual(handlePanel.alphaValue, 0)
        XCTAssertEqual(shelfPanel.alphaValue, 0)
    }

    func testValidDropExpandsPreviewCancelsShelfAndSuppressesRecentRequests() async throws {
        let handlePanel = makePanel()
        let shelfPanel = makePanel()
        let recent = PiPRecentPagesShelfController(
            store: ControllerRecentStore(
                snapshot: try makeSnapshot(count: 2),
                delay: .milliseconds(50)
            )
        )
        var activationCount = 0
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            recentPagesController: recent,
            handlePanel: handlePanel,
            shelfPanel: shelfPanel,
            shelfDismissDelay: .zero,
            activateApplication: { activationCount += 1 }
        )
        present(controller)
        let hostedContent = try XCTUnwrap(handlePanel.contentView)
        let rootView = try handleView(in: handlePanel)
        let drop = try makeDrop(
            pageID: "0123456789abcdef0123456789abcdef",
            sourceLabel: "Roadmap"
        )

        rootView.onHoverChanged(true)
        rootView.onDropCandidateChanged(drop)
        rootView.onHoverChanged(true)
        rootView.onShowRecentPages()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(shelfPanel.isVisible)
        XCTAssertEqual(activationCount, 0)
        XCTAssertTrue(handlePanel.contentView === hostedContent)
        XCTAssertEqual(handlePanel.frame, CGRect(x: 740, y: 352, width: 260, height: 96))
        XCTAssertTrue(rootView.dropTargetModel.isActive)
        XCTAssertEqual(rootView.dropTargetModel.label, "Roadmap")
    }

    func testValidDropHidesVisibleShelfAndExitCollapsesSynchronously() async throws {
        let (controller, handlePanel, shelfPanel, _) = try makeController(itemCount: 2)
        present(controller)
        controller.handleHoverChanged(true)
        await waitUntil { shelfPanel.isVisible }
        let rootView = try handleView(in: handlePanel)
        let drop = try makeDrop(
            pageID: "0123456789abcdef0123456789abcdef",
            sourceLabel: nil
        )

        rootView.onDropCandidateChanged(drop)

        XCTAssertFalse(shelfPanel.isVisible)
        XCTAssertEqual(handlePanel.frame.width, 260)
        XCTAssertEqual(rootView.dropTargetModel.label, "Page")

        rootView.onDropCandidateChanged(nil)

        XCTAssertEqual(handlePanel.frame, placement.frame)
        XCTAssertFalse(rootView.dropTargetModel.isActive)
        XCTAssertNil(rootView.dropTargetModel.label)
    }

    func testLocalTitleUpgradesOnlyTheStillActiveCandidate() async throws {
        let firstID = "0123456789abcdef0123456789abcdef"
        let secondID = "fedcba9876543210fedcba9876543210"
        let titleProvider = ControllerDropTitleProvider(
            responses: [
                firstID: ("Stored First", .milliseconds(70)),
                secondID: ("Stored Second", .milliseconds(5))
            ]
        )
        let handlePanel = makePanel()
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            dropTitleProvider: titleProvider,
            handlePanel: handlePanel,
            shelfPanel: makePanel(),
            shelfDismissDelay: .zero
        )
        present(controller)
        let rootView = try handleView(in: handlePanel)
        let first = try makeDrop(pageID: firstID, sourceLabel: "Dragged First")
        let second = try makeDrop(pageID: secondID, sourceLabel: "Dragged Second")

        rootView.onDropCandidateChanged(first)
        XCTAssertEqual(rootView.dropTargetModel.label, "Dragged First")
        rootView.onDropCandidateChanged(second)
        XCTAssertEqual(rootView.dropTargetModel.label, "Dragged Second")

        await waitUntil { rootView.dropTargetModel.label == "Stored Second" }
        try await Task.sleep(for: .milliseconds(90))

        XCTAssertEqual(rootView.dropTargetModel.label, "Stored Second")
    }

    func testCompletedDropCollapsesBeforeForwardingExactlyOnce() throws {
        let handlePanel = makePanel()
        var forwarded: [NotionPageDrop] = []
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            onDropNotionPage: { drop in
                XCTAssertEqual(handlePanel.frame, self.placement.frame)
                forwarded.append(drop)
            },
            handlePanel: handlePanel,
            shelfPanel: makePanel(),
            shelfDismissDelay: .zero
        )
        present(controller)
        let rootView = try handleView(in: handlePanel)
        let drop = try makeDrop(
            pageID: "0123456789abcdef0123456789abcdef",
            sourceLabel: "Roadmap"
        )
        rootView.onDropCandidateChanged(drop)

        rootView.onDropCandidateChanged(nil)
        rootView.onDropPerformed(drop)
        rootView.onDropPerformed(drop)

        XCTAssertEqual(forwarded, [drop])
        XCTAssertFalse(rootView.dropTargetModel.isActive)
    }

    func testOrderOutCancelsPreviewWorkAndMakesHostedDropCallbacksInert() async throws {
        let pageID = "0123456789abcdef0123456789abcdef"
        let titleProvider = ControllerDropTitleProvider(
            responses: [pageID: ("Stored Title", .milliseconds(40))]
        )
        let handlePanel = makePanel()
        var forwarded: [NotionPageDrop] = []
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            dropTitleProvider: titleProvider,
            onDropNotionPage: { forwarded.append($0) },
            handlePanel: handlePanel,
            shelfPanel: makePanel(),
            shelfDismissDelay: .zero
        )
        present(controller)
        let rootView = try handleView(in: handlePanel)
        let drop = try makeDrop(pageID: pageID, sourceLabel: "Dragged Title")
        rootView.onDropCandidateChanged(drop)

        controller.orderOut()
        rootView.onDropCandidateChanged(drop)
        rootView.onDropPerformed(drop)
        rootView.onHoverChanged(true)
        rootView.onShowRecentPages()
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertFalse(handlePanel.isVisible)
        XCTAssertTrue(forwarded.isEmpty)
        XCTAssertFalse(rootView.dropTargetModel.isActive)
        XCTAssertNil(rootView.dropTargetModel.label)
    }

    func testPresentShowsOnlyHandleAndHoverShowsAttachedShelf() async throws {
        let (controller, handlePanel, shelfPanel, _) = try makeController(itemCount: 3)

        present(controller)

        XCTAssertTrue(handlePanel.isVisible)
        XCTAssertFalse(shelfPanel.isVisible)

        controller.handleHoverChanged(true)
        await waitUntil { shelfPanel.isVisible }

        XCTAssertTrue(shelfPanel.isVisible)
        XCTAssertEqual(shelfPanel.frame.maxX, handlePanel.frame.minX - PanelStashShelfPolicy.edgeGap)
        XCTAssertEqual(handlePanel.frame, placement.frame)
    }

    func testOneCurrentRowAndRepositoryFailureLeaveHandleUsable() async throws {
        let (singleController, singleHandle, singleShelf, _) = try makeController(itemCount: 1)
        present(singleController)
        singleController.handleHoverChanged(true)
        await settle()

        XCTAssertTrue(singleHandle.isVisible)
        XCTAssertFalse(singleShelf.isVisible)

        let handlePanel = makePanel()
        let shelfPanel = makePanel()
        let recent = PiPRecentPagesShelfController(store: ControllerRecentStore(fails: true))
        let failedController = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            recentPagesController: recent,
            handlePanel: handlePanel,
            shelfPanel: shelfPanel,
            shelfDismissDelay: .zero
        )
        present(failedController)
        failedController.handleHoverChanged(true)
        await settle()

        XCTAssertTrue(handlePanel.isVisible)
        XCTAssertFalse(shelfPanel.isVisible)
    }

    func testLeavingBothSurfacesHidesOnlyShelf() async throws {
        let (controller, handlePanel, shelfPanel, _) = try makeController(itemCount: 2)
        present(controller)
        controller.handleHoverChanged(true)
        await waitUntil { shelfPanel.isVisible }

        controller.handleHoverChanged(false)
        await waitUntil { !shelfPanel.isVisible }

        XCTAssertTrue(handlePanel.isVisible)
    }

    func testEnteringShelfCancelsGapDismissal() async throws {
        let handlePanel = makePanel()
        let shelfPanel = makePanel()
        let recent = PiPRecentPagesShelfController(
            store: ControllerRecentStore(snapshot: try makeSnapshot(count: 2))
        )
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            recentPagesController: recent,
            handlePanel: handlePanel,
            shelfPanel: shelfPanel,
            shelfDismissDelay: .milliseconds(40)
        )
        present(controller)
        controller.handleHoverChanged(true)
        await waitUntil { shelfPanel.isVisible }

        controller.handleHoverChanged(false)
        controller.shelfHoverChanged(true)
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertTrue(shelfPanel.isVisible)
    }

    func testSecondaryClickRequestsFocusAndShowsShelf() async throws {
        var activationCount = 0
        let (controller, _, shelfPanel, _) = try makeController(
            itemCount: 2,
            activateApplication: { activationCount += 1 }
        )
        present(controller)

        controller.showRecentPages()
        await waitUntil { shelfPanel.isVisible }

        XCTAssertEqual(activationCount, 1)
        XCTAssertTrue(shelfPanel.becomesKeyOnlyIfNeeded)
    }

    func testFocusRequestSurvivesHoverRequestDuringDelayedLoad() async throws {
        let handlePanel = makePanel()
        let shelfPanel = makePanel()
        let recent = PiPRecentPagesShelfController(
            store: ControllerRecentStore(
                snapshot: try makeSnapshot(count: 2),
                delay: .milliseconds(40)
            )
        )
        var activationCount = 0
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            recentPagesController: recent,
            handlePanel: handlePanel,
            shelfPanel: shelfPanel,
            shelfDismissDelay: .zero,
            activateApplication: { activationCount += 1 }
        )
        present(controller)

        controller.showRecentPages()
        controller.handleHoverChanged(true)
        await waitUntil { shelfPanel.isVisible }

        XCTAssertTrue(shelfPanel.isVisible)
        XCTAssertEqual(activationCount, 1)
        XCTAssertTrue(shelfPanel.becomesKeyOnlyIfNeeded)
    }

    func testFocusRequestSurvivesPointerExitDuringDelayedLoad() async throws {
        let handlePanel = makePanel()
        let shelfPanel = makePanel()
        let recent = PiPRecentPagesShelfController(
            store: ControllerRecentStore(
                snapshot: try makeSnapshot(count: 2),
                delay: .milliseconds(40)
            )
        )
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            recentPagesController: recent,
            handlePanel: handlePanel,
            shelfPanel: shelfPanel,
            shelfDismissDelay: .zero
        )
        present(controller)

        controller.showRecentPages()
        controller.handleHoverChanged(false)
        await waitUntil { shelfPanel.isVisible }

        XCTAssertTrue(shelfPanel.isVisible)
        XCTAssertTrue(shelfPanel.becomesKeyOnlyIfNeeded)
    }

    func testFocusedShelfSurvivesPointerExitAndDismissesWhenFocusIsLost() async throws {
        let (controller, _, shelfPanel, _) = try makeController(itemCount: 2)
        present(controller)

        controller.showRecentPages()
        await waitUntil { shelfPanel.isVisible }
        controller.handleHoverChanged(false)
        controller.shelfHoverChanged(false)
        await settle()

        XCTAssertTrue(shelfPanel.isVisible)

        controller.shelfDidResignKey()

        XCTAssertFalse(shelfPanel.isVisible)
    }

    func testDragHidesShelfAndSnapsFromHandleFrame() async throws {
        var placements: [PanelStashPlacement] = []
        let (controller, handlePanel, shelfPanel, _) = try makeController(itemCount: 2)
        controller.present(
            placement: placement,
            onRestore: {},
            onPlacementChange: { placements.append($0) }
        )
        controller.handleHoverChanged(true)
        await waitUntil { shelfPanel.isVisible }

        controller.finishDrag(frame: CGRect(x: 120, y: 210, width: 36, height: 96))

        XCTAssertFalse(shelfPanel.isVisible)
        XCTAssertEqual(handlePanel.frame, CGRect(x: 0, y: 210, width: 36, height: 96))
        XCTAssertEqual(placements.last?.frame, handlePanel.frame)
    }

    func testSelectionOrdersOutShelfBeforeInvokingCallbackOnce() async throws {
        let handlePanel = makePanel()
        let shelfPanel = makePanel()
        let snapshot = try makeSnapshot(count: 2)
        let recent = PiPRecentPagesShelfController(store: ControllerRecentStore(snapshot: snapshot))
        var selections: [PiPRecentPageSelection] = []
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            recentPagesController: recent,
            onSelectRecentPage: { selection in
                XCTAssertFalse(shelfPanel.isVisible)
                selections.append(selection)
            },
            handlePanel: handlePanel,
            shelfPanel: shelfPanel,
            shelfDismissDelay: .zero
        )
        present(controller)
        controller.handleHoverChanged(true)
        await waitUntil { shelfPanel.isVisible }

        controller.selectRecentPage(id: snapshot.pages[1].pageID)

        let selectedPageIDs = selections.compactMap { selection -> String? in
            guard case let .activate(page, _) = selection else { return nil }
            return page.pageID
        }
        XCTAssertEqual(selectedPageIDs, [snapshot.pages[1].pageID])
        XCTAssertTrue(handlePanel.isVisible)
    }

    func testSelectingCurrentRowRestoresWithoutRepinning() async throws {
        let handlePanel = makePanel()
        let shelfPanel = makePanel()
        let snapshot = try makeSnapshot(count: 2)
        let recent = PiPRecentPagesShelfController(store: ControllerRecentStore(snapshot: snapshot))
        var restoreCount = 0
        var selections: [PiPRecentPageSelection] = []
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            recentPagesController: recent,
            onSelectRecentPage: { selections.append($0) },
            handlePanel: handlePanel,
            shelfPanel: shelfPanel,
            shelfDismissDelay: .zero
        )
        controller.present(
            placement: placement,
            onRestore: { restoreCount += 1 },
            onPlacementChange: { _ in }
        )
        controller.handleHoverChanged(true)
        await waitUntil { shelfPanel.isVisible }

        controller.selectRecentPage(id: snapshot.pages[0].pageID)

        XCTAssertEqual(restoreCount, 1)
        XCTAssertTrue(selections.isEmpty)
        XCTAssertFalse(shelfPanel.isVisible)
    }

    func testOrderOutCancelsPendingLoadHidesPanelsAndClearsPresentationCallbacks() async throws {
        let handlePanel = makePanel()
        let shelfPanel = makePanel()
        let store = ControllerRecentStore(
            snapshot: try makeSnapshot(count: 2),
            delay: .milliseconds(60)
        )
        let recent = PiPRecentPagesShelfController(store: store)
        var restoreCount = 0
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            recentPagesController: recent,
            handlePanel: handlePanel,
            shelfPanel: shelfPanel,
            shelfDismissDelay: .zero
        )
        controller.present(
            placement: placement,
            onRestore: { restoreCount += 1 },
            onPlacementChange: { _ in }
        )
        let oldHandleView = try XCTUnwrap(
            (handlePanel.contentView as? NSHostingView<PiPStashHandleView>)?.rootView
        )
        controller.handleHoverChanged(true)

        controller.orderOut()
        try await Task.sleep(for: .milliseconds(80))
        oldHandleView.onRestore()

        XCTAssertFalse(handlePanel.isVisible)
        XCTAssertFalse(shelfPanel.isVisible)
        XCTAssertEqual(restoreCount, 0)
    }

    private func makeController(
        itemCount: Int,
        activateApplication: @escaping @MainActor () -> Void = {}
    ) throws -> (
        PiPStashHandleController,
        NSPanel,
        NSPanel,
        PiPRecentPagesSnapshot
    ) {
        let handlePanel = makePanel()
        let shelfPanel = makePanel()
        let snapshot = try makeSnapshot(count: itemCount)
        let recent = PiPRecentPagesShelfController(
            store: ControllerRecentStore(snapshot: snapshot)
        )
        let controller = PiPStashHandleController(
            visibleFramesProvider: { [self] in visibleFrames },
            recentPagesController: recent,
            handlePanel: handlePanel,
            shelfPanel: shelfPanel,
            shelfDismissDelay: .zero,
            activateApplication: activateApplication
        )
        return (controller, handlePanel, shelfPanel, snapshot)
    }

    private func present(_ controller: PiPStashHandleController) {
        controller.present(
            placement: placement,
            onRestore: {},
            onPlacementChange: { _ in }
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.alphaValue = 0
        return panel
    }

    private func handleView(in panel: NSPanel) throws -> PiPStashHandleView {
        try XCTUnwrap(
            (panel.contentView as? NSHostingView<PiPStashHandleView>)?.rootView
        )
    }

    private func makeDrop(pageID: String, sourceLabel: String?) throws -> NotionPageDrop {
        try NotionPageDrop(
            validating: try XCTUnwrap(URL(string: "https://www.notion.so/Page-\(pageID)")),
            sourceLabel: sourceLabel
        )
    }

    private func makeSnapshot(count: Int) throws -> PiPRecentPagesSnapshot {
        let pages = try (0..<count).map { index in
            let pageID = String(format: "%032x", index + 1)
            return StoredPageSnapshot(
                pageID: pageID,
                canonicalURL: try XCTUnwrap(
                    URL(string: "https://www.notion.so/Page-\(index)-\(pageID)")
                ),
                displayTitle: "Page \(index)",
                timestamp: Date(timeIntervalSince1970: 10_000 - Double(index))
            )
        }
        return PiPRecentPagesSnapshot(
            activePageID: pages.first?.pageID,
            pages: pages,
            restorations: []
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition was not satisfied", file: file, line: line)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private var placement: PanelStashPlacement {
        PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 964, y: 352, width: 36, height: 96)
        )
    }

    private var visibleFrames: [CGRect] {
        [CGRect(x: 0, y: 20, width: 1_000, height: 780)]
    }
}

private actor ControllerDropTitleProvider: NotionPageDropTitleProviding {
    private let responses: [String: (title: String?, delay: Duration)]

    init(responses: [String: (title: String?, delay: Duration)]) {
        self.responses = responses
    }

    func displayTitle(for pageID: String) async -> String? {
        guard let response = responses[pageID] else { return nil }
        try? await Task.sleep(for: response.delay)
        return response.title
    }
}

private actor ControllerRecentStore: PiPRecentPagesProviding {
    enum Failure: Error { case unavailable }

    private let snapshot: PiPRecentPagesSnapshot?
    private let fails: Bool
    private let delay: Duration

    init(
        snapshot: PiPRecentPagesSnapshot? = nil,
        fails: Bool = false,
        delay: Duration = .zero
    ) {
        self.snapshot = snapshot
        self.fails = fails
        self.delay = delay
    }

    func recentPiPPages(limit: Int) async throws -> PiPRecentPagesSnapshot {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if fails { throw Failure.unavailable }
        guard let snapshot else { throw Failure.unavailable }
        return PiPRecentPagesSnapshot(
            activePageID: snapshot.activePageID,
            pages: Array(snapshot.pages.prefix(max(limit, 0))),
            restorations: snapshot.restorations
        )
    }
}
