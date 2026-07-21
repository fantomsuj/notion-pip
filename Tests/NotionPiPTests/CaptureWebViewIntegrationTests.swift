import Foundation
import WebKit
import XCTest
@testable import NotionPiP

@MainActor
final class CaptureWebViewIntegrationTests: XCTestCase {
    func testBundledEditorRunsRealReplyBridgeAndRestoresStashedContentAfterRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("WebKitCapture.store")

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
            XCTAssertEqual(edited?["body"], "real webkit body")

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

            session?.tearDownBridge()
            session = nil
        }
        XCTAssertNil(releasedSession)

        let reopened = try CaptureRepository(storeURL: storeURL)
        let relaunched = CaptureEditorSession(repository: reopened, draftID: { "unused" })
        try await waitUntil { relaunched.status == .ready }
        let restoreValue = try await relaunched.webView.callAsyncJavaScript(
            "return await window.NotionPiPBridge.restore(draftID, expectedRevision)",
            arguments: ["draftID": "web-draft", "expectedRevision": 3],
            in: nil,
            contentWorld: .page
        )
        let restoreReply = try XCTUnwrap(restoreValue as? [String: Any])
        let result = try XCTUnwrap(restoreReply["result"] as? [String: Any])
        let restored = try XCTUnwrap(result["snapshot"] as? [String: Any])

        XCTAssertEqual(restored["title"] as? String, "Real WebKit")
        XCTAssertEqual(restored["revision"] as? Int, 4)
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
        XCTAssertEqual(restoredDOM?["body"], "real webkit body")
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
        XCTAssertEqual(staleDOM["body"], "cached conflict body")
        try await waitUntil { session.conflict != nil }

        let newestDOM = try await editEditor(
            title: "Newest unsent JS work",
            body: "newest unsent JS body",
            in: session.webView
        )
        XCTAssertEqual(newestDOM["body"], "newest unsent JS body")

        await session.resolve(.saveAsNew)

        XCTAssertNil(session.conflict)
        let copyValue = try await repository.draft(id: "conflict-copy")
        let copy = try XCTUnwrap(copyValue)
        XCTAssertEqual(copy.title, "Newest unsent JS work")
        XCTAssertTrue(String(decoding: copy.editorDocument, as: UTF8.self).contains("newest unsent JS body"))
        let installed = try await editorDOM(in: session.webView)
        XCTAssertEqual(installed["title"], "Newest unsent JS work")
        XCTAssertEqual(installed["body"], "newest unsent JS body")
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

private enum CaptureWebViewIntegrationError: Error {
    case timeout
}
