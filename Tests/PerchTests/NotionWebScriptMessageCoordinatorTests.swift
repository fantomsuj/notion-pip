import Foundation
import WebKit
import XCTest
@testable import Perch

@MainActor
final class NotionWebScriptMessageCoordinatorTests: XCTestCase {
    func testInstallAndRemovalAdvanceGenerationAndOwnAllThreeBridges() {
        var removedControllers: [WKUserContentController] = []
        let coordinator = NotionWebScriptMessageCoordinator { controller in
            removedControllers.append(controller)
            controller.removeScriptMessageHandler(
                forName: NotionEditorActivityBridge.handlerName,
                contentWorld: .page
            )
            controller.removeScriptMessageHandler(
                forName: NotionScrollBridge.handlerName,
                contentWorld: .page
            )
            controller.removeScriptMessageHandler(
                forName: NotionUsefulContentBridge.handlerName,
                contentWorld: .page
            )
            controller.removeAllUserScripts()
        }
        let firstController = WKUserContentController()
        let secondController = WKUserContentController()

        let firstGeneration = coordinator.install(in: firstController)

        XCTAssertEqual(firstGeneration, 1)
        XCTAssertEqual(coordinator.generation, 1)
        XCTAssertEqual(firstController.userScripts.count, 3)
        XCTAssertTrue(
            firstController.userScripts.allSatisfy {
                $0.injectionTime == .atDocumentStart && $0.isForMainFrameOnly
            }
        )
        XCTAssertTrue(firstController.userScripts[0].source.contains("beforeinput"))
        XCTAssertTrue(firstController.userScripts[1].source.contains("pagehide"))
        XCTAssertTrue(firstController.userScripts[2].source.contains("MutationObserver"))
        XCTAssertTrue(
            firstController.userScripts[2].source.contains("perchUsefulContent")
        )
        XCTAssertTrue(firstController.userScripts[2].source.contains("root !== candidate"))
        XCTAssertTrue(
            firstController.userScripts[2].source.contains("requestAnimationFrame(inspect)")
        )
        XCTAssertTrue(firstController.userScripts[2].source.contains("finish('ready')"))
        XCTAssertTrue(firstController.userScripts[2].source.contains("finish('timedOut')"))
        XCTAssertTrue(firstController.userScripts[2].source.contains("documentID"))
        XCTAssertTrue(firstController.userScripts[2].source.contains("window.clearTimeout(timeout)"))
        XCTAssertTrue(firstController.userScripts[2].source.contains("pagehide"))
        XCTAssertFalse(firstController.userScripts[2].source.contains("textContent"))
        XCTAssertFalse(firstController.userScripts[2].source.contains("innerText"))

        coordinator.remove(from: firstController)

        XCTAssertEqual(coordinator.generation, 2)
        XCTAssertTrue(firstController.userScripts.isEmpty)
        XCTAssertEqual(removedControllers.count, 1)
        XCTAssertTrue(removedControllers[0] === firstController)

        let secondGeneration = coordinator.install(in: secondController)

        XCTAssertEqual(secondGeneration, 3)
        XCTAssertEqual(coordinator.generation, 3)
        XCTAssertEqual(secondController.userScripts.count, 3)
    }

    func testUsefulContentBridgeAcceptsOnlyTrustedMainFrameStates() {
        let documentID = UUID()
        let readyBody: [String: Any] = [
            "state": "ready",
            "documentID": documentID.uuidString,
        ]
        for host in ["app.notion.com", "notion.com", "www.notion.com", "notion.so"] {
            XCTAssertEqual(
                NotionUsefulContentBridge.message(
                    from: readyBody,
                    isMainFrame: true,
                    scheme: "HTTPS",
                    host: host
                ),
                NotionUsefulContentMessage(state: .ready, documentID: documentID)
            )
        }
        XCTAssertEqual(
            NotionUsefulContentBridge.message(
                from: [
                    "state": "timedOut",
                    "documentID": documentID.uuidString,
                ],
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            ),
            NotionUsefulContentMessage(state: .timedOut, documentID: documentID)
        )
        XCTAssertNil(
            NotionUsefulContentBridge.message(
                from: readyBody,
                isMainFrame: false,
                scheme: "https",
                host: "app.notion.com"
            )
        )
        XCTAssertNil(
            NotionUsefulContentBridge.message(
                from: readyBody,
                isMainFrame: true,
                scheme: "http",
                host: "app.notion.com"
            )
        )
        XCTAssertNil(
            NotionUsefulContentBridge.message(
                from: ["ready": true],
                isMainFrame: true,
                scheme: "https",
                host: "notion.example"
            )
        )
        XCTAssertNil(
            NotionUsefulContentBridge.message(
                from: [
                    "state": "unknown",
                    "documentID": documentID.uuidString,
                ],
                isMainFrame: true,
                scheme: "https",
                host: "notion.com"
            )
        )
        XCTAssertNil(
            NotionUsefulContentBridge.message(
                from: ["state": "ready", "documentID": "not-a-uuid"],
                isMainFrame: true,
                scheme: "https",
                host: "notion.com"
            )
        )
    }

    func testUsefulContentScriptTimesOutAndStopsWhenNoRootAppears() async throws {
        let recorder = UsefulContentMessageRecorder()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: NotionWebScriptMessageCoordinator.usefulContentScript(
                    timeoutMilliseconds: 50
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(
            recorder,
            contentWorld: .page,
            name: NotionUsefulContentBridge.handlerName
        )
        let webView = WKWebView(
            frame: .init(x: 0, y: 0, width: 400, height: 300),
            configuration: configuration
        )
        webView.loadHTMLString(
            "<!doctype html><html><body><p>Login</p></body></html>",
            baseURL: try XCTUnwrap(URL(string: "https://www.notion.so/login"))
        )

        try await waitUntil { recorder.states == [.timedOut] }
        _ = try await webView.evaluateJavaScript(
            "document.body.append(document.createElement('div'))"
        )
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(recorder.states, [.timedOut])
        configuration.userContentController.removeScriptMessageHandler(
            forName: NotionUsefulContentBridge.handlerName,
            contentWorld: .page
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw UsefulContentMessageTestError.timeout
    }
}

@MainActor
private final class UsefulContentMessageRecorder: NSObject, WKScriptMessageHandler {
    private(set) var states: [NotionUsefulContentState] = []

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let values = message.body as? [String: Any],
              let rawState = values["state"] as? String,
              let state = NotionUsefulContentState(rawValue: rawState),
              let rawDocumentID = values["documentID"] as? String,
              UUID(uuidString: rawDocumentID) != nil
        else {
            return
        }
        states.append(state)
    }
}

private enum UsefulContentMessageTestError: Error {
    case timeout
}
