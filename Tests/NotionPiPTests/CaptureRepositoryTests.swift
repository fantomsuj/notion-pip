import Foundation
import SwiftData
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

    func testNewActiveSaveHelperFetchFailureLeavesPriorActiveAndNoNewDraft() async throws {
        let failure = FailNextCaptureRepositoryFetch()
        let repository = try CaptureRepository(
            inMemory: true,
            clock: TestCaptureClock(referenceDate),
            beforeHelperFetch: failure.check
        )
        let priorActive = try await repository.saveDraft(
            mutation(id: "capture-a", title: "Prior active"),
            expectedRevision: 0
        )

        failure.failNext(.otherActiveDrafts)
        do {
            _ = try await repository.saveDraft(
                mutation(id: "capture-b", title: "Failed new active"),
                expectedRevision: 0
            )
            XCTFail("Expected injected new-active save helper-fetch failure")
        } catch is FailNextCaptureRepositoryFetch.ExpectedFailure {}

        let priorAfterFailure = try await repository.draft(id: priorActive.id)
        let newAfterFailure = try await repository.draft(id: "capture-b")
        XCTAssertEqual(priorAfterFailure, priorActive)
        XCTAssertNil(newAfterFailure)

        _ = try await repository.saveDraft(
            mutation(id: "unrelated", title: "Later save", disposition: .stashed),
            expectedRevision: 0
        )
        let priorAfterLaterSave = try await repository.draft(id: priorActive.id)
        let newAfterLaterSave = try await repository.draft(id: "capture-b")
        XCTAssertEqual(priorAfterLaterSave, priorActive)
        XCTAssertNil(newAfterLaterSave)
    }

    func testExistingActiveSaveHelperFetchFailureLeavesContentUnchanged() async throws {
        let failure = FailNextCaptureRepositoryFetch()
        let repository = try CaptureRepository(
            inMemory: true,
            clock: TestCaptureClock(referenceDate),
            beforeHelperFetch: failure.check
        )
        let active = try await repository.saveDraft(
            mutation(id: "capture-a", title: "Original"),
            expectedRevision: 0
        )

        failure.failNext(.otherActiveDrafts)
        do {
            _ = try await repository.saveDraft(
                mutation(id: active.id, title: "Failed update"),
                expectedRevision: active.revision
            )
            XCTFail("Expected injected existing-active save helper-fetch failure")
        } catch is FailNextCaptureRepositoryFetch.ExpectedFailure {}

        let activeAfterFailure = try await repository.draft(id: active.id)
        XCTAssertEqual(activeAfterFailure, active)

        _ = try await repository.saveDraft(
            mutation(id: "unrelated", title: "Later save", disposition: .stashed),
            expectedRevision: 0
        )
        let activeAfterLaterSave = try await repository.draft(id: active.id)
        XCTAssertEqual(activeAfterLaterSave, active)
    }

    func testIDLookupsReturnExactModelsAndNilForMissingIDs() async throws {
        let repository = try CaptureRepository(inMemory: true, clock: TestCaptureClock(referenceDate))
        let firstDraft = try await repository.saveDraft(mutation(id: "draft-first", title: "First"), expectedRevision: 0)
        _ = try await repository.enqueue(
            draftID: firstDraft.id,
            expectedRevision: firstDraft.revision,
            destination: .managed(databaseID: "database-1")
        )
        let requestedDraft = try await repository.saveDraft(
            mutation(id: "draft-requested", title: "Requested"),
            expectedRevision: 0
        )
        let requestedRecord = try await repository.enqueue(
            draftID: requestedDraft.id,
            expectedRevision: requestedDraft.revision,
            destination: .manual(pageID: "page-requested")
        )

        let fetchedDraft = try await repository.draft(id: requestedDraft.id)
        let fetchedRecord = try await repository.record(id: requestedRecord.id)
        let missingDraft = try await repository.draft(id: "missing-draft")
        let missingRecord = try await repository.record(id: "missing-record")

        XCTAssertEqual(fetchedDraft?.id, requestedDraft.id)
        XCTAssertEqual(fetchedDraft?.title, "Requested")
        XCTAssertEqual(fetchedRecord?.id, requestedRecord.id)
        XCTAssertEqual(fetchedRecord?.title, "Requested")
        XCTAssertEqual(fetchedRecord?.destination, .manual(pageID: "page-requested"))
        XCTAssertNil(missingDraft)
        XCTAssertNil(missingRecord)
    }

    func testNewActiveDraftReturnsNewestExistingActiveDraftUsingStableIDTieBreak() async throws {
        let container = try NotionPiPPersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let older = referenceDate
        let newest = older.addingTimeInterval(60)
        context.insert(makeDraftModel(id: "old", updatedAt: older))
        context.insert(makeDraftModel(id: "newest-b", updatedAt: newest))
        context.insert(makeDraftModel(id: "newest-a", updatedAt: newest))
        try context.save()
        let repository = CaptureRepository(container: container, clock: TestCaptureClock(newest))

        let saved = try await repository.saveDraft(mutation(id: "new-active", title: "New"), expectedRevision: 0)

        XCTAssertEqual(saved.returnDraftID, "newest-a")
    }

    func testClaimNextUsesFirstQueuedAtBeforeStableID() async throws {
        let clock = TestCaptureClock(referenceDate)
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let olderWithLaterID = try await enqueueRecord(repository, id: "z-older")
        clock.advance(by: 1)
        _ = try await enqueueRecord(repository, id: "a-newer")

        let claimed = try await repository.claimNext(at: clock.now(), retryPolicy: RetryPolicy())

        XCTAssertEqual(claimed?.id, olderWithLaterID.id)
    }

    func testClaimNextUsesStableIDTieBreakForMatchingFirstQueuedAt() async throws {
        let clock = TestCaptureClock(referenceDate)
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let beta = try await enqueueRecord(repository, id: "beta")
        let alpha = try await enqueueRecord(repository, id: "alpha")

        let first = try await repository.claimNext(at: clock.now(), retryPolicy: RetryPolicy())
        let second = try await repository.claimNext(at: clock.now(), retryPolicy: RetryPolicy())

        XCTAssertEqual(first?.id, alpha.id)
        XCTAssertEqual(second?.id, beta.id)
    }

    func testClaimNextMovesStaleWorkToAttentionAndClaimsNewerDueRecord() async throws {
        let clock = TestCaptureClock(referenceDate)
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let stale = try await enqueueRecord(repository, id: "stale")
        clock.advance(by: 8 * 86_400)
        let current = try await enqueueRecord(repository, id: "current")

        let claimed = try await repository.claimNext(at: clock.now(), retryPolicy: RetryPolicy())
        let staleAfterClaim = try await repository.record(id: stale.id)

        XCTAssertEqual(claimed?.id, current.id)
        XCTAssertEqual(staleAfterClaim?.state, .uncertain)
        XCTAssertNil(staleAfterClaim?.nextAttemptAt)
        XCTAssertEqual(staleAfterClaim?.safeError?.code, "requiresAttention")
    }

    func testClaimNextClaimsDueRetryButLeavesFutureRetryQueued() async throws {
        let clock = TestCaptureClock(referenceDate)
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let due = try await enqueueRecord(repository, id: "due")
        let future = try await enqueueRecord(repository, id: "future")
        let retryError = SafeDeliveryError(code: "temporary", message: nil, statusCode: 503, retryAfter: nil)
        _ = try await repository.markRetrying(
            recordID: due.id,
            nextAttemptAt: clock.now(),
            requiresManagedCheck: false,
            safeError: retryError,
            at: clock.now()
        )
        _ = try await repository.markRetrying(
            recordID: future.id,
            nextAttemptAt: clock.now().addingTimeInterval(60),
            requiresManagedCheck: false,
            safeError: retryError,
            at: clock.now()
        )

        let claimed = try await repository.claimNext(at: clock.now(), retryPolicy: RetryPolicy())
        let futureAfterClaim = try await repository.record(id: future.id)

        XCTAssertEqual(claimed?.id, due.id)
        XCTAssertEqual(futureAfterClaim?.state, .retrying)
        XCTAssertEqual(futureAfterClaim?.nextAttemptAt, clock.now().addingTimeInterval(60))
    }

    func testResumeUnauthorizedRetriesMakesOnlyUnauthorizedRetryDue() async throws {
        let clock = TestCaptureClock(referenceDate)
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let unauthorized = try await enqueueRecord(repository, id: "unauthorized")
        let other = try await enqueueRecord(repository, id: "other")
        _ = try await repository.markRetrying(
            recordID: unauthorized.id,
            nextAttemptAt: nil,
            requiresManagedCheck: false,
            safeError: SafeDeliveryError(code: "unauthorized", message: "Reconnect", statusCode: 401, retryAfter: nil),
            at: clock.now()
        )
        _ = try await repository.markRetrying(
            recordID: other.id,
            nextAttemptAt: nil,
            requiresManagedCheck: false,
            safeError: SafeDeliveryError(code: "temporary", message: nil, statusCode: 503, retryAfter: nil),
            at: clock.now()
        )

        let resumed = try await repository.resumeUnauthorizedRetries(at: clock.now())
        let unauthorizedAfterResume = try await repository.record(id: unauthorized.id)
        let otherAfterResume = try await repository.record(id: other.id)

        XCTAssertEqual(resumed, 1)
        XCTAssertEqual(unauthorizedAfterResume?.state, .retrying)
        XCTAssertEqual(unauthorizedAfterResume?.nextAttemptAt, clock.now())
        XCTAssertNil(otherAfterResume?.nextAttemptAt)
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

    private func enqueueRecord(_ repository: CaptureRepository, id: String) async throws -> CaptureRecordSnapshot {
        let draft = try await repository.saveDraft(mutation(id: id, title: id), expectedRevision: 0)
        return try await repository.enqueue(
            draftID: draft.id,
            expectedRevision: draft.revision,
            destination: .managed(databaseID: "database-1")
        )
    }

    private func makeDraftModel(id: String, updatedAt: Date) -> CaptureDraftModel {
        CaptureDraftModel(
            stableID: id,
            revision: 1,
            title: id,
            editorDocument: jsonData(["type": "doc", "content": []]),
            sourceDocument: nil,
            dispositionRawValue: DraftDisposition.active.rawValue,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
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
