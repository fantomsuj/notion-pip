import AppKit
import Combine
import WebKit
import XCTest
@testable import NotionPiP

@MainActor
final class PiPPanelGeometryTests: XCTestCase {
    func testHorizontalFrameSurvivesRealPanelStashRestore() throws {
        try assertRealPanelStashRestore(
            frame: CGRect(x: 656, y: 356, width: 760, height: 520)
        )
    }

    func testVerticalFrameSurvivesRealPanelStashRestore() throws {
        try assertRealPanelStashRestore(
            frame: CGRect(x: 936, y: 156, width: 480, height: 720)
        )
    }

    func testStashingDoesNotResizeRetainedPanel() throws {
        _ = NSApplication.shared
        let autosaveKey = "NSWindow Frame NotionPiPPanel"
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
            testWindows.first { $0.title == "Notion PiP" }
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

    private func assertRealPanelStashRestore(frame: CGRect) throws {
        _ = NSApplication.shared
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
            visibleFramesProvider: {
                [CGRect(x: 0, y: 0, width: 1_440, height: 900)]
            }
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

        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_440, height: 900)]
            )
        )
        handle.restore()
        drainMainRunLoop()

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame, frame)
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
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void
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
