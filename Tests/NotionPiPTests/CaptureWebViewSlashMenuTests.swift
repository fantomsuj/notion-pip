import AppKit
import Foundation
import os
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
final class CaptureWebViewSlashMenuTests: XCTestCase {
    func testSlashMenuFiltersHeadingsAndKeyboardSelectionProducesHeadingTwo() async throws {
        let session = try await makeSlashMenuSession(draftID: "slash-heading-draft")

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
        sendWebText("/hea", to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#slash-menu').hidden && document.querySelectorAll('#slash-menu [role=option]').length === 3"
        }
        let opened = try await slashMenuAccessibilityState(in: session.webView)
        sendWebKey("\u{F701}", keyCode: 125, to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelector('#editor .tiptap').getAttribute('aria-activedescendant') === 'slash-option-heading2'"
        }
        sendWebKey("\r", keyCode: 36, to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return Boolean(document.querySelector('#editor .tiptap h2')) && document.querySelector('#slash-menu').hidden"
        }
        let selected = try await selectedSlashHeadingState(in: session.webView)

        XCTAssertEqual(opened["labels"] as? String, "Heading 1|Heading 2|Heading 3")
        XCTAssertEqual(opened["active"] as? String, "slash-option-heading1")
        XCTAssertEqual(opened["menuActive"] as? String, "slash-option-heading1")
        XCTAssertEqual(opened["role"] as? String, "listbox")
        XCTAssertEqual(selected["headingTwo"] as? Bool, true)
        XCTAssertEqual(normalizedDOMText(selected["body"] as? String), "")
        XCTAssertEqual(selected["closed"] as? Bool, true)
    }

    func testSlashMenuKeepsFinalKeyboardOptionVisible() async throws {
        let session = try await makeSlashMenuSession(
            draftID: "slash-scroll-draft",
            frame: NSRect(x: 0, y: 0, width: 480, height: 600)
        )

        _ = try await session.webView.callAsyncJavaScript(
            """
            document.querySelector('#editor .tiptap').focus();
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        sendWebText("/", to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelectorAll('#slash-menu [role=option]').length === 10"
        }

        for commandID in [
            "heading1", "heading2", "heading3", "bulletList", "orderedList",
            "taskList", "quote", "codeBlock", "divider",
        ] {
            sendWebKey("\u{F701}", keyCode: 125, to: session.webView)
            try await waitForJavaScriptCondition(in: session.webView) {
                "return document.querySelector('#slash-menu').getAttribute('aria-activedescendant') === 'slash-option-\(commandID)'"
            }
        }

        let visibility = try await slashMenuScrollState(in: session.webView)

        XCTAssertEqual(visibility["activeID"] as? String, "slash-option-divider")
        XCTAssertEqual(visibility["visible"] as? Bool, true, "\(visibility)")
        XCTAssertGreaterThan(visibility["scrollTop"] as? Double ?? 0, 0)
    }

    func testSlashMenuEscapeDismissesWithoutDeletingQueryText() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "slash-escape-draft" }
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
        sendWebText("/hea", to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#slash-menu').hidden && document.querySelector('#editor .tiptap').innerText.trim() === '/hea'"
        }
        sendWebKey("\u{1b}", keyCode: 53, to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelector('#slash-menu').hidden"
        }
        let result = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            const menu = document.querySelector('#slash-menu');
            return {
              closed: menu.hidden,
              body: editor.innerText,
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertEqual(result?["closed"] as? Bool, true)
        XCTAssertEqual(normalizedDOMText(result?["body"] as? String), "/hea")
    }
}
