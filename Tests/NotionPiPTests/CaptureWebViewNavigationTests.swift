import AppKit
import Foundation
import os
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
final class CaptureWebViewNavigationTests: XCTestCase {
    func testTitleNavigationKeysMoveFocusIntoBody() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "title-key-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        for key in ["Enter", "Tab", "ArrowDown"] {
            let activeIsEditor = try await session.webView.callAsyncJavaScript(
                """
                const title = document.querySelector('#title');
                title.focus();
                title.setSelectionRange(title.value.length, title.value.length);
                title.dispatchEvent(new KeyboardEvent('keydown', { key: pressedKey, bubbles: true }));
                return document.activeElement.matches('#editor .tiptap');
                """,
                arguments: ["pressedKey": key],
                in: nil,
                contentWorld: .page
            ) as? Bool
            XCTAssertEqual(activeIsEditor, true, "Expected \(key) to focus the body")
        }
    }

    func testComposingTitleEnterIsNotPreventedAndDoesNotMoveFocus() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "composing-title-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        let result = try await session.webView.callAsyncJavaScript(
            """
            const title = document.querySelector('#title');
            title.focus();
            const allowed = title.dispatchEvent(new KeyboardEvent('keydown', {
              key: 'Enter',
              isComposing: true,
              keyCode: 229,
              bubbles: true,
              cancelable: true,
            }));
            return {
              activeIsTitle: document.activeElement === title,
              defaultPrevented: !allowed,
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Bool]

        XCTAssertEqual(result?["activeIsTitle"], true)
        XCTAssertEqual(result?["defaultPrevented"], false)
    }

    func testShiftTabInTitlePreservesReverseFocusTraversal() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "reverse-title-key-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        let result = try await session.webView.callAsyncJavaScript(
            """
            const title = document.querySelector('#title');
            title.focus();
            const allowed = title.dispatchEvent(new KeyboardEvent('keydown', {
              key: 'Tab',
              shiftKey: true,
              bubbles: true,
              cancelable: true,
            }));
            return {
              activeIsTitle: document.activeElement === title,
              defaultPrevented: !allowed,
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Bool]

        XCTAssertEqual(result?["activeIsTitle"], true)
        XCTAssertEqual(result?["defaultPrevented"], false)
    }

    func testArrowUpAtStartOfBodyReturnsFocusToTitle() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "body-key-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        let activeID = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            editor.focus();
            const selection = window.getSelection();
            const range = document.createRange();
            range.setStart(editor.firstChild, 0);
            range.collapse(true);
            selection.removeAllRanges();
            selection.addRange(range);
            editor.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));
            return document.activeElement.id;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String

        XCTAssertEqual(activeID, "title")
    }

    func testArrowUpAtStartOfNestedFirstBlockReturnsFocusToTitle() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "nested-body-key-draft",
                title: "Nested first block",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"Nested body"}]}]}]}"#.utf8),
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

        let activeID = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            const text = editor.querySelector('blockquote p').firstChild;
            editor.focus();
            const selection = window.getSelection();
            const range = document.createRange();
            range.setStart(text, 0);
            range.collapse(true);
            selection.removeAllRanges();
            selection.addRange(range);
            editor.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));
            return document.activeElement.id;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String

        XCTAssertEqual(activeID, "title")
    }
}
