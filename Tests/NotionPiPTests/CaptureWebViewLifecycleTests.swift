import AppKit
import Foundation
import os
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
final class CaptureWebViewLifecycleTests: XCTestCase {
    func testDisposeStopsLoadingTearsDownBridgeAndDoesNotRetainSession() async throws {
        weak var weakSession: CaptureEditorSession?
        var session: CaptureEditorSession? = CaptureEditorSession(
            repository: try CaptureRepository(inMemory: true)
        )
        let webView = try XCTUnwrap(session?.webView)
        weakSession = session

        session?.dispose()
        session?.dispose()

        XCTAssertEqual(session?.installedHandlerNames, [])
        XCTAssertNil(webView.navigationDelegate)
        XCTAssertNil(webView.uiDelegate)
        try await waitUntil { !webView.isLoading }

        session = nil

        XCTAssertNil(weakSession)
    }

    func testTerminationFlushPersistsEditInsideDebounceWindowAndReopensLatestContent() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "termination-debounce-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }
        _ = try await editEditor(
            title: "Newest title",
            body: "Newest body",
            in: session.webView
        )

        let shouldTerminate = await session.prepareForTermination()

        XCTAssertTrue(shouldTerminate)
        session.tearDownBridge()
        let reopened = CaptureEditorSession(repository: repository)
        try await waitUntil { reopened.status == .ready }
        try await waitForJavaScriptCondition(in: reopened.webView) {
            "return !document.querySelector('#title').disabled"
        }
        let reopenedContent = try await editorDOM(in: reopened.webView)
        XCTAssertEqual(reopenedContent["title"], "Newest title")
        XCTAssertEqual(normalizedDOMText(reopenedContent["body"]), "Newest body")
    }

    func testTerminationFlushCompletesWhileAutosaveIsInFlight() async throws {
        let gate = BlockingBridgeRequestGate { request in
            if case .changed = request { return true }
            return false
        }
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "termination-inflight-draft" },
            beforeBridgeRequest: { request in await gate.suspendIfMatched(request) }
        )
        try await waitUntil { session.status == .ready }
        _ = try await editEditor(
            title: "In-flight title",
            body: "In-flight body",
            in: session.webView
        )
        try await waitUntil { gate.entered }

        let termination = Task { @MainActor in
            await session.prepareForTermination()
        }
        let persisted = try await waitForDraft(
            repository,
            id: "termination-inflight-draft"
        ) {
            $0.title == "In-flight title"
                && String(decoding: $0.editorDocument, as: UTF8.self)
                    .contains("In-flight body")
        }
        gate.resume()

        let shouldTerminate = await termination.value
        XCTAssertTrue(shouldTerminate)
        XCTAssertGreaterThan(persisted.revision, 1)
    }

    func testTerminationPersistenceFailureCancelsQuitAndKeepsPreviousDraft() async throws {
        let failure = WebViewCaptureSaveFailure()
        let repository = try CaptureRepository(
            inMemory: true,
            beforeSave: failure.check
        )
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "termination-failure-draft" }
        )
        try await waitUntil { session.status == .ready }
        _ = try await editEditor(
            title: "Unsaved title",
            body: "Unsaved body",
            in: session.webView
        )
        failure.failNext(.draftMutation)

        let shouldTerminate = await session.prepareForTermination()
        session.tearDownBridge()

        let stored = try await repository.draft(id: "termination-failure-draft")
        XCTAssertFalse(shouldTerminate)
        XCTAssertEqual(stored?.title, "")
        XCTAssertEqual(
            session.status,
            .failed("Could not save the latest draft before quitting.")
        )
    }

    func testNewNoteFlushesEditsLocksMutationAndFocusesEmptySuccessor() async throws {
        let gate = BlockingBridgeRequestGate { request in
            if case .stash = request { return true }
            return false
        }
        var identifiers = ["stash-locked-draft", "stash-next-draft"].makeIterator()
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { identifiers.next()! },
            beforeBridgeRequest: { request in await gate.suspendIfMatched(request) }
        )
        try await waitUntil { session.status == .ready }
        _ = try await editEditor(
            title: "Captured before stash",
            body: "captured stash body",
            in: session.webView
        )
        _ = try await session.webView.callAsyncJavaScript(
            """
            document.querySelector('#slash-menu').hidden = false;
            document.querySelector('#format-toolbar').hidden = false;
            document.querySelector('#new-note').click();
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil { gate.entered }
        let flushedBeforeStashValue = try await repository.draft(id: "stash-locked-draft")
        let flushedBeforeStash = try XCTUnwrap(flushedBeforeStashValue)
        XCTAssertEqual(flushedBeforeStash.title, "Captured before stash")
        XCTAssertTrue(
            String(decoding: flushedBeforeStash.editorDocument, as: UTF8.self)
                .contains("captured stash body")
        )
        XCTAssertEqual(flushedBeforeStash.disposition, .active)
        let attempted = try await attemptUserEditorInput(
            title: "Must not replace stashed capture",
            body: "must not replace stash body",
            in: session.webView
        )

        assertEditorLocked(attempted)
        let controls = try await editorLockState(in: session.webView)
        XCTAssertEqual(controls["newNoteDisabled"] as? Bool, true)
        XCTAssertEqual(controls["toolbarDisabled"] as? Bool, true)
        gate.resume()
        try await assertStashedCaptureAndSuccessor(repository: repository, session: session)
    }

    func testRestoreDrainsQueuedOldDraftEditBeforeSwitchingSnapshots() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "restore-target",
                title: "Stashed target",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"target body"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .stashed
            ),
            expectedRevision: 0
        )
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "old-active-draft" }
        )
        try await waitUntil { session.status == .ready }
        _ = try await editEditor(
            title: "Queued old draft edit",
            body: "queued old draft body",
            in: session.webView
        )

        let restoredValue = try await session.webView.callAsyncJavaScript(
            "return await window.NotionPiPBridge.restore(draftID, expectedRevision)",
            arguments: ["draftID": "restore-target", "expectedRevision": 1],
            in: nil,
            contentWorld: .page
        )
        let restoredReply = try XCTUnwrap(restoredValue as? [String: Any])

        XCTAssertEqual(restoredReply["ok"] as? Bool, true, "\(restoredReply)")
        let oldDraftValue = try await repository.draft(id: "old-active-draft")
        let oldDraft = try XCTUnwrap(oldDraftValue)
        XCTAssertEqual(oldDraft.title, "Queued old draft edit")
        XCTAssertTrue(String(decoding: oldDraft.editorDocument, as: UTF8.self).contains("queued old draft body"))
        XCTAssertEqual(oldDraft.disposition, .stashed)
        let targetValue = try await repository.draft(id: "restore-target")
        let target = try XCTUnwrap(targetValue)
        XCTAssertEqual(target.disposition, .active)
        let installed = try await editorDOM(in: session.webView)
        XCTAssertEqual(installed["title"], "Stashed target")
        XCTAssertEqual(normalizedDOMText(installed["body"]), "target body")
    }
}
