import AppKit
import Foundation
import os
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
final class CaptureWebViewToolbarTests: XCTestCase {
    func testContextualFormattingToolbarShowsActiveStateAboveSelectionAndKeepsEditorFocus() async throws {
        let session = try await makeReadyFormattingSession(
            draftID: "format-toolbar-draft",
            document: #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","marks":[{"type":"bold"}],"text":"Selected text"}]}]}"#
        )

        _ = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            const text = editor.querySelector('strong').firstChild;
            editor.focus();
            const range = document.createRange();
            range.setStart(text, 0);
            range.setEnd(text, 8);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            document.dispatchEvent(new Event('selectionchange'));
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#format-toolbar').hidden && document.querySelector('[data-format=bold]').getAttribute('aria-pressed') === 'true'"
        }
        let result = try await session.webView.callAsyncJavaScript(
            """
            const toolbar = document.querySelector('#format-toolbar');
            const italic = toolbar.querySelector('[data-format=italic]');
            const selectedBounds = window.getSelection().getRangeAt(0).getBoundingClientRect();
            const toolbarBounds = toolbar.getBoundingClientRect();
            italic.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
            italic.click();
            return {
              boldPressed: toolbar.querySelector('[data-format=bold]').getAttribute('aria-pressed'),
              italicPressed: italic.getAttribute('aria-pressed'),
              aboveSelection: toolbarBounds.bottom <= selectedBounds.top,
              activeIsEditor: document.activeElement.matches('#editor .tiptap'),
              italicApplied: Boolean(document.querySelector('#editor .tiptap em')),
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertEqual(result?["boldPressed"] as? String, "true")
        XCTAssertEqual(result?["italicPressed"] as? String, "true")
        XCTAssertEqual(result?["aboveSelection"] as? Bool, true)
        XCTAssertEqual(result?["activeIsEditor"] as? Bool, true)
        XCTAssertEqual(result?["italicApplied"] as? Bool, true)
    }

    func testFormattingToolbarSupportsKeyboardActivationAndForwardTraversal() async throws {
        let session = try await makeKeyboardFormattingSession()
        try await activateBoldWithKeyboard(in: session.webView)
        var traversal = ["bold"]
        for expected in ["italic", "underline", "strike", "code", "link"] {
            traversal.append(try await moveFormattingFocus(to: expected, in: session.webView))
        }
        XCTAssertEqual(traversal, ["bold", "italic", "underline", "strike", "code", "link"])
    }

    func testFormattingToolbarSupportsLinkActivationAndReturnToEditor() async throws {
        let session = try await makeKeyboardFormattingSession()
        try await activateBoldWithKeyboard(in: session.webView)
        for expected in ["italic", "underline", "strike", "code", "link"] {
            _ = try await moveFormattingFocus(to: expected, in: session.webView)
        }
        _ = try await session.webView.callAsyncJavaScript(
            "document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true, cancelable: true })); return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelector('[data-format=link]').getAttribute('aria-pressed') === 'true'"
        }
        let applied = try await formattingLinkState(in: session.webView)
        XCTAssertEqual(applied["toolbarVisible"] as? Bool, true)
        XCTAssertEqual(applied["boldPressed"] as? String, "true")
        XCTAssertEqual(applied["linkPressed"] as? String, "true")
        XCTAssertEqual(applied["href"] as? String, "https://example.com/keyboard")

        for expected in ["code", "strike", "underline", "italic", "bold"] {
            _ = try await moveFormattingFocus(to: expected, modifiers: .shift, in: session.webView)
        }
        sendWebKey("\t", modifiers: .shift, keyCode: 48, to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.activeElement.matches('#editor .tiptap')"
        }
        let returned = try await formattingReturnState(in: session.webView)
        XCTAssertEqual(returned["activeIsEditor"] as? Bool, true)
        XCTAssertEqual(returned["selectedText"] as? String, "Selected")
        XCTAssertEqual(returned["toolbarVisible"] as? Bool, true)
    }

    func testContextualFormattingToolbarDismissesOnEscape() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "format-escape-draft",
                title: "Formatting",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Selected text"}]}]}"#.utf8),
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

        _ = try await session.webView.callAsyncJavaScript(
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
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#format-toolbar').hidden"
        }
        sendWebKey("\u{1b}", keyCode: 53, to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelector('#format-toolbar').hidden"
        }
        let selectedText = try await session.webView.callAsyncJavaScript(
            "return window.getSelection().toString()",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String

        XCTAssertEqual(selectedText, "Selected")
    }
}
