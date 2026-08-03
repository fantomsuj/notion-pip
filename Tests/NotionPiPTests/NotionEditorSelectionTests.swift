import WebKit
import XCTest
@testable import NotionPiP

@MainActor
final class NotionEditorSelectionTests: XCTestCase {
    func testScriptsRoundTripBackwardSelectionInSameEditableElement() async throws {
        let webView = try await makeLoadedWebView()
        _ = try await webView.callAsyncJavaScript(
            """
            const text = document.getElementById('editor').firstChild;
            document.getElementById('editor').focus();
            window.getSelection().setBaseAndExtent(text, 7, text, 3);
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )

        let captureValue = try await webView.evaluateJavaScript(
            NotionEditorSelectionEvaluation.capture.script
        )
        let snapshot = try XCTUnwrap(
            NotionEditorSelectionSnapshot(javaScriptValue: captureValue)
        )
        _ = try await webView.callAsyncJavaScript(
            """
            const text = document.getElementById('editor').firstChild;
            window.getSelection().setBaseAndExtent(text, 0, text, 0);
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )

        let restored = try await webView.evaluateJavaScript(
            NotionEditorSelectionEvaluation.restore(snapshot).script
        ) as? Bool
        let selection = try await webView.callAsyncJavaScript(
            """
            const selection = window.getSelection();
            return {
              anchorOffset: selection.anchorOffset,
              focusOffset: selection.focusOffset,
              selectedText: selection.toString(),
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertEqual(restored, true)
        XCTAssertEqual(selection?["anchorOffset"] as? Int, 7)
        XCTAssertEqual(selection?["focusOffset"] as? Int, 3)
        XCTAssertEqual(selection?["selectedText"] as? String, "defg")
    }

    func testRestoreRejectsReplacementEditableElementAtSameDOMPath() async throws {
        let webView = try await makeLoadedWebView()
        _ = try await webView.callAsyncJavaScript(
            """
            const text = document.getElementById('editor').firstChild;
            document.getElementById('editor').focus();
            window.getSelection().setBaseAndExtent(text, 2, text, 5);
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let captureValue = try await webView.evaluateJavaScript(
            NotionEditorSelectionEvaluation.capture.script
        )
        let snapshot = try XCTUnwrap(
            NotionEditorSelectionSnapshot(javaScriptValue: captureValue)
        )
        _ = try await webView.callAsyncJavaScript(
            """
            const editor = document.getElementById('editor');
            editor.replaceWith(editor.cloneNode(true));
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )

        let restored = try await webView.evaluateJavaScript(
            NotionEditorSelectionEvaluation.restore(snapshot).script
        ) as? Bool

        XCTAssertEqual(restored, false)
    }

    func testInsertReplacesStoredSelectionAndMovesCursorAfterPrefill() async throws {
        let webView = try await makeLoadedWebView()
        _ = try await webView.callAsyncJavaScript(
            """
            const text = document.getElementById('editor').firstChild;
            document.getElementById('editor').focus();
            window.getSelection().setBaseAndExtent(text, 3, text, 7);
            return true;
            """, arguments: [:], in: nil, contentWorld: .page
        )
        let value = try await webView.evaluateJavaScript(NotionEditorSelectionEvaluation.capture.script)
        let snapshot = try XCTUnwrap(NotionEditorSelectionSnapshot(javaScriptValue: value))

        let inserted = try await webView.evaluateJavaScript(
            NotionEditorSelectionEvaluation.insert("CAPTURE", at: snapshot).script
        ) as? Bool
        let result = try await webView.callAsyncJavaScript(
            "return document.getElementById('editor').textContent",
            arguments: [:], in: nil, contentWorld: .page
        ) as? String

        XCTAssertEqual(inserted, true)
        XCTAssertEqual(result, "abcCAPTUREhij")
    }

    private func makeLoadedWebView() async throws -> WKWebView {
        let webView = WKWebView()
        let navigationFinished = expectation(description: "HTML loaded")
        let delegate = SelectionTestNavigationDelegate {
            navigationFinished.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <body>
                <div id="editor" contenteditable="true">abcdefghij</div>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://www.notion.so/")
        )
        await fulfillment(of: [navigationFinished], timeout: 2)
        withExtendedLifetime(delegate) {}
        return webView
    }
}

@MainActor
private final class SelectionTestNavigationDelegate: NSObject, WKNavigationDelegate {
    private let didFinish: @MainActor () -> Void

    init(didFinish: @escaping @MainActor () -> Void) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish()
    }
}
