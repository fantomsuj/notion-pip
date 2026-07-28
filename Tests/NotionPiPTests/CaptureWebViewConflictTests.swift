import AppKit
import Foundation
import os
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
final class CaptureWebViewConflictTests: XCTestCase {
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

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(session.conflict)
        let draftsAfterDebounce = try await repository.drafts()
        XCTAssertEqual(draftsAfterDebounce.count, 2)
        XCTAssertEqual(draftsAfterDebounce.filter { $0.id == "conflict-copy" }.count, 1)
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

        assertCapturedEditorAttempt(attempted, title: "Final captured work", body: "final captured body")

        gate.resume()
        await resolution.value
        try await assertConflictCopyAndUnlockedEditor(
            repository: repository,
            session: session
        )
    }
}
