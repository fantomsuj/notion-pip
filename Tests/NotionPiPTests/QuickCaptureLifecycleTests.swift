import Foundation
import XCTest
@testable import NotionPiP

final class QuickCaptureLifecycleTests: XCTestCase {
    func testClosePassesAnAlreadyCanonicalEditorDocumentThroughToPersistence() async throws {
        let document = try CanonicalCaptureDocument(
            validating: jsonData([
                "type": "doc",
                "content": [[
                    "type": "paragraph",
                    "content": [["type": "text", "text": "Latest body"]],
                ]],
            ])
        )
        let stored = CaptureDraftSnapshot(
            id: "draft-canonical",
            revision: 1,
            title: "Old title",
            editorDocument: jsonData(["type": "doc", "content": []]),
            sourceDocument: nil,
            disposition: .active,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            captureRecordID: nil,
            returnDraftID: nil
        )
        let repository = CanonicalMutationProbe(stored: stored)
        let destinations = QuickCaptureDestinationRepository(
            container: try NotionPiPPersistence.makeContainer(inMemory: true)
        )
        let coordinator = QuickCaptureLifecycleCoordinator(
            repository: repository,
            destinations: destinations,
            hasUsableToken: { true }
        )

        _ = await coordinator.close(
            snapshot: CaptureEditorSnapshot(
                draftID: stored.id,
                title: "Latest title",
                canonicalDocument: document,
                revision: stored.revision
            )
        )

        let receivedCanonicalDocument = await repository.receivedCanonicalDocument
        XCTAssertEqual(receivedCanonicalDocument, document)
    }

    func testEmptyCloseDiscardsDraftWithoutCreatingRecord() async throws {
        let (repository, destinations, draft) = try await makeRepositories()
        let coordinator = QuickCaptureLifecycleCoordinator(
            repository: repository,
            destinations: destinations,
            hasUsableToken: { true }
        )

        let outcome = await coordinator.close(
            snapshot: editorSnapshot(
                draftID: draft.id,
                revision: draft.revision,
                title: "  ",
                content: [["type": "paragraph"]]
            )
        )

        XCTAssertEqual(outcome, .discarded)
        let drafts = try await repository.drafts()
        let records = try await repository.records()
        XCTAssertTrue(drafts.isEmpty)
        XCTAssertTrue(records.isEmpty)
    }

    func testNonEmptyCloseSavesLatestSnapshotAndEnqueuesBeforeCallback() async throws {
        let (repository, destinations, draft) = try await makeRepositories()
        try await destinations.replaceDefault(
            with: .pageParent(pageID: "page-1", title: "Inbox")
        )
        let callback = EnqueueCallbackProbe(repository: repository)
        let coordinator = QuickCaptureLifecycleCoordinator(
            repository: repository,
            destinations: destinations,
            hasUsableToken: { true },
            onEnqueued: { recordID in await callback.recordEnqueue(recordID) }
        )

        let outcome = await coordinator.close(
            snapshot: editorSnapshot(
                draftID: draft.id,
                revision: draft.revision,
                title: "Latest title",
                content: [[
                    "type": "paragraph",
                    "content": [["type": "text", "text": "Latest body"]],
                ]]
            )
        )

        XCTAssertEqual(outcome, .enqueued(recordID: draft.id))
        let fetchedRecord = try await repository.record(id: draft.id)
        let record = try XCTUnwrap(fetchedRecord)
        let observedDurableRecordIDs = await callback.observedDurableRecordIDs
        XCTAssertEqual(record.title, "Latest title")
        XCTAssertTrue(String(decoding: record.editorDocument, as: UTF8.self).contains("Latest body"))
        XCTAssertEqual(record.destination, .pageParent(pageID: "page-1"))
        XCTAssertEqual(observedDurableRecordIDs, [draft.id])
    }

    func testMissingDestinationRetainsLatestDraftAndProvidesSettingsGuidance() async throws {
        let (repository, destinations, draft) = try await makeRepositories()
        let coordinator = QuickCaptureLifecycleCoordinator(
            repository: repository,
            destinations: destinations,
            hasUsableToken: { true }
        )

        let outcome = await coordinator.close(
            snapshot: editorSnapshot(
                draftID: draft.id,
                revision: draft.revision,
                title: "Keep me",
                content: [["type": "paragraph"]]
            )
        )

        XCTAssertEqual(
            outcome,
            .needsConfiguration("Choose a Quick Capture destination in Settings.")
        )
        let retainedDraft = try await repository.draft(id: draft.id)
        let records = try await repository.records()
        XCTAssertEqual(retainedDraft?.title, "Keep me")
        XCTAssertTrue(records.isEmpty)
    }

    func testMissingTokenRetainsDraftAndProvidesReconnectGuidance() async throws {
        let (repository, destinations, draft) = try await makeRepositories()
        try await destinations.replaceDefault(
            with: .dataSource(dataSourceID: "source-1", title: "Notes")
        )
        let coordinator = QuickCaptureLifecycleCoordinator(
            repository: repository,
            destinations: destinations,
            hasUsableToken: { false }
        )

        let outcome = await coordinator.close(
            snapshot: editorSnapshot(
                draftID: draft.id,
                revision: draft.revision,
                title: "",
                content: [[
                    "type": "paragraph",
                    "content": [["type": "text", "text": "Body"]],
                ]]
            )
        )

        XCTAssertEqual(
            outcome,
            .needsConfiguration("Reconnect your Notion personal access token in Settings.")
        )
        let retainedDraft = try await repository.draft(id: draft.id)
        let records = try await repository.records()
        XCTAssertNotNil(retainedDraft)
        XCTAssertTrue(records.isEmpty)
    }

    private func makeRepositories() async throws -> (
        CaptureRepository,
        QuickCaptureDestinationRepository,
        CaptureDraftSnapshot
    ) {
        let container = try NotionPiPPersistence.makeContainer(inMemory: true)
        let repository = CaptureRepository(container: container)
        let destinations = QuickCaptureDestinationRepository(container: container)
        let draft = try await repository.saveDraft(
            DraftMutation(
                id: "draft-1",
                title: "",
                editorDocument: jsonData(["type": "doc", "content": [["type": "paragraph"]]]),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        return (repository, destinations, draft)
    }

    private func editorSnapshot(
        draftID: String,
        revision: Int,
        title: String,
        content: [[String: Any]]
    ) -> CaptureEditorSnapshot {
        CaptureEditorSnapshot(
            draftID: draftID,
            title: title,
            document: jsonData(["type": "doc", "content": content]),
            revision: revision
        )
    }
}

private actor CanonicalMutationProbe: CaptureDraftFinalizing {
    private let stored: CaptureDraftSnapshot
    private(set) var receivedCanonicalDocument: CanonicalCaptureDocument?

    init(stored: CaptureDraftSnapshot) {
        self.stored = stored
    }

    func draft(id: String) -> CaptureDraftSnapshot? {
        id == stored.id ? stored : nil
    }

    func saveDraft(
        _ mutation: DraftMutation,
        expectedRevision: Int
    ) -> CaptureDraftSnapshot {
        receivedCanonicalDocument = mutation.canonicalEditorDocument
        return CaptureDraftSnapshot(
            id: mutation.id,
            revision: expectedRevision + 1,
            title: mutation.title,
            editorDocument: mutation.editorDocument,
            sourceDocument: mutation.sourceDocument,
            disposition: mutation.disposition,
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt,
            captureRecordID: nil,
            returnDraftID: nil
        )
    }

    func discardDraft(id: String, expectedRevision: Int) {}

    func enqueue(
        draftID: String,
        expectedRevision: Int,
        destination: CaptureDestination
    ) throws -> CaptureRecordSnapshot {
        throw CaptureRepositoryError.draftNotFound(draftID)
    }
}

private actor EnqueueCallbackProbe {
    private let repository: CaptureRepository
    private(set) var observedDurableRecordIDs: [String] = []

    init(repository: CaptureRepository) {
        self.repository = repository
    }

    func recordEnqueue(_ recordID: String) async {
        if (try? await repository.record(id: recordID)) != nil {
            observedDurableRecordIDs.append(recordID)
        }
    }
}
