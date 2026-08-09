import WebKit
import XCTest
@testable import NotionPiP

@MainActor
final class NotionEditorCaretBridgeTests: XCTestCase {
    private let visibleBody: [String: Any] = [
        "visible": true,
        "left": 120.0,
        "top": 80.0,
        "bottom": 100.0,
        "viewportWidth": 800.0,
        "viewportHeight": 600.0,
    ]

    func testTrustedVisibleMessagePublishesValidatedGeometry() {
        XCTAssertEqual(
            NotionEditorCaretBridge.update(
                from: visibleBody,
                isMainFrame: true,
                scheme: "HTTPS",
                host: "APP.NOTION.COM"
            ),
            .visible(
                NotionEditorCaretGeometry(
                    left: 120,
                    top: 80,
                    bottom: 100,
                    viewportWidth: 800,
                    viewportHeight: 600
                )
            )
        )
    }

    func testTrustedHiddenMessageContainsNoGeometry() {
        for host in ["notion.com", "www.notion.com", "notion.so", "www.notion.so"] {
            XCTAssertEqual(
                NotionEditorCaretBridge.update(
                    from: ["visible": false],
                    isMainFrame: true,
                    scheme: "https",
                    host: host
                ),
                .hidden
            )
        }
    }

    func testBridgeRejectsSubframeNonHTTPSAndUntrustedHost() {
        XCTAssertNil(
            NotionEditorCaretBridge.update(
                from: visibleBody,
                isMainFrame: false,
                scheme: "https",
                host: "www.notion.so"
            )
        )
        XCTAssertNil(
            NotionEditorCaretBridge.update(
                from: visibleBody,
                isMainFrame: true,
                scheme: "http",
                host: "www.notion.so"
            )
        )
        XCTAssertNil(
            NotionEditorCaretBridge.update(
                from: visibleBody,
                isMainFrame: true,
                scheme: "https",
                host: "notion.example"
            )
        )
    }

    func testBridgeRejectsMalformedSchemas() {
        var visibleWithExtraField = visibleBody
        visibleWithExtraField["text"] = "must not cross the bridge"
        XCTAssertNil(
            NotionEditorCaretBridge.update(
                from: visibleWithExtraField,
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            )
        )
        XCTAssertNil(
            NotionEditorCaretBridge.update(
                from: ["visible": false, "left": 1],
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            )
        )
        XCTAssertNil(
            NotionEditorCaretBridge.update(
                from: [
                    "visible": "true",
                    "left": 1,
                    "top": 2,
                    "bottom": 3,
                    "viewportWidth": 4,
                    "viewportHeight": 5,
                ],
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            )
        )
        var numericVisibility = visibleBody
        numericVisibility["visible"] = NSNumber(value: 1)
        XCTAssertNil(
            NotionEditorCaretBridge.update(
                from: numericVisibility,
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            )
        )
        var booleanCoordinate = visibleBody
        booleanCoordinate["left"] = true
        XCTAssertNil(
            NotionEditorCaretBridge.update(
                from: booleanCoordinate,
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            )
        )
    }

    func testBridgeRejectsNonFiniteAndInvalidViewportGeometry() {
        for (key, value) in [
            ("left", Double.infinity),
            ("top", Double.nan),
            ("bottom", -Double.infinity),
            ("viewportWidth", 0),
            ("viewportHeight", -1),
        ] {
            var invalid = visibleBody
            invalid[key] = value
            XCTAssertNil(
                NotionEditorCaretBridge.update(
                    from: invalid,
                    isMainFrame: true,
                    scheme: "https",
                    host: "www.notion.so"
                ),
                "Expected \(key)=\(value) to be rejected"
            )
        }

        var reversedCaret = visibleBody
        reversedCaret["bottom"] = 79.0
        XCTAssertNil(
            NotionEditorCaretBridge.update(
                from: reversedCaret,
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            )
        )
    }

    func testScriptPublishesOnlyCollapsedCaretInFocusedEditable() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let session = NotionWebSession(webView: webView)
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <body>
                <div id="editor" contenteditable="true">abcdefghij</div>
              </body>
            </html>
            """,
            baseURL: try XCTUnwrap(URL(string: "https://www.notion.so/caret-fixture"))
        )
        try await waitForJavaScriptCondition(in: webView) {
            "document.readyState === 'complete' && Boolean(document.querySelector('#editor'))"
        }
        _ = try await webView.evaluateJavaScript(
            """
            window.__notionPiPEditorCaretInstalled = false;
            window.requestAnimationFrame = (callback) =>
              window.setTimeout(() => callback(performance.now()), 0);
            \(NotionEditorCaretBridge.script)
            true;
            """
        )
        try await waitForCondition { session.editorCaretGeometry == nil }

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const editor = document.querySelector('#editor');
              const text = editor.firstChild;
              editor.focus();
              window.getSelection().setBaseAndExtent(text, 3, text, 3);
              document.dispatchEvent(new Event('selectionchange', { bubbles: true }));
              return true;
            })();
            """
        )
        try await waitForCondition { session.editorCaretGeometry != nil }
        let geometry = try XCTUnwrap(session.editorCaretGeometry)
        XCTAssertGreaterThan(geometry.bottom, geometry.top)
        XCTAssertGreaterThan(geometry.viewportWidth, 0)
        XCTAssertGreaterThan(geometry.viewportHeight, 0)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const text = document.querySelector('#editor').firstChild;
              window.getSelection().setBaseAndExtent(text, 2, text, 5);
              document.dispatchEvent(new Event('selectionchange', { bubbles: true }));
              return true;
            })();
            """
        )
        try await waitForCondition { session.editorCaretGeometry == nil }
    }

    private func waitForCondition(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CaretBridgeTestError.timeout
    }

    private func waitForJavaScriptCondition(
        in webView: WKWebView,
        timeout: Duration = .seconds(2),
        expression: () -> String
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let matches = try? await webView.evaluateJavaScript(expression()) as? Bool,
               matches {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CaretBridgeTestError.timeout
    }
}

private enum CaretBridgeTestError: Error {
    case timeout
}
