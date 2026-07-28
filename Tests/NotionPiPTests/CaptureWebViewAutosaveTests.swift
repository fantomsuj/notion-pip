import AppKit
import Foundation
import os
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
final class CaptureWebViewAutosaveTests: XCTestCase {
    func testTitleOnlyEditAnnouncesSavingThenSavedAfterAcknowledgement() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "title-status-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        let immediateStatus = try await session.webView.callAsyncJavaScript(
            """
            const title = document.querySelector('#title');
            title.value = 'Title only';
            title.dispatchEvent(new Event('input', { bubbles: true }));
            return document.querySelector('#status').textContent;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String

        XCTAssertEqual(immediateStatus, "Saving…")
        _ = try await waitForDraft(repository, id: "title-status-draft") {
            $0.title == "Title only"
        }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelector('#status').textContent === 'Saved'"
        }
    }

    func testEditorRemainsLockedUntilDelayedReadyInstallsAuthoritativeDraft() async throws {
        let gate = BlockingBridgeRequestGate { request in
            if case .ready = request { return true }
            return false
        }
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "ready-locked-draft" },
            beforeBridgeRequest: { request in await gate.suspendIfMatched(request) }
        )
        try await waitUntil { gate.entered }

        let attempted = try await attemptUserEditorInput(
            title: "Must not be accepted before ready",
            body: "early body",
            in: session.webView
        )

        XCTAssertEqual(attempted["titleDisabled"] as? Bool, true)
        XCTAssertEqual(attempted["editorEditable"] as? String, "false")
        XCTAssertEqual(attempted["title"] as? String, "")
        XCTAssertEqual(normalizedDOMText(attempted["body"] as? String), "")
        let controls = try await editorLockState(in: session.webView)
        XCTAssertEqual(controls["newNoteDisabled"] as? Bool, true)
        XCTAssertEqual(controls["toolbarDisabled"] as? Bool, true)
        gate.resume()
        try await waitUntil { session.status == .ready }
        let unlocked = try await editorLockState(in: session.webView)
        XCTAssertEqual(unlocked["titleDisabled"] as? Bool, false)
        XCTAssertEqual(unlocked["editorEditable"] as? String, "true")
    }

    func testAutosavePersistenceFailureShowsRetryAndPersistsExactEditAfterRetry() async throws {
        let failure = WebViewCaptureRepositoryFailure()
        let requests = WebViewBridgeRequestRecorder()
        let repository = try CaptureRepository(
            inMemory: true,
            beforeHelperFetch: failure.check
        )
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "autosave-retry-draft" },
            beforeBridgeRequest: { request in await requests.append(request) }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }
        failure.failNext(.otherActiveDrafts)

        _ = try await session.webView.callAsyncJavaScript(
            """
            const title = document.querySelector('#title');
            title.value = 'Exact retry edit';
            title.dispatchEvent(new Event('input', { bubbles: true }));
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#retry').hidden"
        }
        let failedDraft = try await repository.draft(id: "autosave-retry-draft")
        XCTAssertEqual(failedDraft?.title, "")

        _ = try await session.webView.callAsyncJavaScript(
            "document.querySelector('#retry').click(); return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let saved = try await waitForDraft(repository, id: "autosave-retry-draft") {
            $0.title == "Exact retry edit"
        }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelector('#retry').hidden && document.querySelector('#status').textContent === 'Saved'"
        }
        let changedRequests = await requests.changedRequests()

        XCTAssertEqual(saved.title, "Exact retry edit")
        XCTAssertEqual(changedRequests.count, 2)
        XCTAssertEqual(changedRequests[0], changedRequests[1])
    }
}
