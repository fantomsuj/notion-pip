import Foundation
import XCTest
@testable import NotionPiP

final class CaptureRepositoryTests: XCTestCase {
    func testSaveDraftCanonicalizesJSONAndIncrementsRevision() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let snapshot = try await repository.saveDraft(
            DraftMutation(
                id: "capture-1",
                title: "A note",
                editorDocument: Data(#"{"z":2,"a":1}"#.utf8),
                sourceDocument: Data(#"{"URL":"https://example.com","nested":{"b":2,"a":1}}"#.utf8),
                disposition: .active
            ),
            expectedRevision: 0
        )

        XCTAssertEqual(snapshot.revision, 1)
        XCTAssertEqual(String(decoding: snapshot.editorDocument, as: UTF8.self), #"{"a":1,"z":2}"#)
        XCTAssertEqual(
            String(decoding: try XCTUnwrap(snapshot.sourceDocument), as: UTF8.self),
            #"{"nested":{"a":1,"b":2},"URL":"https:\/\/example.com"}"#
        )
    }

    func testSaveRejectsStaleRevisionWithoutChangingStoredDraft() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let first = try await repository.saveDraft(mutation(id: "capture-1", title: "Original"), expectedRevision: 0)

        do {
            _ = try await repository.saveDraft(mutation(id: first.id, title: "Stale edit"), expectedRevision: 0)
            XCTFail("Expected a stale revision error")
        } catch let error as CaptureRepositoryError {
            XCTAssertEqual(error, .staleRevision(expected: 0, actual: 1))
        }

        let stored = try await repository.draft(id: first.id)
        XCTAssertEqual(stored?.title, "Original")
    }

    func testRepeatedIdenticalSaveReconcilesLostAcknowledgement() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let request = mutation(id: "capture-1", title: "Same request")
        let first = try await repository.saveDraft(request, expectedRevision: 0)
        let replay = try await repository.saveDraft(request, expectedRevision: 0)

        XCTAssertEqual(replay, first)
        XCTAssertEqual(replay.revision, 1)
    }

    func testOnlyOneDraftIsActiveAndStashedDraftCanBeRestored() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let first = try await repository.saveDraft(mutation(id: "capture-1", title: "First"), expectedRevision: 0)
        _ = try await repository.saveDraft(mutation(id: "capture-2", title: "Second"), expectedRevision: 0)

        let stashedFirst = try await repository.draft(id: first.id)
        XCTAssertEqual(stashedFirst?.disposition, .stashed)
        let restored = try await repository.restoreDraft(id: first.id, expectedRevision: 2)
        XCTAssertEqual(restored.disposition, .active)
        let stashedSecond = try await repository.draft(id: "capture-2")
        XCTAssertEqual(stashedSecond?.disposition, .stashed)
    }

    func testEnqueueAtomicallyCreatesOneRecordAndRetiresDraft() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let draft = try await repository.saveDraft(mutation(id: "capture-1", title: "Queue me"), expectedRevision: 0)

        let record = try await repository.enqueue(
            draftID: draft.id,
            expectedRevision: draft.revision,
            destination: .managed(databaseID: "database-1")
        )

        XCTAssertEqual(record.id, draft.id)
        XCTAssertEqual(record.state, .queued)
        XCTAssertEqual(record.editorDocument, draft.editorDocument)
        let retiredDraft = try await repository.draft(id: draft.id)
        XCTAssertEqual(retiredDraft?.disposition, .abandoned)
    }

    func testRepeatedEnqueueReconcilesToExistingCaptureRecord() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let draft = try await repository.saveDraft(mutation(id: "capture-1", title: "Queue me"), expectedRevision: 0)
        let first = try await repository.enqueue(
            draftID: draft.id,
            expectedRevision: draft.revision,
            destination: .manual(pageID: "page-1")
        )

        let replay = try await repository.enqueue(
            draftID: draft.id,
            expectedRevision: draft.revision,
            destination: .manual(pageID: "page-1")
        )

        XCTAssertEqual(replay, first)
        let records = try await repository.records()
        XCTAssertEqual(records.count, 1)
    }

    func testFailedEnqueueRevisionCheckLeavesDraftActiveAndCreatesNoRecord() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let draft = try await repository.saveDraft(mutation(id: "capture-1", title: "Queue me"), expectedRevision: 0)

        do {
            _ = try await repository.enqueue(
                draftID: draft.id,
                expectedRevision: draft.revision - 1,
                destination: .managed(databaseID: "database-1")
            )
            XCTFail("Expected a stale revision error")
        } catch let error as CaptureRepositoryError {
            XCTAssertEqual(error, .staleRevision(expected: 0, actual: 1))
        }

        let storedDraft = try await repository.draft(id: draft.id)
        let records = try await repository.records()
        XCTAssertEqual(storedDraft?.disposition, .active)
        XCTAssertTrue(records.isEmpty)
    }

    private func mutation(id: String, title: String) -> DraftMutation {
        DraftMutation(
            id: id,
            title: title,
            editorDocument: jsonData(["type": "doc", "content": [["type": "paragraph", "content": [["type": "text", "text": title]]]]]),
            sourceDocument: nil,
            disposition: .active
        )
    }

    private var referenceDate: Date {
        Date(timeIntervalSinceReferenceDate: 0)
    }
}
