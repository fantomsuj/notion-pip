import AppKit
import Combine
import SwiftUI
import WebKit
import XCTest
@testable import Perch

@MainActor
final class PiPPanelGeometryTests: XCTestCase {
    func testEdgeHandleDropPreviewIsInertAndCompletionRestoresCommittedFrame() async throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_200, height: 900)
        let committedFrame = CGRect(x: 240, y: 140, width: 560, height: 640)
        let panel = EdgeHandleDropFramePanel(frame: committedFrame)
        let handlePanel = makeDropHandlePanel()
        let shelfPanel = makeDropHandlePanel()
        let dropComposition = NotionPageDropComposition(
            makeStashHandle: { onDropNotionPage in
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

    func testStashAnimationMovesTowardChosenEdgeWithoutChangingPanelSize() {
        let frame = CGRect(x: 120, y: 80, width: 480, height: 720)

        let leftTarget = KeyCapablePiPPanel.stashAnimationTargetFrame(
            from: frame,
            toward: .left
        )
        let rightTarget = KeyCapablePiPPanel.stashAnimationTargetFrame(
            from: frame,
            toward: .right
        )

        XCTAssertLessThan(leftTarget.minX, frame.minX)
        XCTAssertGreaterThan(rightTarget.minX, frame.minX)
        XCTAssertEqual(leftTarget.size, frame.size)
        XCTAssertEqual(rightTarget.size, frame.size)
        XCTAssertEqual(leftTarget.minY, frame.minY)
        XCTAssertEqual(rightTarget.minY, frame.minY)
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
        _ = NSApplication.shared
        let autosaveKey = "NSWindow Frame PerchPanel"
        let priorAutosavedFrame = UserDefaults.standard.object(forKey: autosaveKey)
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let session = NotionWebSession(
            webView: WKWebView(frame: .zero),
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} },
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
        drainMainRunLoop()
        let requestedFrame = CGRect(x: 100, y: 100, width: 620, height: 680)
        panel.setFrame(requestedFrame, display: false)
        let retainedFrame = panel.frame

        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_728, height: 1_084)]
            )
        )
        drainMainRunLoop()

        XCTAssertEqual(panel.frame, retainedFrame)
    }

    private func drainMainRunLoop() {
        let deadline = Date().addingTimeInterval(0.25)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: deadline)
        }
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
        drainMainRunLoop()

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
