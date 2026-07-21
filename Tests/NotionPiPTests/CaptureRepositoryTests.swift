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

    func testRestoreRejectsActiveDraftWithoutMutation() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let active = try await repository.saveDraft(mutation(id: "capture-1", title: "Active"), expectedRevision: 0)

        do {
            _ = try await repository.restoreDraft(id: active.id, expectedRevision: active.revision)
            XCTFail("Expected active restore rejection")
        } catch {}

        let stored = try await repository.draft(id: active.id)
        XCTAssertEqual(stored, active)
    }

    func testStashRejectsAlreadyStashedDraftWithoutMutation() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let first = try await repository.saveDraft(mutation(id: "capture-1", title: "First"), expectedRevision: 0)
        _ = try await repository.saveDraft(mutation(id: "capture-2", title: "Second"), expectedRevision: 0)
        let fetchedStashed = try await repository.draft(id: first.id)
        let stashed = try XCTUnwrap(fetchedStashed)

        do {
            _ = try await repository.stashDraft(id: stashed.id, expectedRevision: stashed.revision)
            XCTFail("Expected stashed transition rejection")
        } catch {}

        let stored = try await repository.draft(id: stashed.id)
        XCTAssertEqual(stored, stashed)
    }

    func testRestoreRejectsAbandonedDraftWithoutChangingRecordLink() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let active = try await repository.saveDraft(mutation(id: "capture-1", title: "Queued"), expectedRevision: 0)
        _ = try await repository.enqueue(
            draftID: active.id,
            expectedRevision: active.revision,
            destination: .managed(databaseID: "database-1")
        )
        let fetchedAbandoned = try await repository.draft(id: active.id)
        let abandoned = try XCTUnwrap(fetchedAbandoned)

        do {
            _ = try await repository.restoreDraft(id: abandoned.id, expectedRevision: abandoned.revision)
            XCTFail("Expected abandoned restore rejection")
        } catch {}

        let stored = try await repository.draft(id: abandoned.id)
        XCTAssertEqual(stored, abandoned)
        XCTAssertEqual(stored?.captureRecordID, active.id)
    }

    func testStashRejectsAbandonedDraftWithoutChangingRecordLink() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let active = try await repository.saveDraft(mutation(id: "capture-1", title: "Queued"), expectedRevision: 0)
        _ = try await repository.enqueue(
            draftID: active.id,
            expectedRevision: active.revision,
            destination: .manual(pageID: "page-1")
        )
        let fetchedAbandoned = try await repository.draft(id: active.id)
        let abandoned = try XCTUnwrap(fetchedAbandoned)

        do {
            _ = try await repository.stashDraft(id: abandoned.id, expectedRevision: abandoned.revision)
            XCTFail("Expected abandoned stash rejection")
        } catch {}

        let stored = try await repository.draft(id: abandoned.id)
        XCTAssertEqual(stored, abandoned)
        XCTAssertEqual(stored?.captureRecordID, active.id)
    }

    func testSaveDraftCannotBypassExplicitDispositionTransition() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let active = try await repository.saveDraft(mutation(id: "capture-1", title: "Active"), expectedRevision: 0)
        let changedDisposition = DraftMutation(
            id: active.id,
            title: "Changed",
            editorDocument: active.editorDocument,
            sourceDocument: active.sourceDocument,
            disposition: .stashed
        )

        do {
            _ = try await repository.saveDraft(changedDisposition, expectedRevision: active.revision)
            XCTFail("Expected explicit transition requirement")
        } catch {}

        let stored = try await repository.draft(id: active.id)
        XCTAssertEqual(stored, active)
    }

    func testSaveDraftCannotReactivateAbandonedLinkedDraft() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let active = try await repository.saveDraft(mutation(id: "capture-1", title: "Queued"), expectedRevision: 0)
        _ = try await repository.enqueue(
            draftID: active.id,
            expectedRevision: active.revision,
            destination: .managed(databaseID: "database-1")
        )
        let abandoned = try await repository.draft(id: active.id)
        let retired = try XCTUnwrap(abandoned)
        let reactivation = DraftMutation(
            id: retired.id,
            title: "Reactivated",
            editorDocument: retired.editorDocument,
            sourceDocument: retired.sourceDocument,
            disposition: .active
        )

        do {
            _ = try await repository.saveDraft(reactivation, expectedRevision: retired.revision)
            XCTFail("Expected abandoned reactivation rejection")
        } catch {}

        let stored = try await repository.draft(id: retired.id)
        XCTAssertEqual(stored, abandoned)
    }

    func testSaveDraftCannotMutateAbandonedLinkedDraftContent() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let active = try await repository.saveDraft(mutation(id: "capture-1", title: "Queued"), expectedRevision: 0)
        _ = try await repository.enqueue(
            draftID: active.id,
            expectedRevision: active.revision,
            destination: .manual(pageID: "page-1")
        )
        let abandoned = try await repository.draft(id: active.id)
        let retired = try XCTUnwrap(abandoned)
        let contentMutation = DraftMutation(
            id: retired.id,
            title: "Mutated after enqueue",
            editorDocument: retired.editorDocument,
            sourceDocument: retired.sourceDocument,
            disposition: .abandoned
        )

        do {
            _ = try await repository.saveDraft(contentMutation, expectedRevision: retired.revision)
            XCTFail("Expected abandoned content mutation rejection")
        } catch {}

        let stored = try await repository.draft(id: retired.id)
        XCTAssertEqual(stored, abandoned)
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

    func testEnqueueReplayRejectsStaleOriginalRevisionWithoutMutation() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let draft = try await repository.saveDraft(mutation(id: "capture-1", title: "Queue me"), expectedRevision: 0)
        let first = try await repository.enqueue(
            draftID: draft.id,
            expectedRevision: draft.revision,
            destination: .managed(databaseID: "database-1")
        )
        let retiredBefore = try await repository.draft(id: draft.id)

        do {
            _ = try await repository.enqueue(
                draftID: draft.id,
                expectedRevision: draft.revision - 1,
                destination: .managed(databaseID: "database-1")
            )
            XCTFail("Expected stale replay rejection")
        } catch {}

        let recordAfter = try await repository.record(id: draft.id)
        let retiredAfter = try await repository.draft(id: draft.id)
        XCTAssertEqual(recordAfter, first)
        XCTAssertEqual(retiredAfter, retiredBefore)
    }

    func testEnqueueReplayRejectsFutureOriginalRevisionWithoutMutation() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let draft = try await repository.saveDraft(mutation(id: "capture-1", title: "Queue me"), expectedRevision: 0)
        let first = try await repository.enqueue(
            draftID: draft.id,
            expectedRevision: draft.revision,
            destination: .manual(pageID: "page-1")
        )
        let retiredBefore = try await repository.draft(id: draft.id)

        do {
            _ = try await repository.enqueue(
                draftID: draft.id,
                expectedRevision: draft.revision + 1,
                destination: .manual(pageID: "page-1")
            )
            XCTFail("Expected future replay rejection")
        } catch {}

        let recordAfter = try await repository.record(id: draft.id)
        let retiredAfter = try await repository.draft(id: draft.id)
        XCTAssertEqual(recordAfter, first)
        XCTAssertEqual(retiredAfter, retiredBefore)
    }

    func testEnqueueReplayRejectsDifferentDestinationWithoutMutation() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let draft = try await repository.saveDraft(mutation(id: "capture-1", title: "Queue me"), expectedRevision: 0)
        let first = try await repository.enqueue(
            draftID: draft.id,
            expectedRevision: draft.revision,
            destination: .managed(databaseID: "database-1")
        )
        let retiredBefore = try await repository.draft(id: draft.id)

        do {
            _ = try await repository.enqueue(
                draftID: draft.id,
                expectedRevision: draft.revision,
                destination: .manual(pageID: "database-1")
            )
            XCTFail("Expected destination replay rejection")
        } catch {}

        let recordAfter = try await repository.record(id: draft.id)
        let retiredAfter = try await repository.draft(id: draft.id)
        XCTAssertEqual(recordAfter, first)
        XCTAssertEqual(retiredAfter, retiredBefore)
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

    func testEnqueueActiveDraftReactivatesItsReturnDraft() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let first = try await repository.saveDraft(mutation(id: "capture-a", title: "A"), expectedRevision: 0)
        let second = try await repository.saveDraft(mutation(id: "capture-b", title: "B"), expectedRevision: 0)

        XCTAssertEqual(second.returnDraftID, first.id)
        _ = try await repository.enqueue(
            draftID: second.id,
            expectedRevision: second.revision,
            destination: .managed(databaseID: "database-1")
        )

        let returned = try await repository.draft(id: first.id)
        let retired = try await repository.draft(id: second.id)
        let allDrafts = try await repository.drafts()
        XCTAssertEqual(returned?.disposition, .active)
        XCTAssertEqual(retired?.disposition, .abandoned)
        XCTAssertNil(retired?.returnDraftID)
        XCTAssertEqual(allDrafts.filter { $0.disposition == .active }.map(\.id), [first.id])
    }

    func testStashActiveDraftReactivatesItsReturnDraft() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let first = try await repository.saveDraft(mutation(id: "capture-a", title: "A"), expectedRevision: 0)
        let second = try await repository.saveDraft(mutation(id: "capture-b", title: "B"), expectedRevision: 0)

        XCTAssertEqual(second.returnDraftID, first.id)
        let stashed = try await repository.stashDraft(id: second.id, expectedRevision: second.revision)

        let returned = try await repository.draft(id: first.id)
        let allDrafts = try await repository.drafts()
        XCTAssertEqual(stashed.disposition, .stashed)
        XCTAssertNil(stashed.returnDraftID)
        XCTAssertEqual(returned?.disposition, .active)
        XCTAssertEqual(allDrafts.filter { $0.disposition == .active }.map(\.id), [first.id])
    }

    func testRestoreHelperFetchFailureRollsBackBeforeLaterSave() async throws {
        let failure = FailNextCaptureRepositoryFetch()
        let repository = try CaptureRepository(
            inMemory: true,
            clock: TestCaptureClock(referenceDate),
            beforeHelperFetch: failure.check
        )
        let first = try await repository.saveDraft(mutation(id: "capture-a", title: "A"), expectedRevision: 0)
        let second = try await repository.saveDraft(mutation(id: "capture-b", title: "B"), expectedRevision: 0)
        let fetchedFirstBefore = try await repository.draft(id: first.id)
        let fetchedSecondBefore = try await repository.draft(id: second.id)
        let firstBefore = try XCTUnwrap(fetchedFirstBefore)
        let secondBefore = try XCTUnwrap(fetchedSecondBefore)

        failure.failNext(.otherActiveDrafts)
        do {
            _ = try await repository.restoreDraft(id: firstBefore.id, expectedRevision: firstBefore.revision)
            XCTFail("Expected injected restore helper-fetch failure")
        } catch is FailNextCaptureRepositoryFetch.ExpectedFailure {}

        let firstAfterFailure = try await repository.draft(id: first.id)
        let secondAfterFailure = try await repository.draft(id: second.id)
        XCTAssertEqual(firstAfterFailure, firstBefore)
        XCTAssertEqual(secondAfterFailure, secondBefore)

        _ = try await repository.saveDraft(
            mutation(id: "unrelated", title: "Later save", disposition: .stashed),
            expectedRevision: 0
        )
        let firstAfterLaterSave = try await repository.draft(id: first.id)
        let secondAfterLaterSave = try await repository.draft(id: second.id)
        XCTAssertEqual(firstAfterLaterSave, firstBefore)
        XCTAssertEqual(secondAfterLaterSave, secondBefore)
    }

    func testStashHelperFetchFailureRollsBackBeforeLaterSave() async throws {
        let failure = FailNextCaptureRepositoryFetch()
        let repository = try CaptureRepository(
            inMemory: true,
            clock: TestCaptureClock(referenceDate),
            beforeHelperFetch: failure.check
        )
        let first = try await repository.saveDraft(mutation(id: "capture-a", title: "A"), expectedRevision: 0)
        let second = try await repository.saveDraft(mutation(id: "capture-b", title: "B"), expectedRevision: 0)
        let fetchedFirstBefore = try await repository.draft(id: first.id)
        let fetchedSecondBefore = try await repository.draft(id: second.id)
        let firstBefore = try XCTUnwrap(fetchedFirstBefore)
        let secondBefore = try XCTUnwrap(fetchedSecondBefore)

        failure.failNext(.returnDraft)
        do {
            _ = try await repository.stashDraft(id: second.id, expectedRevision: second.revision)
            XCTFail("Expected injected stash helper-fetch failure")
        } catch is FailNextCaptureRepositoryFetch.ExpectedFailure {}

        let firstAfterFailure = try await repository.draft(id: first.id)
        let secondAfterFailure = try await repository.draft(id: second.id)
        XCTAssertEqual(firstAfterFailure, firstBefore)
        XCTAssertEqual(secondAfterFailure, secondBefore)

        _ = try await repository.saveDraft(
            mutation(id: "unrelated", title: "Later save", disposition: .stashed),
            expectedRevision: 0
        )
        let firstAfterLaterSave = try await repository.draft(id: first.id)
        let secondAfterLaterSave = try await repository.draft(id: second.id)
        XCTAssertEqual(firstAfterLaterSave, firstBefore)
        XCTAssertEqual(secondAfterLaterSave, secondBefore)
    }

    func testEnqueueHelperFetchFailureRollsBackBeforeLaterSave() async throws {
        let failure = FailNextCaptureRepositoryFetch()
        let repository = try CaptureRepository(
            inMemory: true,
            clock: TestCaptureClock(referenceDate),
            beforeHelperFetch: failure.check
        )
        let first = try await repository.saveDraft(mutation(id: "capture-a", title: "A"), expectedRevision: 0)
        let second = try await repository.saveDraft(mutation(id: "capture-b", title: "B"), expectedRevision: 0)
        let fetchedFirstBefore = try await repository.draft(id: first.id)
        let fetchedSecondBefore = try await repository.draft(id: second.id)
        let firstBefore = try XCTUnwrap(fetchedFirstBefore)
        let secondBefore = try XCTUnwrap(fetchedSecondBefore)

        failure.failNext(.returnDraft)
        do {
            _ = try await repository.enqueue(
                draftID: second.id,
                expectedRevision: second.revision,
                destination: .managed(databaseID: "database-1")
            )
            XCTFail("Expected injected enqueue helper-fetch failure")
        } catch is FailNextCaptureRepositoryFetch.ExpectedFailure {}

        let firstAfterFailure = try await repository.draft(id: first.id)
        let secondAfterFailure = try await repository.draft(id: second.id)
        let recordsAfterFailure = try await repository.records()
        XCTAssertEqual(firstAfterFailure, firstBefore)
        XCTAssertEqual(secondAfterFailure, secondBefore)
        XCTAssertTrue(recordsAfterFailure.isEmpty)

        _ = try await repository.saveDraft(
            mutation(id: "unrelated", title: "Later save", disposition: .stashed),
            expectedRevision: 0
        )
        let firstAfterLaterSave = try await repository.draft(id: first.id)
        let secondAfterLaterSave = try await repository.draft(id: second.id)
        let recordsAfterLaterSave = try await repository.records()
        XCTAssertEqual(firstAfterLaterSave, firstBefore)
        XCTAssertEqual(secondAfterLaterSave, secondBefore)
        XCTAssertTrue(recordsAfterLaterSave.isEmpty)
    }

    private func mutation(
        id: String,
        title: String,
        disposition: DraftDisposition = .active
    ) -> DraftMutation {
        DraftMutation(
            id: id,
            title: title,
            editorDocument: jsonData(["type": "doc", "content": [["type": "paragraph", "content": [["type": "text", "text": title]]]]]),
            sourceDocument: nil,
            disposition: disposition
        )
    }

    private var referenceDate: Date {
        Date(timeIntervalSinceReferenceDate: 0)
    }
}

private final class FailNextCaptureRepositoryFetch: @unchecked Sendable {
    struct ExpectedFailure: Error {}

    private let lock = NSLock()
    private var checkpoint: CaptureRepositoryHelperFetch?

    func failNext(_ checkpoint: CaptureRepositoryHelperFetch) {
        lock.withLock { self.checkpoint = checkpoint }
    }

    func check(_ checkpoint: CaptureRepositoryHelperFetch) throws {
        try lock.withLock {
            if self.checkpoint == checkpoint {
                self.checkpoint = nil
                throw ExpectedFailure()
            }
        }
    }
}
