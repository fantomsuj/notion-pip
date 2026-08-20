import AppKit
import Combine
import SwiftUI
import WebKit
import XCTest
@testable import Perch

@MainActor
final class PiPPanelGeometryTests: XCTestCase {
    func testDropCompositionForwardsTitleProviderToProductionHandle() async throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_200, height: 900)
        let handlePanel = makeDropHandlePanel()
        let titleProvider = GeometryDropTitleProvider(title: "Stored Roadmap")
        let dropComposition = NotionPageDropComposition(
            dropTitleProvider: titleProvider,
            makeStashHandle: { dropTitleProvider, onDropNotionPage in
                PiPStashHandleController(
                    visibleFramesProvider: { [visibleFrame] },
                    dropTitleProvider: dropTitleProvider,
                    onDropNotionPage: onDropNotionPage,
                    handlePanel: handlePanel,
                    shelfPanel: self.makeDropHandlePanel(),
                    shelfDismissDelay: .zero
                )
            }
        )
        dropComposition.stashHandle.present(
            placement: PanelStashPlacement(
                side: .right,
                frame: CGRect(x: 1_164, y: 402, width: 36, height: 96)
            ),
            onRestore: {},
            onPlacementChange: { _ in }
        )
        let handleView = try dropHandleView(in: handlePanel)
        let drop = try NotionPageDrop(
            validating: XCTUnwrap(
                URL(string: "https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef")
            ),
            sourceLabel: "Dragged Roadmap"
        )

        handleView.onDropCandidateChanged(drop)
        for _ in 0..<20 where handleView.dropTargetModel.label != "Stored Roadmap" {
            await Task.yield()
        }

        XCTAssertEqual(handleView.dropTargetModel.label, "Stored Roadmap")
    }

    func testEdgeHandleDropPreviewIsInertAndCompletionRestoresCommittedFrame() async throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_200, height: 900)
        let committedFrame = CGRect(x: 240, y: 140, width: 560, height: 640)
        let panel = EdgeHandleDropFramePanel(frame: committedFrame)
        let handlePanel = makeDropHandlePanel()
        let shelfPanel = makeDropHandlePanel()
        let dropComposition = NotionPageDropComposition(
            makeStashHandle: { _, onDropNotionPage in
                PiPStashHandleController(
                    visibleFramesProvider: { [visibleFrame] },
                    onDropNotionPage: onDropNotionPage,
                    handlePanel: handlePanel,
                    shelfPanel: shelfPanel,
                    shelfDismissDelay: .zero
                )
            }
        )
        let pageLoader = EdgeHandleDropPageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: pageLoader,
            stashHandle: dropComposition.stashHandle,
            visibleFramesProvider: { [visibleFrame] }
        )
        let repository = RuntimePinnedPageRepository()
        let runtime = AppRuntime(
            panelCoordinator: coordinator,
            pageRepository: repository
        )
        dropComposition.bind(to: runtime)
        let currentPage = try NotionPageReference(
            validating: XCTUnwrap(
                URL(string: "https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef")
            )
        )
        let drop = try NotionPageDrop(
            validating: XCTUnwrap(
                URL(string: "https://www.notion.so/Design-System-fedcba9876543210fedcba9876543210")
            ),
            sourceLabel: "Design System"
        )
        runtime.activate(page: currentPage, source: .typedURL)
        try await repository.waitUntilSaveCount(1)
        XCTAssertTrue(coordinator.stash(visibleFrames: [visibleFrame]))
        let handleView = try dropHandleView(in: handlePanel)

        handleView.onDropCandidateChanged(drop)

        XCTAssertEqual(runtime.activePage, currentPage)
        XCTAssertEqual(runtime.lastActivationSource, .typedURL)
        let previewSavedPages = await repository.savedPages()
        XCTAssertEqual(previewSavedPages, [currentPage])
        XCTAssertEqual(pageLoader.activatedPages, [currentPage])
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.frame, committedFrame)

        handleView.onDropPerformed(drop)
        handleView.onDropPerformed(drop)
        try await repository.waitUntilSaveCount(2)

        XCTAssertEqual(runtime.activePage, drop.page)
        XCTAssertEqual(runtime.lastActivationSource, .edgeHandleDrop)
        let completedSavedPages = await repository.savedPages()
        XCTAssertEqual(completedSavedPages, [currentPage, drop.page])
        XCTAssertEqual(pageLoader.activatedPages, [currentPage, drop.page])
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame, committedFrame)
    }

    private static let transitionTimeout: TimeInterval = 1

    func testTopEdgeTrackpadMoveTranslatesRealPanelInBothAxes() {
        let panel = KeyCapablePiPPanel(
            contentRect: CGRect(x: 100, y: 100, width: 400, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(
            CGRect(x: 100, y: 100, width: 400, height: 500),
            display: false
        )
        defer { panel.orderOut(nil) }

        let consumed = panel.handleTopEdgeTrackpadMove(
            TopEdgeTrackpadMoveInput(
                phase: .began,
                momentumPhase: .none,
                hasPreciseScrollingDeltas: true,
                locationInContent: CGPoint(x: 200, y: 492),
                contentBounds: CGRect(x: 0, y: 0, width: 400, height: 500),
                isContentFlipped: false,
                isExpanded: false,
                visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                translation: CGSize(width: 12, height: -9)
            )
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(panel.frame.origin, CGPoint(x: 112, y: 91))
    }

    func testTopEdgeTrackpadMoveClampsRealPanelToStartingDisplay() {
        let panel = KeyCapablePiPPanel(
            contentRect: CGRect(x: 500, y: 200, width: 400, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(
            CGRect(x: 500, y: 200, width: 400, height: 500),
            display: false
        )
        defer { panel.orderOut(nil) }

        let consumed = panel.handleTopEdgeTrackpadMove(
            TopEdgeTrackpadMoveInput(
                phase: .began,
                momentumPhase: .none,
                hasPreciseScrollingDeltas: true,
                locationInContent: CGPoint(x: 200, y: 492),
                contentBounds: CGRect(x: 0, y: 0, width: 400, height: 500),
                isContentFlipped: false,
                isExpanded: false,
                visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                translation: CGSize(width: 500, height: 500)
            )
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(panel.frame.origin, CGPoint(x: 600, y: 300))
    }

    func testRealPanelReportsTrackpadActivityUntilGestureEnds() {
        let panel = KeyCapablePiPPanel(
            contentRect: CGRect(x: 100, y: 100, width: 400, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer { panel.orderOut(nil) }

        XCTAssertFalse(panel.isTrackpadMoveActive)

        _ = panel.handleTopEdgeTrackpadMove(
            TopEdgeTrackpadMoveInput(
                phase: .began,
                momentumPhase: .none,
                hasPreciseScrollingDeltas: true,
                locationInContent: CGPoint(x: 200, y: 492),
                contentBounds: CGRect(x: 0, y: 0, width: 400, height: 500),
                isContentFlipped: false,
                isExpanded: false,
                visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                translation: CGSize(width: 12, height: -9)
            )
        )

        XCTAssertTrue(panel.isTrackpadMoveActive)

        _ = panel.handleTopEdgeTrackpadMove(
            TopEdgeTrackpadMoveInput(
                phase: .ended,
                momentumPhase: .none,
                hasPreciseScrollingDeltas: true,
                locationInContent: CGPoint(x: 200, y: 492),
                contentBounds: CGRect(x: 0, y: 0, width: 400, height: 500),
                isContentFlipped: false,
                isExpanded: false,
                visibleFrame: nil,
                translation: .zero
            )
        )

        XCTAssertFalse(panel.isTrackpadMoveActive)
    }

    func testOrderingOutPanelClearsInterruptedTrackpadMove() {
        let panel = KeyCapablePiPPanel(
            contentRect: CGRect(x: 100, y: 100, width: 400, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        _ = panel.handleTopEdgeTrackpadMove(
            TopEdgeTrackpadMoveInput(
                phase: .began,
                momentumPhase: .none,
                hasPreciseScrollingDeltas: true,
                locationInContent: CGPoint(x: 200, y: 492),
                contentBounds: CGRect(x: 0, y: 0, width: 400, height: 500),
                isContentFlipped: false,
                isExpanded: false,
                visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                translation: CGSize(width: 12, height: -9)
            )
        )
        XCTAssertTrue(panel.isTrackpadMoveActive)

        panel.orderOut()

        XCTAssertFalse(panel.isTrackpadMoveActive)
    }

    func testCornerLandingCurveIsMonotonicAndNeverOvershoots() {
        let samples = stride(from: CGFloat.zero, through: 1, by: 0.05).map {
            KeyCapablePiPPanel.criticallyDampedSpringProgress($0)
        }

        XCTAssertEqual(samples.first, 0)
        XCTAssertTrue(zip(samples, samples.dropFirst()).allSatisfy { pair in
            pair.0 <= pair.1
        })
        XCTAssertTrue(samples.allSatisfy { (0...1).contains($0) })
        XCTAssertGreaterThan(samples.last ?? 0, 0.99)
    }

    func testStashAnimationCompressesTowardChosenHandle() {
        let frame = CGRect(x: 120, y: 80, width: 480, height: 720)
        let leftPlacement = PanelStashPlacement(
            side: .left,
            frame: CGRect(x: 0, y: 392, width: 36, height: 96)
        )
        let rightPlacement = PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 964, y: 392, width: 36, height: 96)
        )

        let leftTarget = KeyCapablePiPPanel.stashAnimationTargetFrame(
            from: frame,
            toward: leftPlacement
        )
        let rightTarget = KeyCapablePiPPanel.stashAnimationTargetFrame(
            from: frame,
            toward: rightPlacement
        )

        XCTAssertLessThan(leftTarget.maxX, frame.maxX)
        XCTAssertGreaterThan(rightTarget.minX, frame.minX)
        XCTAssertEqual(leftTarget.width, frame.width * 0.88, accuracy: 0.001)
        XCTAssertEqual(rightTarget.width, frame.width * 0.88, accuracy: 0.001)
        XCTAssertEqual(leftTarget.height, frame.height * 0.94, accuracy: 0.001)
        XCTAssertEqual(rightTarget.height, frame.height * 0.94, accuracy: 0.001)
        XCTAssertEqual(leftTarget.midY, frame.midY, accuracy: 0.001)
        XCTAssertEqual(rightTarget.midY, frame.midY, accuracy: 0.001)
    }

    func testHandleSettleEndpointsMirrorAcrossScreenEdges() {
        let leftPlacement = PanelStashPlacement(
            side: .left,
            frame: CGRect(x: 0, y: 220, width: 36, height: 96)
        )
        let rightPlacement = PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 964, y: 220, width: 36, height: 96)
        )

        let leftStart = PanelStashTransition.unsettledHandleFrame(for: leftPlacement)
        let rightStart = PanelStashTransition.unsettledHandleFrame(for: rightPlacement)

        XCTAssertEqual(leftStart.minX, leftPlacement.frame.minX - 12)
        XCTAssertEqual(rightStart.minX, rightPlacement.frame.minX + 12)
        XCTAssertEqual(leftStart.size, leftPlacement.frame.size)
        XCTAssertEqual(rightStart.size, rightPlacement.frame.size)
    }

    func testHorizontalFrameSurvivesRealPanelStashRestore() throws {
        try assertRealPanelStashRestore(
            requestedSize: CGSize(width: 760, height: 520)
        )
    }

    func testVerticalFrameSurvivesRealPanelStashRestore() throws {
        try assertRealPanelStashRestore(
            requestedSize: CGSize(width: 480, height: 720)
        )
    }

    func testStashingDoesNotResizeRetainedPanel() throws {
        try requireInteractiveAppKitTests()
        _ = NSApplication.shared
        let autosaveKey = "NSWindow Frame PerchPanel"
        let priorAutosavedFrame = UserDefaults.standard.object(forKey: autosaveKey)
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let session = NotionWebSession(
            webView: WKWebView(frame: .zero),
            loadRequest: { _, _ in },
            pauseMedia: { _ in }
        )
        let coordinator = PiPPanelCoordinator(
            webSession: session,
            performanceSignposter: nil
        )
        let testWindows = NSApp.windows.filter {
            !existingWindows.contains(ObjectIdentifier($0))
        }
        let panel = try XCTUnwrap(
            testWindows.first { $0.title == "Perch" }
        )
        testWindows.forEach { $0.alphaValue = 0 }
        defer {
            panel.orderOut(nil)
            _ = panel.setFrameAutosaveName("")
            if let priorAutosavedFrame {
                UserDefaults.standard.set(priorAutosavedFrame, forKey: autosaveKey)
            } else {
                UserDefaults.standard.removeObject(forKey: autosaveKey)
            }
        }
        coordinator.show(
            page: try NotionPageReference(
                validating: XCTUnwrap(
                    URL(
                        string: "https://www.notion.so/123456781234123412341234567890ab"
                    )
                )
            )
        )
        XCTAssertTrue(
            waitForCondition(timeout: Self.transitionTimeout) { panel.isVisible },
            "Panel did not become visible before setting the test frame"
        )
        let requestedFrame = CGRect(x: 100, y: 100, width: 620, height: 680)
        panel.setFrame(requestedFrame, display: false)
        let retainedFrame = panel.frame

        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_728, height: 1_084)]
            )
        )
        XCTAssertTrue(
            waitForCondition(timeout: Self.transitionTimeout) { !panel.isVisible },
            "Panel did not finish stashing"
        )

        XCTAssertEqual(panel.frame, retainedFrame)
    }

    private func waitForCondition(
        timeout: TimeInterval,
        _ condition: @escaping () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(mode: .default, before: deadline)
        }
        return condition()
    }

    private func makeDropHandlePanel() -> NSPanel {
        NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    private func dropHandleView(in panel: NSPanel) throws -> PiPStashHandleView {
        try XCTUnwrap(
            (panel.contentView as? NSHostingView<PiPStashHandleView>)?.rootView
        )
    }

    private func assertRealPanelStashRestore(requestedSize: CGSize) throws {
        try requireInteractiveAppKitTests()
        _ = NSApplication.shared
        let visibleFrame = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let effectiveSize = CGSize(
            width: min(requestedSize.width, visibleFrame.width),
            height: min(requestedSize.height, visibleFrame.height)
        )
        let frame = CGRect(
            x: visibleFrame.maxX - effectiveSize.width,
            y: visibleFrame.minY,
            width: effectiveSize.width,
            height: effectiveSize.height
        )
        let panel = KeyCapablePiPPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.alphaValue = 0
        let handle = GeometryTestStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: GeometryTestPageLoader(),
            stashHandle: handle,
            visibleFramesProvider: { [visibleFrame] }
        )
        defer { panel.orderOut(nil) }
        coordinator.show(
            page: try NotionPageReference(
                validating: XCTUnwrap(
                    URL(
                        string: "https://www.notion.so/123456781234123412341234567890ab"
                    )
                )
            )
        )
        panel.setFrame(frame, display: false)
        let retainedFrame = panel.frame

        XCTAssertTrue(
            coordinator.stash(visibleFrames: [visibleFrame])
        )
        handle.restore()
        XCTAssertTrue(
            waitForCondition(timeout: Self.transitionTimeout) {
                panel.isVisible && panel.frame == retainedFrame
            },
            "Panel did not finish restoring its retained frame"
        )

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame, retainedFrame)
        XCTAssertEqual(panel.frame.size, effectiveSize)
    }
}

@MainActor
private final class GeometryTestPageLoader: NotionPageLoading {
    func activate(page: NotionPageReference) {}
    func reloadPinnedPage(_ page: NotionPageReference) {}
}

@MainActor
private final class GeometryTestStashHandle: PiPStashHandle {
    private(set) var isVisible = false
    private var onRestore: (@MainActor () -> Void)?

    func present(
        placement: PanelStashPlacement,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void,
        onPullRevealChange: @escaping @MainActor (CGFloat) -> Void,
        onPullRevealEnd: @escaping @MainActor (CGFloat) -> Bool
    ) {
        isVisible = true
        self.onRestore = onRestore
    }

    func orderOut() {
        isVisible = false
        onRestore = nil
    }

    func restore() {
        onRestore?()
    }
}

@MainActor
private final class EdgeHandleDropFramePanel: PiPPanelWindow {
    private(set) var frame: CGRect
    private(set) var isVisible = false
    let isExpanded = false
    var onClose: (@MainActor () -> Void)?

    init(frame: CGRect) {
        self.frame = frame
    }

    func present() {
        isVisible = true
    }

    func pulseLocateHalo() {}

    func orderOut() {
        isVisible = false
    }

    func restoreFromExpandedState() {}

    func setFrame(_ frame: CGRect, display: Bool) {
        self.frame = frame
    }
}

@MainActor
private final class EdgeHandleDropPageLoader: NotionPageLoading {
    private(set) var activatedPages: [NotionPageReference] = []

    func activate(page: NotionPageReference) {
        activatedPages.append(page)
    }

    func reloadPinnedPage(_ page: NotionPageReference) {}
}

private actor GeometryDropTitleProvider: NotionPageDropTitleProviding {
    let title: String

    init(title: String) {
        self.title = title
    }

    func displayTitle(for pageID: String) async -> String? {
        title
    }
}
