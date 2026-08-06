import Foundation
import XCTest
import WebKit
@testable import NotionPiP

func assertEditorLocked(_ attempted: [String: Any]) {
    XCTAssertEqual(attempted["titleDisabled"] as? Bool, true)
    XCTAssertEqual(attempted["editorEditable"] as? String, "false")
}

func assertCapturedEditorAttempt(
    _ attempted: [String: Any],
    title: String,
    body: String
) {
    assertEditorLocked(attempted)
    XCTAssertEqual(attempted["title"] as? String, title)
    XCTAssertEqual(normalizedDOMText(attempted["body"] as? String), body)
}

@MainActor
func captureSuccessorState(in webView: WKWebView) async throws -> [String: Any] {
    let value = try await webView.callAsyncJavaScript(
        """
        return {
          activeID: document.activeElement.id,
          slashHidden: document.querySelector('#slash-menu').hidden,
          formatHidden: document.querySelector('#format-toolbar').hidden,
          newNoteDisabled: document.querySelector('#new-note').disabled,
          titleValue: document.querySelector('#title').value,
          titlePlaceholder: document.querySelector('#title').placeholder,
          status: document.querySelector('#status').textContent,
        };
        """,
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: Any])
}

func assertEmptyCaptureSuccessor(_ state: [String: Any]) {
    XCTAssertEqual(state["activeID"] as? String, "title")
    XCTAssertEqual(state["slashHidden"] as? Bool, true)
    XCTAssertEqual(state["formatHidden"] as? Bool, true)
    XCTAssertEqual(state["newNoteDisabled"] as? Bool, false)
    XCTAssertEqual(state["titleValue"] as? String, "")
    XCTAssertEqual(state["titlePlaceholder"] as? String, "Untitled")
    XCTAssertEqual(state["status"] as? String, "Saved")
}

@MainActor
func assertConflictCopyAndUnlockedEditor(
    repository: CaptureRepository,
    session: CaptureEditorSession
) async throws {
    let copyValue = try await repository.draft(id: "locked-copy")
    let copy = try XCTUnwrap(copyValue)
    XCTAssertEqual(copy.title, "Final captured work")
    XCTAssertTrue(String(decoding: copy.editorDocument, as: UTF8.self).contains("final captured body"))
    let unlocked = try await editorLockState(in: session.webView)
    XCTAssertEqual(unlocked["titleDisabled"] as? Bool, false)
    XCTAssertEqual(unlocked["editorEditable"] as? String, "true")
}

@MainActor
func assertStashedCaptureAndSuccessor(
    repository: CaptureRepository,
    session: CaptureEditorSession
) async throws {
    _ = try await waitForDraft(repository, id: "stash-locked-draft") {
        $0.disposition == .stashed
    }
    try await waitForJavaScriptCondition(in: session.webView) {
        "return document.querySelector('#title').value === '' && !document.querySelector('#title').disabled && document.activeElement.id === 'title'"
    }
    let successorState = try await captureSuccessorState(in: session.webView)
    let stashedValue = try await repository.draft(id: "stash-locked-draft")
    let stashed = try XCTUnwrap(stashedValue)
    XCTAssertEqual(stashed.title, "Captured before stash")
    XCTAssertTrue(String(decoding: stashed.editorDocument, as: UTF8.self).contains("captured stash body"))
    assertEmptyCaptureSuccessor(successorState)
}

@MainActor
func stashRealWebKitDraft(at storeURL: URL) async throws -> Int {
    var identifiers = ["web-draft", "next-draft"].makeIterator()
    let repository = try CaptureRepository(storeURL: storeURL)
    weak var releasedSession: CaptureEditorSession?
    var stashedRevision: Int?
    do {
        var session: CaptureEditorSession? = CaptureEditorSession(
            repository: repository,
            draftID: { identifiers.next()! }
        )
        releasedSession = session
        let liveSession = try XCTUnwrap(session)
        try await waitUntil { liveSession.status == .ready }
        let bootstrapped = try await liveSession.webView.callAsyncJavaScript(
            "return Boolean(window.NotionPiPBridge && document.querySelector('#editor .tiptap'))",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Bool
        XCTAssertEqual(bootstrapped, true)

        let edited = try await editEditor(
            title: "Real WebKit",
            body: "real webkit body",
            in: liveSession.webView
        )
        XCTAssertEqual(edited["title"], "Real WebKit")
        XCTAssertEqual(normalizedDOMText(edited["body"]), "real webkit body")
        let saved = try await waitForDraft(repository, id: "web-draft") {
            $0.revision == 2 && $0.title == "Real WebKit"
        }
        XCTAssertTrue(String(decoding: saved.editorDocument, as: UTF8.self).contains("real webkit body"))

        _ = try await liveSession.webView.callAsyncJavaScript(
            "document.querySelector('#new-note').click(); return true",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let stored = try await waitForDraft(repository, id: "web-draft") {
            $0.disposition == .stashed
        }
        XCTAssertEqual(stored.title, "Real WebKit")
        stashedRevision = stored.revision
        liveSession.dispose()
        session = nil
    }
    XCTAssertNil(releasedSession)
    return try XCTUnwrap(stashedRevision)
}
