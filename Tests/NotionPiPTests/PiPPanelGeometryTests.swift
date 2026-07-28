import AppKit
import Combine
import WebKit
import XCTest
@testable import NotionPiP

@MainActor
final class PiPPanelGeometryTests: XCTestCase {
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
        let stableFrame = CGRect(x: 100, y: 100, width: 620, height: 680)
        panel.setFrame(stableFrame, display: false)

        XCTAssertTrue(
            coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_728, height: 1_084)]
            )
        )
        drainMainRunLoop()

        XCTAssertEqual(panel.frame, stableFrame)
    }

    private func drainMainRunLoop() {
        let deadline = Date().addingTimeInterval(0.25)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: deadline)
        }
    }
}
