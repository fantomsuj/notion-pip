import AppKit
import Foundation
import os
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
final class CaptureWebViewFocusTests: XCTestCase {
    func testEmptyAuthoritativeDraftFocusesTitleAndExposesAccessibleBody() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "empty-focus-draft" }
        )

        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }
        let state = try await focusState(in: session.webView)

        let lifecycle = try await session.webView.callAsyncJavaScript(
            """
            const title = document.querySelector('#title');
            return {
              hasSave: Boolean(document.querySelector('#save')),
              newNoteDisabled: document.querySelector('#new-note').disabled,
              statusRegionCount: document.querySelectorAll('[role=status]').length,
              status: document.querySelector('#status').textContent,
              titleValue: title.value,
              titlePlaceholder: title.placeholder,
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertEqual(state["activeID"], "title")
        XCTAssertEqual(state["role"], "textbox")
        XCTAssertEqual(state["ariaLabel"], "Note content")
        XCTAssertEqual(state["ariaMultiline"], "true")
        XCTAssertEqual(lifecycle?["hasSave"] as? Bool, false)
        XCTAssertEqual(lifecycle?["newNoteDisabled"] as? Bool, false)
        XCTAssertEqual(lifecycle?["statusRegionCount"] as? Int, 1)
        XCTAssertEqual(lifecycle?["status"] as? String, "Saved")
        XCTAssertEqual(lifecycle?["titleValue"] as? String, "")
        XCTAssertEqual(lifecycle?["titlePlaceholder"] as? String, "Untitled")
    }

    func testPopulatedAuthoritativeDraftFocusesBodyAtItsEnd() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "populated-focus-draft",
                title: "Existing note",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Continue here"}]}]}"#.utf8),
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
        let state = try await focusState(in: session.webView)

        XCTAssertEqual(state["activeIsEditor"], "true")
        XCTAssertEqual(state["body"], "Continue here")
        XCTAssertEqual(state["textBeforeCaret"], "Continue here")
    }

    func testNewerSnapshotForSameDraftPreservesCurrentFocus() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "same-draft-focus",
                title: "Existing note",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Existing body"}]}]}"#.utf8),
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
            const title = document.querySelector('#title');
            title.focus();
            window.NotionPiPBridge.applyNativeReply({
              version: 1,
              id: 'same-draft-refresh',
              ok: true,
              result: {
                kind: 'restored',
                revision: 2,
                snapshot: {
                  draftID: 'same-draft-focus',
                  title: 'Refreshed note',
                  document: {
                    type: 'doc',
                    content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Refreshed body' }] }],
                  },
                  revision: 2,
                },
              },
            });
            return { activeID: document.activeElement.id, title: title.value };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: String]

        XCTAssertEqual(result?["activeID"], "title")
        XCTAssertEqual(result?["title"], "Refreshed note")
    }
}
