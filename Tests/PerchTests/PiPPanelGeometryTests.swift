import AppKit
import Combine
import WebKit
import XCTest
@testable import Perch

@MainActor
final class PiPPanelGeometryTests: XCTestCase {
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
        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: deadline)
        }
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
