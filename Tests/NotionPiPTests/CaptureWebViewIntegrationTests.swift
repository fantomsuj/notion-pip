import Foundation
import WebKit
import XCTest
@testable import NotionPiP

@MainActor
final class CaptureWebViewIntegrationTests: XCTestCase {
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
        XCTAssertEqual(controls["saveDisabled"] as? Bool, true)
        XCTAssertEqual(controls["stashDisabled"] as? Bool, true)
        XCTAssertEqual(controls["toolbarDisabled"] as? Bool, true)
        gate.resume()
        try await waitUntil { session.status == .ready }
        let unlocked = try await editorLockState(in: session.webView)
        XCTAssertEqual(unlocked["titleDisabled"] as? Bool, false)
        XCTAssertEqual(unlocked["editorEditable"] as? String, "true")
    }

    func testStashLocksEveryMutationControlUntilNewDraftSnapshotIsApplied() async throws {
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
        _ = try await waitForDraft(repository, id: "stash-locked-draft") {
            $0.title == "Captured before stash"
        }

        _ = try await session.webView.callAsyncJavaScript(
            "document.querySelector('#stash').click(); return true",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil { gate.entered }
        let attempted = try await attemptUserEditorInput(
            title: "Must not replace stashed capture",
            body: "must not replace stash body",
            in: session.webView
        )

        XCTAssertEqual(attempted["titleDisabled"] as? Bool, true)
        XCTAssertEqual(attempted["editorEditable"] as? String, "false")
        let controls = try await editorLockState(in: session.webView)
        XCTAssertEqual(controls["saveDisabled"] as? Bool, true)
        XCTAssertEqual(controls["stashDisabled"] as? Bool, true)
        XCTAssertEqual(controls["toolbarDisabled"] as? Bool, true)
        gate.resume()
        _ = try await waitForDraft(repository, id: "stash-locked-draft") {
            $0.disposition == .stashed
        }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelector('#title').value === '' && !document.querySelector('#title').disabled"
        }
        let stashedValue = try await repository.draft(id: "stash-locked-draft")
        let stashed = try XCTUnwrap(stashedValue)
        XCTAssertEqual(stashed.title, "Captured before stash")
        XCTAssertTrue(String(decoding: stashed.editorDocument, as: UTF8.self).contains("captured stash body"))
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

    func testOlderSameDraftSnapshotCannotReplaceNewerLiveDOM() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "monotonic-draft" }
        )
        try await waitUntil { session.status == .ready }
        _ = try await editEditor(
            title: "Newer live title",
            body: "newer live body",
            in: session.webView
        )
        _ = try await waitForDraft(repository, id: "monotonic-draft") {
            $0.revision == 2 && $0.title == "Newer live title"
        }

        let applied = try await session.webView.callAsyncJavaScript(
            """
            return window.NotionPiPBridge.applyNativeReply({
              version: 1,
              id: 'older-snapshot',
              ok: true,
              result: {
                kind: 'restored',
                revision: 1,
                snapshot: {
                  draftID: 'monotonic-draft',
                  title: 'Older title',
                  document: {
                    type: 'doc',
                    content: [{ type: 'paragraph', content: [{ type: 'text', text: 'older body' }] }],
                  },
                  revision: 1,
                },
              },
            });
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Bool
        let installed = try await editorDOM(in: session.webView)

        XCTAssertEqual(applied, true)
        XCTAssertEqual(installed["title"], "Newer live title")
        XCTAssertEqual(normalizedDOMText(installed["body"]), "newer live body")
    }

    func testBundledEditorRunsRealReplyBridgeAndRestoresStashedContentAfterRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("WebKitCapture.store")
        var stashedRevision: Int?

        weak var releasedSession: CaptureEditorSession?
        do {
            var identifiers = ["web-draft", "next-draft"].makeIterator()
            let repository = try CaptureRepository(storeURL: storeURL)
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

            let edited = try await liveSession.webView.callAsyncJavaScript(
                """
                const title = document.querySelector('#title');
                const editor = document.querySelector('#editor .tiptap');
                title.value = newTitle;
                title.dispatchEvent(new Event('input', { bubbles: true }));
                editor.focus();
                const range = document.createRange();
                range.selectNodeContents(editor);
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
                document.execCommand('insertText', false, newBody);
                return { title: title.value, body: editor.innerText };
                """,
                arguments: ["newTitle": "Real WebKit", "newBody": "real webkit body"],
                in: nil,
                contentWorld: .page
            ) as? [String: String]
            XCTAssertEqual(edited?["title"], "Real WebKit")
            XCTAssertEqual(normalizedDOMText(edited?["body"]), "real webkit body")

            let saved = try await waitForDraft(repository, id: "web-draft") {
                $0.revision == 2 && $0.title == "Real WebKit"
            }
            XCTAssertTrue(String(decoding: saved.editorDocument, as: UTF8.self).contains("real webkit body"))

            _ = try await liveSession.webView.callAsyncJavaScript(
                "document.querySelector('#save').click(); return true",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            try await waitForJavaScriptCondition(in: liveSession.webView) {
                "return !document.querySelector('#save').disabled && !document.querySelector('#stash').disabled"
            }
            _ = try await liveSession.webView.callAsyncJavaScript(
                "document.querySelector('#stash').click(); return true",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            let stored = try await waitForDraft(repository, id: "web-draft") {
                $0.disposition == .stashed
            }
            XCTAssertEqual(stored.disposition, .stashed)
            XCTAssertEqual(stored.title, "Real WebKit")
            stashedRevision = stored.revision

            session?.tearDownBridge()
            session = nil
        }
        XCTAssertNil(releasedSession)

        let reopened = try CaptureRepository(storeURL: storeURL)
        let relaunched = CaptureEditorSession(repository: reopened, draftID: { "unused" })
        try await waitUntil { relaunched.status == .ready }
        let expectedRevision = try XCTUnwrap(stashedRevision)
        let restoreValue = try await relaunched.webView.callAsyncJavaScript(
            "return await window.NotionPiPBridge.restore(draftID, expectedRevision)",
            arguments: ["draftID": "web-draft", "expectedRevision": expectedRevision],
            in: nil,
            contentWorld: .page
        )
        let restoreReply = try XCTUnwrap(restoreValue as? [String: Any])
        XCTAssertEqual(restoreReply["ok"] as? Bool, true, "\(restoreReply)")
        let result = try XCTUnwrap(restoreReply["result"] as? [String: Any])
        let restored = try XCTUnwrap(result["snapshot"] as? [String: Any])

        XCTAssertEqual(restored["title"] as? String, "Real WebKit")
        XCTAssertEqual(restored["revision"] as? Int, expectedRevision + 1)
        let document = try XCTUnwrap(restored["document"] as? [String: Any])
        let content = try XCTUnwrap(document["content"] as? [[String: Any]])
        let paragraph = try XCTUnwrap(content.first)
        let textNodes = try XCTUnwrap(paragraph["content"] as? [[String: Any]])
        XCTAssertEqual(textNodes.first?["text"] as? String, "real webkit body")
        let restoredDOM = try await relaunched.webView.callAsyncJavaScript(
            "return { title: document.querySelector('#title').value, body: document.querySelector('#editor .tiptap').innerText }",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: String]
        XCTAssertEqual(restoredDOM?["title"], "Real WebKit")
        XCTAssertEqual(normalizedDOMText(restoredDOM?["body"]), "real webkit body")
    }

    func testNativeSaveAsNewCapturesNewestUnsentTiptapDocument() async throws {
        var identifiers = ["conflict-draft", "conflict-copy"].makeIterator()
        let repository = try CaptureRepository(
            inMemory: true,
            clock: TestCaptureClock(Date(timeIntervalSince1970: 1_700_000_000))
        )
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { identifiers.next()! }
        )
        try await waitUntil { session.status == .ready }
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "conflict-draft",
                title: "Native latest",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"native"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 1
        )

        let staleDOM = try await editEditor(
            title: "Cached conflict work",
            body: "cached conflict body",
            in: session.webView
        )
        XCTAssertEqual(normalizedDOMText(staleDOM["body"]), "cached conflict body")
        try await waitUntil { session.conflict != nil }

        let newestDOM = try await editEditor(
            title: "Newest unsent JS work",
            body: "newest unsent JS body",
            in: session.webView
        )
        XCTAssertEqual(normalizedDOMText(newestDOM["body"]), "newest unsent JS body")

        await session.resolve(.saveAsNew)

        XCTAssertNil(session.conflict)
        let copyValue = try await repository.draft(id: "conflict-copy")
        let copy = try XCTUnwrap(copyValue)
        XCTAssertEqual(copy.title, "Newest unsent JS work")
        XCTAssertTrue(String(decoding: copy.editorDocument, as: UTF8.self).contains("newest unsent JS body"))
        let installed = try await editorDOM(in: session.webView)
        XCTAssertEqual(installed["title"], "Newest unsent JS work")
        XCTAssertEqual(normalizedDOMText(installed["body"]), "newest unsent JS body")
    }

    func testConflictRecoveryLocksRealEditorWhileNativeReplyIsInFlight() async throws {
        var identifiers = ["locked-draft", "locked-copy"].makeIterator()
        let gate = BlockingConflictResolutionGate()
        let repository = try CaptureRepository(
            inMemory: true,
            clock: TestCaptureClock(Date(timeIntervalSince1970: 1_700_000_000))
        )
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { identifiers.next()! },
            beforeConflictResolution: { _ in await gate.suspend() }
        )
        try await waitUntil { session.status == .ready }
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "locked-draft",
                title: "Native latest",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"native"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 1
        )
        _ = try await editEditor(
            title: "Initial conflict",
            body: "initial conflict body",
            in: session.webView
        )
        try await waitUntil { session.conflict != nil }
        _ = try await editEditor(
            title: "Final captured work",
            body: "final captured body",
            in: session.webView
        )

        let resolution = Task { await session.resolve(.saveAsNew) }
        try await waitUntil { gate.entered }
        let attempted = try await attemptUserEditorInput(
            title: "Must not replace capture",
            body: "must not replace body",
            in: session.webView
        )

        XCTAssertEqual(attempted["titleDisabled"] as? Bool, true)
        XCTAssertEqual(attempted["editorEditable"] as? String, "false")
        XCTAssertEqual(attempted["title"] as? String, "Final captured work")
        XCTAssertEqual(
            normalizedDOMText(attempted["body"] as? String),
            "final captured body"
        )

        gate.resume()
        await resolution.value

        let copyValue = try await repository.draft(id: "locked-copy")
        let copy = try XCTUnwrap(copyValue)
        XCTAssertEqual(copy.title, "Final captured work")
        XCTAssertTrue(String(decoding: copy.editorDocument, as: UTF8.self).contains("final captured body"))
        let unlocked = try await editorLockState(in: session.webView)
        XCTAssertEqual(unlocked["titleDisabled"] as? Bool, false)
        XCTAssertEqual(unlocked["editorEditable"] as? String, "true")
    }

}

@MainActor
private func editEditor(title: String, body: String, in webView: WKWebView) async throws -> [String: String] {
    let value = try await webView.callAsyncJavaScript(
        """
        const title = document.querySelector('#title');
        const editor = document.querySelector('#editor .tiptap');
        title.value = newTitle;
        title.dispatchEvent(new Event('input', { bubbles: true }));
        editor.focus();
        const range = document.createRange();
        range.selectNodeContents(editor);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        document.execCommand('insertText', false, newBody);
        return { title: title.value, body: editor.innerText };
        """,
        arguments: ["newTitle": title, "newBody": body],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: String])
}

@MainActor
private func editorDOM(in webView: WKWebView) async throws -> [String: String] {
    let value = try await webView.callAsyncJavaScript(
        "return { title: document.querySelector('#title').value, body: document.querySelector('#editor .tiptap').innerText }",
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: String])
}

@MainActor
private func attemptUserEditorInput(
    title: String,
    body: String,
    in webView: WKWebView
) async throws -> [String: Any] {
    let value = try await webView.callAsyncJavaScript(
        """
        const title = document.querySelector('#title');
        const editor = document.querySelector('#editor .tiptap');
        title.focus();
        title.select();
        document.execCommand('insertText', false, attemptedTitle);
        editor.focus();
        const range = document.createRange();
        range.selectNodeContents(editor);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        document.execCommand('insertText', false, attemptedBody);
        return {
          titleDisabled: title.disabled,
          editorEditable: editor.getAttribute('contenteditable'),
          title: title.value,
          body: editor.innerText,
        };
        """,
        arguments: ["attemptedTitle": title, "attemptedBody": body],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: Any])
}

@MainActor
private func editorLockState(in webView: WKWebView) async throws -> [String: Any] {
    let value = try await webView.callAsyncJavaScript(
        """
        const title = document.querySelector('#title');
        const editor = document.querySelector('#editor .tiptap');
        return {
          titleDisabled: title.disabled,
          editorEditable: editor.getAttribute('contenteditable'),
          saveDisabled: document.querySelector('#save').disabled,
          stashDisabled: document.querySelector('#stash').disabled,
          toolbarDisabled: Array.from(document.querySelectorAll('[data-command]')).every((button) => button.disabled),
        };
        """,
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: Any])
}

@MainActor
private func waitForDraft(
    _ repository: CaptureRepository,
    id: String,
    timeout: Duration = .seconds(5),
    condition: (CaptureDraftSnapshot) -> Bool
) async throws -> CaptureDraftSnapshot {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if let draft = try await repository.draft(id: id), condition(draft) {
            return draft
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw CaptureWebViewIntegrationError.timeout
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(5),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            throw CaptureWebViewIntegrationError.timeout
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
private func waitForJavaScriptCondition(
    in webView: WKWebView,
    timeout: Duration = .seconds(5),
    expression: () -> String
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        let value = try await webView.callAsyncJavaScript(
            expression(),
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Bool
        if value == true { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw CaptureWebViewIntegrationError.timeout
}

private enum CaptureWebViewIntegrationError: Error {
    case timeout
}

private func normalizedDOMText(_ value: String?) -> String? {
    value?.trimmingCharacters(in: .whitespacesAndNewlines)
}

@MainActor
private final class BlockingConflictResolutionGate {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class BlockingBridgeRequestGate {
    private let matches: (CaptureBridgeRequest) -> Bool
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(matches: @escaping (CaptureBridgeRequest) -> Bool) {
        self.matches = matches
    }

    func suspendIfMatched(_ request: CaptureBridgeRequest) async {
        guard matches(request) else { return }
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
