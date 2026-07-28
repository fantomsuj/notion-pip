import AppKit
import Foundation
import os
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
final class CaptureWebViewRichTextTests: XCTestCase {
    func testPastingHTTPSURLOverSelectionLinksWithoutReplacingText() async throws {
        let session = try await makeReadyFormattingSession(
            draftID: "format-link-paste-draft",
            document: #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Selected text"}]}]}"#
        )

        let result = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            const text = editor.querySelector('p').firstChild;
            editor.focus();
            const range = document.createRange();
            range.setStart(text, 0);
            range.setEnd(text, 8);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            document.dispatchEvent(new Event('selectionchange'));
            await new Promise((resolve) => setTimeout(resolve, 20));
            const clipboard = new DataTransfer();
            clipboard.setData('text/plain', 'https://example.com/reference');
            editor.dispatchEvent(new ClipboardEvent('paste', {
              bubbles: true,
              cancelable: true,
              clipboardData: clipboard,
            }));
            await new Promise((resolve) => setTimeout(resolve, 20));
            const link = editor.querySelector('a');
            return {
              body: editor.innerText,
              href: link?.getAttribute('href') || '',
              linkedText: link?.textContent || '',
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: String]

        XCTAssertEqual(normalizedDOMText(result?["body"]), "Selected text")
        XCTAssertEqual(result?["href"], "https://example.com/reference")
        XCTAssertEqual(result?["linkedText"], "Selected")
    }

    func testPastingURLOverLinkIneligibleSelectionFallsBackToNormalPaste() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "format-link-fallback-draft",
                title: "Formatting",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","marks":[{"type":"code"}],"text":"Selected text"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        let session = CaptureEditorSession(repository: repository)
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        let result = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            const text = editor.querySelector('code').firstChild;
            editor.focus();
            const range = document.createRange();
            range.setStart(text, 0);
            range.setEnd(text, 8);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            document.dispatchEvent(new Event('selectionchange'));
            await new Promise((resolve) => setTimeout(resolve, 20));
            const clipboard = new DataTransfer();
            clipboard.setData('text/plain', 'https://example.com/fallback');
            editor.dispatchEvent(new ClipboardEvent('paste', {
              bubbles: true,
              cancelable: true,
              clipboardData: clipboard,
            }));
            await new Promise((resolve) => setTimeout(resolve, 20));
            return {
              body: editor.innerText,
              hasLink: Boolean(editor.querySelector('a')),
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertEqual(normalizedDOMText(result?["body"] as? String), "https://example.com/fallback text")
        XCTAssertEqual(result?["hasLink"] as? Bool, false)
    }

    func testMarkdownMarkersCreateHeadingQuoteAndListNodes() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "markdown-markers-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        _ = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            editor.focus();
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        sendWebText("# Heading", to: session.webView)
        sendWebKey("\r", keyCode: 36, to: session.webView)
        sendWebText("> Quoted", to: session.webView)
        sendWebKey("\r", keyCode: 36, to: session.webView)
        sendWebKey("\r", keyCode: 36, to: session.webView)
        sendWebText("- Listed", to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            """
            const editor = document.querySelector('#editor .tiptap');
            return editor.querySelector('h1')?.textContent === 'Heading'
              && editor.querySelector('blockquote')?.textContent === 'Quoted'
              && editor.querySelector('ul:not([data-type="taskList"])')?.textContent === 'Listed';
            """
        }
        let result = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            return {
              heading: editor.querySelector('h1')?.textContent || '',
              quote: editor.querySelector('blockquote')?.textContent || '',
              list: editor.querySelector('ul:not([data-type="taskList"])')?.textContent || '',
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: String]

        XCTAssertEqual(result?["heading"], "Heading")
        XCTAssertEqual(result?["quote"], "Quoted")
        XCTAssertEqual(result?["list"], "Listed")
    }

    func testTaskItemCreatedFromMarkerAutosavesThroughBridge() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "task-item-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        _ = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            editor.focus();
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        sendWebText("[ ] Ship capture", to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return Boolean(document.querySelector('#editor .tiptap ul[data-type=taskList] li[data-checked]')) && document.querySelector('#editor .tiptap').innerText.includes('Ship capture')"
        }
        let taskDOM = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            return {
              taskList: Boolean(editor.querySelector('ul[data-type="taskList"]')),
              taskItem: Boolean(editor.querySelector('ul[data-type="taskList"] li[data-checked]')),
              checked: editor.querySelector('input[type="checkbox"]')?.checked ?? true,
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertEqual(taskDOM?["taskList"] as? Bool, true)
        XCTAssertEqual(taskDOM?["taskItem"] as? Bool, true)
        XCTAssertEqual(taskDOM?["checked"] as? Bool, false)
        let saved = try await waitForDraft(repository, id: "task-item-draft") {
            let document = String(decoding: $0.editorDocument, as: UTF8.self)
            return document.contains("taskList")
                && document.contains("taskItem")
                && document.contains("Ship capture")
        }
        XCTAssertGreaterThan(saved.revision, 1)
    }
}
