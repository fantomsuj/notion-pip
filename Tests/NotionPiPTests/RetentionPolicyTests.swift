import Foundation
import XCTest
@testable import NotionPiP

final class RetentionPolicyTests: XCTestCase {
    func testThirtyDayCleanupDeletesOnlyOrdinaryDeliveredAndItsAbandonedDraft() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 20_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, id: "ordinary")
        let engine = DeliveryEngine(
            repository: repository,
            transport: RetentionTransport(),
            clock: clock
        )
        _ = try await engine.drain()
        let delivered = try await fetch(repository, id: record.id)
        XCTAssertEqual(delivered.state, .delivered)

        clock.advance(by: 31 * 86_400)
        let result = try await repository.applyRetention(
            at: clock.now(),
            policy: RetentionPolicy()
        )

        XCTAssertEqual(result, RetentionResult(deletedRecords: 1, deletedDrafts: 1))
        let retainedRecord = try await repository.record(id: record.id)
        let retainedDraft = try await repository.draft(id: record.draftID)
        XCTAssertNil(retainedRecord)
        XCTAssertNil(retainedDraft)
    }

    func testCleanupPreservesUnresolvedRecordsAndAllWorkNeededForRecovery() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 20_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let queued = try await seedRecord(repository, id: "queued")
        let uncertain = try await seedRecord(repository, id: "uncertain", destination: .manual(pageID: "page-1"))
        _ = try await repository.claimNext(at: clock.now(), retryPolicy: RetryPolicy())
        _ = try await repository.claimNext(at: clock.now(), retryPolicy: RetryPolicy())
        _ = try await repository.recoverInterruptedWork(at: clock.now())
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "active",
                title: "Still editing",
                editorDocument: jsonData(["type": "doc", "content": []]),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )

        clock.advance(by: 31 * 86_400)
        let result = try await repository.applyRetention(at: clock.now(), policy: RetentionPolicy())

        XCTAssertEqual(result, RetentionResult(deletedRecords: 0, deletedDrafts: 0))
        let queuedRecord = try await repository.record(id: queued.id)
        let uncertainRecord = try await fetch(repository, id: uncertain.id)
        let queuedDraft = try await repository.draft(id: queued.draftID)
        let uncertainDraft = try await repository.draft(id: uncertain.draftID)
        let activeDraft = try await repository.draft(id: "active")
        XCTAssertNotNil(queuedRecord)
        XCTAssertEqual(uncertainRecord.state, .uncertain)
        XCTAssertNotNil(queuedDraft)
        XCTAssertNotNil(uncertainDraft)
        XCTAssertNotNil(activeDraft)
    }

    func testCleanupPreservesDeliveredRecordWithUnresolvedOperationJournal() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 20_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, id: "journaled")
        let engine = DeliveryEngine(
            repository: repository,
            transport: RetentionTransport(),
            clock: clock
        )
        _ = try await engine.drain()
        _ = try await repository.recordReplacementBeforeArchive(
            recordID: record.id,
            replacementBlockIDs: ["new"],
            blocksToArchive: ["old"]
        )

        clock.advance(by: 31 * 86_400)
        let result = try await repository.applyRetention(at: clock.now(), policy: RetentionPolicy())

        let retainedRecord = try await repository.record(id: record.id)
        let retainedDraft = try await repository.draft(id: record.draftID)
        XCTAssertEqual(result, RetentionResult(deletedRecords: 0, deletedDrafts: 0))
        XCTAssertNotNil(retainedRecord)
        XCTAssertNotNil(retainedDraft)
    }

    func testCleanupPreservesEveryProtectedRecordAndDraftState() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 20_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)

        let journaled = try await seedRecord(repository, id: "journaled")
        _ = try await DeliveryEngine(
            repository: repository,
            transport: RetentionTransport(),
            clock: clock
        ).drain()
        _ = try await repository.recordReplacementBeforeArchive(
            recordID: journaled.id,
            replacementBlockIDs: ["new"],
            blocksToArchive: ["old"]
        )

        let inFlight = try await seedRecord(repository, id: "in-flight")
        _ = try await repository.claimNext(at: clock.now(), retryPolicy: RetryPolicy())
        let queued = try await seedRecord(repository, id: "queued")
        let retrying = try await seedRecord(repository, id: "retrying")
        _ = try await repository.markRetrying(
            recordID: retrying.id,
            nextAttemptAt: clock.now().addingTimeInterval(60),
            requiresManagedCheck: false,
            safeError: safeError(code: "retrying"),
            at: clock.now()
        )
        let uncertain = try await seedRecord(repository, id: "uncertain")
        _ = try await repository.markUncertain(
            recordID: uncertain.id,
            safeError: safeError(code: "uncertain"),
            at: clock.now()
        )
        let conflict = try await seedRecord(repository, id: "conflict")
        _ = try await repository.markBlockedConflict(
            recordID: conflict.id,
            safeError: safeError(code: "conflict"),
            at: clock.now()
        )
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "protected-stashed",
                title: "Stashed",
                editorDocument: jsonData(["type": "doc", "content": []]),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "protected-active",
                title: "Active",
                editorDocument: jsonData(["type": "doc", "content": []]),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )

        clock.advance(by: 31 * 86_400)
        let result = try await repository.applyRetention(
            at: clock.now(),
            policy: RetentionPolicy()
        )

        let retainedInFlight = try await fetch(repository, id: inFlight.id)
        let retainedQueued = try await fetch(repository, id: queued.id)
        let retainedRetrying = try await fetch(repository, id: retrying.id)
        let retainedUncertain = try await fetch(repository, id: uncertain.id)
        let retainedConflict = try await fetch(repository, id: conflict.id)
        let retainedJournaled = try await repository.record(id: journaled.id)
        let retainedStashed = try await repository.draft(id: "protected-stashed")
        let retainedActive = try await repository.draft(id: "protected-active")
        XCTAssertEqual(result, RetentionResult(deletedRecords: 0, deletedDrafts: 0))
        XCTAssertEqual(retainedInFlight.state, .inFlight)
        XCTAssertEqual(retainedQueued.state, .queued)
        XCTAssertEqual(retainedRetrying.state, .retrying)
        XCTAssertEqual(retainedUncertain.state, .uncertain)
        XCTAssertEqual(retainedConflict.state, .blockedConflict)
        XCTAssertNotNil(retainedJournaled)
        XCTAssertEqual(retainedStashed?.disposition, .stashed)
        XCTAssertEqual(retainedActive?.disposition, .active)
    }

    private func seedRecord(
        _ repository: CaptureRepository,
        id: String,
        destination: CaptureDestination = .managed(databaseID: "database-1")
    ) async throws -> CaptureRecordSnapshot {
        let draft = try await repository.saveDraft(
            DraftMutation(
                id: id,
                title: id,
                editorDocument: jsonData(["type": "doc", "content": []]),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        return try await repository.enqueue(
            draftID: draft.id,
            expectedRevision: draft.revision,
            destination: destination
        )
    }

    private func fetch(_ repository: CaptureRepository, id: String) async throws -> CaptureRecordSnapshot {
        let record = try await repository.record(id: id)
        return try XCTUnwrap(record)
    }

    private func safeError(code: String) -> SafeDeliveryError {
        SafeDeliveryError(
            code: code,
            message: "Safe test error",
            statusCode: nil,
            retryAfter: nil
        )
    }
}

private actor RetentionTransport: CaptureDeliveryTransport {
    func findManagedCapture(captureID: String, databaseID: String) async throws -> DeliveryReceipt? { nil }

    func createManaged(_ record: CaptureRecordSnapshot, databaseID: String) async throws -> DeliveryReceipt {
        DeliveryReceipt(remoteIdentity: "page-\(record.id)", fingerprint: nil)
    }

    func appendManual(_ record: CaptureRecordSnapshot, pageID: String) async throws -> DeliveryReceipt {
        DeliveryReceipt(remoteIdentity: pageID, fingerprint: nil)
    }
}
