import AppKit
import Foundation
import os
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
final class CaptureWebViewRecoveryTests: XCTestCase {
    func testRendererTerminationReloadsEditorAndRestoresPersistedActiveDraftOnce() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "renderer-recovery-draft",
                title: "Recovered draft",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Restored after termination"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        var readyRequestCount = 0
        let session = CaptureEditorSession(
            repository: repository,
            beforeBridgeRequest: { request in
                if case .ready = request {
                    readyRequestCount += 1
                }
            }
        )
        defer { session.dispose() }
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return window.NotionPiPBridge?.snapshot().draftID === 'renderer-recovery-draft'"
        }
        XCTAssertEqual(readyRequestCount, 1)

        session.webViewWebContentProcessDidTerminate(session.webView)
        session.webViewWebContentProcessDidTerminate(session.webView)

        XCTAssertEqual(session.status, .loading)
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return window.NotionPiPBridge?.snapshot().draftID === 'renderer-recovery-draft'"
        }
        let snapshot = try await session.latestSnapshot()

        XCTAssertEqual(readyRequestCount, 2)
        XCTAssertEqual(snapshot.draftID, "renderer-recovery-draft")
        XCTAssertEqual(snapshot.title, "Recovered draft")
        XCTAssertEqual(
            snapshot.document,
            Data(#"{"content":[{"content":[{"text":"Restored after termination","type":"text"}],"type":"paragraph"}],"type":"doc"}"#.utf8)
        )
    }

    func testOlderSameDraftSnapshotCannotReplaceNewerLiveDOM() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "monotonic-draft" }
        )
        defer { session.dispose() }
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
        let stashedRevision = try await stashRealWebKitDraft(at: storeURL)

        let reopened = try CaptureRepository(storeURL: storeURL)
        let relaunched = CaptureEditorSession(repository: reopened, draftID: { "unused" })
        defer { relaunched.dispose() }
        try await waitUntil { relaunched.status == .ready }
        let expectedRevision = stashedRevision
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
}
