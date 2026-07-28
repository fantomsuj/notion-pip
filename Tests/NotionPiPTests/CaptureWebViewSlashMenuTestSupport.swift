import AppKit
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
func makeSlashMenuSession(
    draftID: String,
    frame: NSRect? = nil
) async throws -> CaptureEditorSession {
    let repository = try CaptureRepository(inMemory: true)
    let session = CaptureEditorSession(
        repository: repository,
        draftID: { draftID }
    )
    if let frame {
        session.webView.frame = frame
    }
    try await waitUntil { session.status == .ready }
    try await waitForJavaScriptCondition(in: session.webView) {
        "return !document.querySelector('#title').disabled"
    }
    return session
}

@MainActor
func slashMenuAccessibilityState(in webView: WKWebView) async throws -> [String: Any] {
    let value = try await webView.callAsyncJavaScript(
        """
        const editor = document.querySelector('#editor .tiptap');
        const menu = document.querySelector('#slash-menu');
        const options = Array.from(menu.querySelectorAll('[role="option"]'));
        return {
          labels: options.map((option) => option.textContent.trim()).join('|'),
          active: editor.getAttribute('aria-activedescendant') || '',
          menuActive: menu.getAttribute('aria-activedescendant') || '',
          role: menu.getAttribute('role') || '',
        };
        """,
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: Any])
}

@MainActor
func selectedSlashHeadingState(in webView: WKWebView) async throws -> [String: Any] {
    let value = try await webView.callAsyncJavaScript(
        """
        const editor = document.querySelector('#editor .tiptap');
        return {
          headingTwo: Boolean(editor.querySelector('h2')),
          body: editor.innerText,
          closed: document.querySelector('#slash-menu').hidden,
        };
        """,
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: Any])
}

@MainActor
func slashMenuScrollState(in webView: WKWebView) async throws -> [String: Any] {
    let value = try await webView.callAsyncJavaScript(
        """
        const menu = document.querySelector('#slash-menu');
        const active = document.querySelector('#' + menu.getAttribute('aria-activedescendant'));
        const menuBounds = menu.getBoundingClientRect();
        const activeBounds = active.getBoundingClientRect();
        return {
          activeID: active.id,
          visible: activeBounds.top >= menuBounds.top - 1
            && activeBounds.bottom <= menuBounds.bottom + 1,
          scrollTop: menu.scrollTop,
        };
        """,
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: Any])
}
