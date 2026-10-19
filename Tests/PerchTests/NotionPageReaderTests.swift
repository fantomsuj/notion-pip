import WebKit
import XCTest
@testable import Perch

@MainActor
final class NotionPageReaderTests: XCTestCase {
    func testNotionModeConvertsRenderedBlocksToMarkdown() async throws {
        let webView = try await makeLoadedWebView(html: Self.notionFixture)

        let result = try await read(webView, mode: .notion)
        let snapshot = try XCTUnwrap(result)

        XCTAssertEqual(snapshot.title, "Project Brief")
        XCTAssertEqual(snapshot.coverage, .renderedBlocks)
        XCTAssertEqual(
            snapshot.body,
            """
            # Goals

            Ship the [roadmap](https://www.notion.so/Roadmap-0123) by Friday.

            - First
                - Nested
            - Second
            - [x] Done thing
            - [ ] Open thing

            ```
            let a = 1
            print(a)
            ```

            > Quoted

            ---

            Left column

            Right column

            | Name | Owner |
            | --- | --- |
            | API | Jay \\| team |

            [Sub page](https://www.notion.so/Sub-page-abc)

            Mystery text

            [image: Diagram]
            """
        )
    }

    func testGenericModeCopiesTheMainRegionText() async throws {
        let webView = try await makeLoadedWebView(
            html: """
            <!doctype html><html><head><title>Course</title></head>
            <body><nav>Menu</nav><main><h1>Week 1</h1><p>Read chapter 2</p></main></body></html>
            """
        )

        let result = try await read(
            webView,
            mode: .generic,
            url: URL(string: "https://canvas.example.edu/courses/1")!,
            fallbackTitle: ""
        )
        let snapshot = try XCTUnwrap(result)

        XCTAssertEqual(snapshot.title, "Course")
        XCTAssertEqual(snapshot.coverage, .visibleText)
        XCTAssertFalse(snapshot.body.contains("Menu"))
        XCTAssertTrue(snapshot.body.contains("Week 1"))
        XCTAssertTrue(snapshot.body.contains("Read chapter 2"))
    }

    func testPageScriptsCannotTamperWithTheReader() async throws {
        let webView = try await makeLoadedWebView(html: Self.notionFixture)
        _ = try await webView.evaluateJavaScript(
            "document.querySelector = () => null; Element.prototype.closest = () => null; true"
        )

        let result = try await read(webView, mode: .notion)
        let snapshot = try XCTUnwrap(result)

        XCTAssertEqual(snapshot.title, "Project Brief")
        XCTAssertEqual(snapshot.coverage, .renderedBlocks)
        XCTAssertTrue(snapshot.body.hasPrefix("# Goals"))
    }

    private func read(
        _ webView: WKWebView,
        mode: NotionPageReaderMode,
        url: URL = URL(string: "https://www.notion.so/Project-Brief")!,
        fallbackTitle: String = "Fallback"
    ) async throws -> AgentPageSnapshot? {
        try await withCheckedThrowingContinuation { continuation in
            NotionPageReader.evaluate(webView, mode) { result in
                switch result {
                case let .success(value):
                    continuation.resume(
                        returning: AgentPageSnapshot(
                            javaScriptValue: value,
                            url: url,
                            fallbackTitle: fallbackTitle
                        )
                    )
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func makeLoadedWebView(html: String) async throws -> WKWebView {
        let webView = WKWebView()
        let navigationFinished = expectation(description: "HTML loaded")
        let delegate = PageReaderTestNavigationDelegate {
            navigationFinished.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.notion.so/"))
        await fulfillment(of: [navigationFinished], timeout: 2)
        withExtendedLifetime(delegate) {}
        return webView
    }

    /// A trimmed copy of the markup Notion renders, using its block classes.
    private static let notionFixture = """
        <!doctype html><html><head><title>Project Brief | Notion</title></head><body>
        <div class="notion-frame">
         <div class="notion-page-block" data-block-id="p0"><h1 contenteditable="true">Project Brief</h1></div>
         <div class="notion-page-content">
          <div class="notion-selectable notion-header-block" data-block-id="b1"><h2><div data-content-editable-leaf="true" contenteditable="true">Goals</div></h2></div>
          <div class="notion-selectable notion-text-block" data-block-id="b2"><div data-content-editable-leaf="true" contenteditable="true">Ship the <a href="/Roadmap-0123">roadmap</a> by&nbsp;Friday.</div></div>
          <div class="notion-selectable notion-bulleted_list-block" data-block-id="b3"><div data-content-editable-leaf="true" contenteditable="true">First</div>
             <div><div class="notion-selectable notion-bulleted_list-block" data-block-id="b3a"><div data-content-editable-leaf="true" contenteditable="true">Nested</div></div></div></div>
          <div class="notion-selectable notion-bulleted_list-block" data-block-id="b4"><div data-content-editable-leaf="true" contenteditable="true">Second</div></div>
          <div class="notion-selectable notion-to_do-block" data-block-id="b5"><input type="checkbox" checked><div data-content-editable-leaf="true" contenteditable="true" style="text-decoration: line-through">Done thing</div></div>
          <div class="notion-selectable notion-to_do-block" data-block-id="b6"><input type="checkbox"><div data-content-editable-leaf="true" contenteditable="true">Open thing</div></div>
          <div class="notion-selectable notion-code-block" data-block-id="b7"><div style="white-space: pre-wrap" data-content-editable-leaf="true" contenteditable="true">let a = 1&#10;print(a)</div></div>
          <div class="notion-selectable notion-quote-block" data-block-id="b8"><div data-content-editable-leaf="true" contenteditable="true">Quoted</div></div>
          <div class="notion-selectable notion-divider-block" data-block-id="b9"><div></div></div>
          <div class="notion-selectable notion-column_list-block" data-block-id="c1">
            <div class="notion-selectable notion-column-block" data-block-id="c1a"><div class="notion-selectable notion-text-block" data-block-id="c1a1"><div data-content-editable-leaf="true">Left column</div></div></div>
            <div class="notion-selectable notion-column-block" data-block-id="c1b"><div class="notion-selectable notion-text-block" data-block-id="c1b1"><div data-content-editable-leaf="true">Right column</div></div></div>
          </div>
          <div class="notion-selectable notion-table-block" data-block-id="t1"><table><tr><td>Name</td><td>Owner</td></tr><tr><td>API</td><td>Jay | team</td></tr></table></div>
          <div class="notion-selectable notion-page-block" data-block-id="pg"><a href="/Sub-page-abc">Sub page</a></div>
          <div class="notion-selectable notion-weird_new-block" data-block-id="w1">Mystery text</div>
          <div class="notion-selectable notion-image-block" data-block-id="i1"><img alt="Diagram" src="https://example.com/x.png"></div>
         </div>
        </div></body></html>
        """
}

@MainActor
private final class PageReaderTestNavigationDelegate: NSObject, WKNavigationDelegate {
    private let didFinish: @MainActor () -> Void

    init(didFinish: @escaping @MainActor () -> Void) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish()
    }
}
