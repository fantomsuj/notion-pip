import AppKit
import Foundation
import os
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
func makeReadyFormattingSession(
    draftID: String,
    document: String
) async throws -> CaptureEditorSession {
    let repository = try CaptureRepository(inMemory: true)
    _ = try await repository.saveDraft(
        DraftMutation(
            id: draftID,
            title: "Formatting",
            editorDocument: Data(document.utf8),
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
    return session
}

@MainActor
func makeKeyboardFormattingSession() async throws -> CaptureEditorSession {
    let session = try await makeReadyFormattingSession(
        draftID: "format-keyboard-draft",
        document: #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Selected text"}]}]}"#
    )
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
        window.prompt = () => 'https://example.com/keyboard';
        return true;
        """,
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    try await waitForJavaScriptCondition(in: session.webView) {
        "return !document.querySelector('#format-toolbar').hidden"
    }
    return session
}

@MainActor
func moveFormattingFocus(
    to expected: String,
    modifiers: NSEvent.ModifierFlags = [],
    in webView: WKWebView
) async throws -> String {
    sendWebKey("\t", modifiers: modifiers, keyCode: 48, to: webView)
    try await waitForJavaScriptCondition(in: webView) {
        "return document.activeElement.dataset.format === '\(expected)'"
    }
    let value = try await webView.callAsyncJavaScript(
        "return document.activeElement.dataset.format || ''",
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? String)
}

@MainActor
func activateBoldWithKeyboard(in webView: WKWebView) async throws {
    _ = try await moveFormattingFocus(to: "bold", in: webView)
    _ = try await webView.callAsyncJavaScript(
        "document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', code: 'Space', keyCode: 32, bubbles: true, cancelable: true })); return true;",
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    try await waitForJavaScriptCondition(in: webView) {
        "return document.querySelector('[data-format=bold]').getAttribute('aria-pressed') === 'true'"
    }
}

@MainActor
func formattingLinkState(in webView: WKWebView) async throws -> [String: Any] {
    let value = try await webView.callAsyncJavaScript(
        """
        return {
          toolbarVisible: !document.querySelector('#format-toolbar').hidden,
          boldPressed: document.querySelector('[data-format=bold]').getAttribute('aria-pressed'),
          linkPressed: document.querySelector('[data-format=link]').getAttribute('aria-pressed'),
          href: document.querySelector('#editor .tiptap a')?.getAttribute('href') || '',
        };
        """,
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: Any])
}

@MainActor
func formattingReturnState(in webView: WKWebView) async throws -> [String: Any] {
    let value = try await webView.callAsyncJavaScript(
        """
        return {
          activeIsEditor: document.activeElement.matches('#editor .tiptap'),
          selectedText: window.getSelection().toString(),
          toolbarVisible: !document.querySelector('#format-toolbar').hidden,
        };
        """,
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: Any])
}
