import WebKit
import XCTest
@testable import NotionPiP

@MainActor
final class CaptureEditorFlowTests: XCTestCase {
    func testReadyCreatesOneActiveDraftAndReturnsTypedSnapshot() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let session = CaptureEditorSession(repository: repository, draftID: { "draft-1" })

        let reply = await session.handle(.ready(id: "ready-1"))

        XCTAssertEqual(reply.id, "ready-1")
        XCTAssertEqual(reply.result?.kind, .ready)
        XCTAssertEqual(reply.result?.snapshot?.draftID, "draft-1")
        XCTAssertEqual(reply.result?.snapshot?.revision, 1)
        let drafts = try await repository.drafts()
        XCTAssertEqual(drafts.count, 1)
    }

    func testChangedAutosavesAndAcknowledgesAuthoritativeRevision() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let session = CaptureEditorSession(repository: repository, draftID: { "draft-1" })
        _ = await session.handle(.ready(id: "ready"))

        let reply = await session.handle(
            .changed(
                id: "change-1",
                snapshot: bridgeSnapshot(id: "draft-1", title: "Saved", text: "hello"),
                expectedRevision: 1
            )
        )

        XCTAssertEqual(reply.result?.kind, .changed)
        XCTAssertEqual(reply.result?.revision, 2)
        let stored = try await repository.draft(id: "draft-1")
        XCTAssertEqual(stored?.title, "Saved")
    }

    func testLostSaveAcknowledgementReconcilesWithoutCreatingAnotherRevision() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let session = CaptureEditorSession(repository: repository, draftID: { "draft-1" })
        _ = await session.handle(.ready(id: "ready"))
        let request = CaptureBridgeRequest.changed(
            id: "change-1",
            snapshot: bridgeSnapshot(id: "draft-1", title: "Same", text: "body"),
            expectedRevision: 1
        )

        let first = await session.handle(request)
        let replay = await session.handle(
            .changed(
                id: "change-2",
                snapshot: bridgeSnapshot(id: "draft-1", title: "Same", text: "body"),
                expectedRevision: 1
            )
        )

        XCTAssertEqual(first.result?.revision, 2)
        XCTAssertEqual(replay.result?.revision, 2)
        let stored = try await repository.draft(id: "draft-1")
        XCTAssertEqual(stored?.revision, 2)
    }

    func testStaleChangePreservesCurrentEditorWorkAndOffersAllRecoveryActions() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let session = CaptureEditorSession(repository: repository, draftID: { "draft-1" })
        _ = await session.handle(.ready(id: "ready"))
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "draft-1",
                title: "Newer native value",
                editorDocument: proseMirror("native"),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 1
        )

        let currentWork = bridgeSnapshot(id: "draft-1", title: "Unsaved editor value", text: "editor")
        let reply = await session.handle(.changed(id: "stale", snapshot: currentWork, expectedRevision: 1))

        XCTAssertEqual(reply.error?.code, .staleRevision)
        XCTAssertEqual(session.conflict?.currentWork, currentWork)
        XCTAssertEqual(session.conflict?.latest.title, "Newer native value")
        XCTAssertEqual(
            session.conflict?.availableActions,
            [.reloadLatest, .saveAsNew, .openInNotion]
        )
    }

    func testStashAndRestoreSwitchTheAuthoritativeActiveDraft() async throws {
        var identifiers = ["draft-1", "draft-2"].makeIterator()
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let session = CaptureEditorSession(repository: repository, draftID: { identifiers.next()! })
        _ = await session.handle(.ready(id: "ready"))

        let firstSnapshot = bridgeSnapshot(id: "draft-1", title: "First", text: "")
        let stashReply = await session.handle(
            .stash(id: "stash", snapshot: firstSnapshot, expectedRevision: 1)
        )
        let stashed = try await repository.draft(id: "draft-1")
        let restoreReply = await session.handle(
            .restore(
                id: "restore",
                draftID: "draft-1",
                expectedRevision: try XCTUnwrap(stashed?.revision)
            )
        )

        XCTAssertEqual(stashReply.result?.kind, .stashed)
        XCTAssertEqual(stashReply.result?.snapshot?.draftID, "draft-2")
        XCTAssertEqual(restoreReply.result?.kind, .restored)
        XCTAssertEqual(restoreReply.result?.snapshot?.draftID, "draft-1")
        let first = try await repository.draft(id: "draft-1")
        let second = try await repository.draft(id: "draft-2")
        XCTAssertEqual(first?.disposition, .active)
        XCTAssertEqual(second?.disposition, .stashed)
    }

    func testStaleSavePreservesCurrentEditorWorkAndOffersRecovery() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let session = CaptureEditorSession(repository: repository, draftID: { "draft-1" })
        _ = await session.handle(.ready(id: "ready"))
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "draft-1",
                title: "Native latest",
                editorDocument: proseMirror("native"),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 1
        )
        let editorWork = bridgeSnapshot(id: "draft-1", title: "Editor current", text: "editor")

        let reply = await session.handle(
            .save(id: "save-stale", snapshot: editorWork, expectedRevision: 1)
        )

        XCTAssertEqual(reply.error?.code, .staleRevision)
        XCTAssertEqual(session.conflict?.currentWork, editorWork)
        XCTAssertEqual(session.conflict?.latest.title, "Native latest")
        XCTAssertEqual(session.conflict?.availableActions, CaptureConflictAction.allCases)
    }

    func testSavePersistsSuppliedSnapshotBeforeAcknowledging() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let session = CaptureEditorSession(repository: repository, draftID: { "draft-1" })
        _ = await session.handle(.ready(id: "ready"))
        let supplied = bridgeSnapshot(id: "draft-1", title: "Explicit save", text: "save body")

        let reply = await session.handle(.save(id: "save", snapshot: supplied, expectedRevision: 1))

        XCTAssertEqual(reply.result?.kind, .saved)
        XCTAssertEqual(reply.result?.revision, 2)
        let fetched = try await repository.draft(id: "draft-1")
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.title, "Explicit save")
        XCTAssertEqual(stored.editorDocument, try CanonicalJSON.canonicalize(supplied.document))
    }

    func testStashPersistsDifferentSuppliedContentBeforeTransitionAndRestore() async throws {
        var identifiers = ["draft-1", "draft-2"].makeIterator()
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let session = CaptureEditorSession(repository: repository, draftID: { identifiers.next()! })
        _ = await session.handle(.ready(id: "ready"))
        let supplied = bridgeSnapshot(id: "draft-1", title: "Stash this", text: "stash body")

        let stash = await session.handle(.stash(id: "stash", snapshot: supplied, expectedRevision: 1))
        let fetched = try await repository.draft(id: "draft-1")
        let stored = try XCTUnwrap(fetched)
        let restore = await session.handle(
            .restore(id: "restore", draftID: "draft-1", expectedRevision: stored.revision)
        )

        XCTAssertEqual(stash.result?.kind, .stashed)
        XCTAssertEqual(stored.disposition, .stashed)
        XCTAssertEqual(stored.title, "Stash this")
        XCTAssertEqual(stored.editorDocument, try CanonicalJSON.canonicalize(supplied.document))
        XCTAssertEqual(restore.result?.snapshot?.title, "Stash this")
        XCTAssertEqual(restore.result?.snapshot?.document, try CanonicalJSON.canonicalize(supplied.document))
    }

    func testQuickCaptureLaunchActivatesAppBeforeOpeningWindow() {
        var events: [String] = []

        QuickCaptureLaunchAction.perform(
            activate: { events.append("activate") },
            openWindow: { events.append("open") }
        )

        XCTAssertEqual(events, ["activate", "open"])
    }

    func testBridgeCanTearDownAndSessionIsNotRetainedByHandler() async throws {
        weak var weakSession: CaptureEditorSession?
        var session: CaptureEditorSession? = CaptureEditorSession(
            repository: try CaptureRepository(inMemory: true)
        )
        weakSession = session

        session?.tearDownBridge()
        XCTAssertEqual(session?.installedHandlerNames, [])
        session = nil

        XCTAssertNil(weakSession)
    }

    func testSaveAsNewPreservesConflictingWorkInANewDraft() async throws {
        var identifiers = ["draft-1", "draft-copy"].makeIterator()
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let session = CaptureEditorSession(repository: repository, draftID: { identifiers.next()! })
        _ = await session.handle(.ready(id: "ready"))
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "draft-1",
                title: "Native",
                editorDocument: proseMirror("native"),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 1
        )
        let editorWork = bridgeSnapshot(id: "draft-1", title: "Editor", text: "preserve me")
        _ = await session.handle(.changed(id: "stale", snapshot: editorWork, expectedRevision: 1))

        let reply = await session.handle(
            .resolveConflict(id: "resolve", action: .saveAsNew, snapshot: editorWork)
        )

        XCTAssertEqual(reply.result?.kind, .conflictResolved)
        XCTAssertEqual(reply.result?.snapshot?.draftID, "draft-copy")
        let copy = try await repository.draft(id: "draft-copy")
        XCTAssertEqual(copy?.title, "Editor")
        XCTAssertNil(session.conflict)
    }

    func testNativeConflictResolutionUsesTheLatestLiveEditorSnapshot() async throws {
        var identifiers = ["draft-1", "draft-copy"].makeIterator()
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let resolver = CaptureConflictResolverSpy()
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { identifiers.next()! },
            conflictResolver: resolver
        )
        _ = await session.handle(.ready(id: "ready"))
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "draft-1",
                title: "Native latest",
                editorDocument: proseMirror("native"),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 1
        )
        let cachedWork = bridgeSnapshot(id: "draft-1", title: "Cached work", text: "cached")
        let liveWork = bridgeSnapshot(id: "draft-1", title: "Newest live work", text: "newest")
        _ = await session.handle(.changed(id: "stale", snapshot: cachedWork, expectedRevision: 1))
        resolver.onResolve = { action, operationID, _ in
            let reply = await session.handle(
                .resolveConflict(id: operationID, action: action, snapshot: liveWork)
            )
            guard reply.result != nil else { throw CaptureConflictResolverTestError.failedReply }
        }

        await session.resolve(.saveAsNew)

        XCTAssertEqual(resolver.calls.count, 1)
        XCTAssertEqual(resolver.calls.first?.action, .saveAsNew)
        let copy = try await repository.draft(id: "draft-copy")
        XCTAssertEqual(copy?.title, "Newest live work")
        XCTAssertEqual(copy?.editorDocument, try CanonicalJSON.canonicalize(liveWork.document))
        XCTAssertNil(session.conflict)
    }

    func testConflictResolutionIsSingleFlight() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let resolver = BlockingCaptureConflictResolver()
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "draft-1" },
            conflictResolver: resolver
        )
        _ = await session.handle(.ready(id: "ready"))
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "draft-1",
                title: "Native latest",
                editorDocument: proseMirror("native"),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 1
        )
        let editorWork = bridgeSnapshot(id: "draft-1", title: "Editor work", text: "editor")
        _ = await session.handle(.changed(id: "stale", snapshot: editorWork, expectedRevision: 1))

        let first = Task { await session.resolve(.saveAsNew) }
        while resolver.calls.isEmpty { await Task.yield() }
        let second = Task { await session.resolve(.saveAsNew) }
        await Task.yield()

        XCTAssertEqual(resolver.calls.count, 1)
        XCTAssertTrue(session.isResolvingConflict)
        resolver.resume()
        await first.value
        await second.value
        XCTAssertEqual(resolver.calls.count, 1)
        XCTAssertFalse(session.isResolvingConflict)
    }

    func testConflictResolutionRetryReusesCommittedOperationWithoutCreatingAnotherCopy() async throws {
        var identifiers = ["draft-1", "draft-copy"].makeIterator()
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(captureFlowReferenceDate))
        let resolver = CaptureConflictResolverSpy()
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { identifiers.next()! },
            conflictResolver: resolver
        )
        _ = await session.handle(.ready(id: "ready"))
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "draft-1",
                title: "Native latest",
                editorDocument: proseMirror("native"),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 1
        )
        let editorWork = bridgeSnapshot(id: "draft-1", title: "Newest work", text: "newest")
        _ = await session.handle(.changed(id: "stale", snapshot: editorWork, expectedRevision: 1))
        var shouldThrowAfterCommit = true
        resolver.onResolve = { action, operationID, _ in
            let reply = await session.handle(
                .resolveConflict(id: operationID, action: action, snapshot: editorWork)
            )
            guard reply.result != nil else { throw CaptureConflictResolverTestError.failedReply }
            if shouldThrowAfterCommit {
                shouldThrowAfterCommit = false
                throw CaptureConflictResolverTestError.applyFailed
            }
        }

        await session.resolve(.saveAsNew)
        XCTAssertNotNil(session.conflict)
        let firstOperationID = try XCTUnwrap(resolver.calls.first?.operationID)

        await session.resolve(.saveAsNew)

        XCTAssertEqual(resolver.calls.count, 2)
        XCTAssertEqual(resolver.calls.last?.operationID, firstOperationID)
        let drafts = try await repository.drafts()
        XCTAssertEqual(drafts.filter { $0.id == "draft-copy" }.count, 1)
        XCTAssertNil(session.conflict)
    }

    func testCaptureUsesNonpersistentStoreAndNoHandlerLeaksIntoNotionWebView() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let capture = CaptureEditorSession(repository: repository)
        let notion = NotionWebSession()

        XCTAssertFalse(capture.webView.configuration.websiteDataStore === WKWebsiteDataStore.default())
        XCTAssertTrue(notion.webView.configuration.websiteDataStore === WKWebsiteDataStore.default())
        XCTAssertEqual(capture.installedHandlerNames, [CaptureBridgeProtocol.handlerName])
        XCTAssertFalse(
            capture.webView.configuration.userContentController
                === notion.webView.configuration.userContentController
        )
    }

    func testAcknowledgedDraftRevisionAndContentRestoreAfterSessionRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("CaptureEditor.store")

        do {
            let repository = try CaptureRepository(storeURL: storeURL)
            let session = CaptureEditorSession(repository: repository, draftID: { "draft-relaunch" })
            _ = await session.handle(.ready(id: "ready"))
            let acknowledged = await session.handle(
                .changed(
                    id: "change",
                    snapshot: bridgeSnapshot(
                        id: "draft-relaunch",
                        title: "Survives relaunch",
                        text: "durable body"
                    ),
                    expectedRevision: 1
                )
            )
            XCTAssertEqual(acknowledged.result?.revision, 2)
        }

        let reopened = try CaptureRepository(storeURL: storeURL)
        let relaunched = CaptureEditorSession(repository: reopened, draftID: { "unused" })
        let reply = await relaunched.handle(.ready(id: "ready-again"))

        XCTAssertEqual(reply.result?.snapshot?.draftID, "draft-relaunch")
        XCTAssertEqual(reply.result?.snapshot?.title, "Survives relaunch")
        XCTAssertEqual(reply.result?.snapshot?.revision, 2)
        XCTAssertEqual(
            reply.result?.snapshot?.document,
            try CanonicalJSON.canonicalize(proseMirror("durable body"))
        )
    }
}

private func bridgeSnapshot(id: String, title: String, text: String) -> CaptureEditorSnapshot {
    CaptureEditorSnapshot(draftID: id, title: title, document: proseMirror(text))
}

private func proseMirror(_ text: String) -> Data {
    Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"\#(text)"}]}]}"#.utf8)
}

private let captureFlowReferenceDate = Date(timeIntervalSince1970: 1_700_000_000)

@MainActor
private final class CaptureConflictResolverSpy: CaptureConflictResolving {
    struct Call: Equatable {
        let action: CaptureConflictAction
        let operationID: String
    }

    private(set) var calls: [Call] = []
    var onResolve: ((CaptureConflictAction, String, WKWebView) async throws -> Void)?

    func resolve(
        _ action: CaptureConflictAction,
        operationID: String,
        in webView: WKWebView
    ) async throws {
        calls.append(Call(action: action, operationID: operationID))
        try await onResolve?(action, operationID, webView)
    }
}

@MainActor
private final class BlockingCaptureConflictResolver: CaptureConflictResolving {
    private(set) var calls: [(CaptureConflictAction, String)] = []
    private var continuation: CheckedContinuation<Void, Never>?

    func resolve(
        _ action: CaptureConflictAction,
        operationID: String,
        in webView: WKWebView
    ) async throws {
        calls.append((action, operationID))
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private enum CaptureConflictResolverTestError: Error {
    case failedReply
    case applyFailed
}
