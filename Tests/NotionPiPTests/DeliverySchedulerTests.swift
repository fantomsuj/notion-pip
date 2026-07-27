import Foundation
import os
import XCTest
@testable import NotionPiP

final class DeliverySchedulerTests: XCTestCase {
    func testScheduledRetryDrainsAfterRetryAfterDelay() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let record = try await seedRecord(repository)
        let transport = SchedulerDeliveryTransport(actions: [
            .failure(.http(status: 429, retryAfter: 0.05, message: "Slow down")),
            .receipt(DeliveryReceipt(remoteIdentity: "remote-page", fingerprint: nil)),
        ])
        let engine = DeliveryEngine(repository: repository, transport: transport)
        let scheduler = DeliveryScheduler(repository: repository, engine: engine)

        await scheduler.trigger()

        let fetchedRetrying = try await repository.record(id: record.id)
        let retrying = try XCTUnwrap(fetchedRetrying)
        XCTAssertEqual(retrying.state, .retrying)
        XCTAssertNotNil(retrying.nextAttemptAt)

        let delivered = try await waitForState(
            .delivered,
            recordID: record.id,
            repository: repository
        )
        XCTAssertEqual(delivered.remoteIdentity, "remote-page")
        let callCount = await transport.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testReconnectResumesUnauthorizedDelivery() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let record = try await seedRecord(repository)
        let transport = SchedulerDeliveryTransport(actions: [
            .failure(.http(status: 401, retryAfter: nil, message: "Reconnect")),
            .receipt(DeliveryReceipt(remoteIdentity: "remote-page", fingerprint: nil)),
        ])
        let engine = DeliveryEngine(repository: repository, transport: transport)
        let scheduler = DeliveryScheduler(repository: repository, engine: engine)

        await scheduler.trigger()

        let fetchedPaused = try await repository.record(id: record.id)
        let paused = try XCTUnwrap(fetchedPaused)
        XCTAssertEqual(paused.state, .retrying)
        XCTAssertNil(paused.nextAttemptAt)

        await scheduler.trigger(reconnected: true)

        let fetchedDelivered = try await repository.record(id: record.id)
        let delivered = try XCTUnwrap(fetchedDelivered)
        XCTAssertEqual(delivered.state, .delivered)
        let callCount = await transport.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testClaimSaveFailureRetriesLocallyAndEventuallyDelivers() async throws {
        let failure = CaptureSaveFailure()
        let repository = try CaptureRepository(
            inMemory: true,
            beforeSave: failure.check
        )
        let record = try await seedRecord(repository)
        let transport = SchedulerDeliveryTransport(actions: [
            .receipt(DeliveryReceipt(remoteIdentity: "remote-page", fingerprint: nil)),
        ])
        let engine = DeliveryEngine(repository: repository, transport: transport)
        let scheduler = DeliveryScheduler(
            repository: repository,
            engine: engine,
            recoveryRetryDelay: 0.02
        )
        failure.failNext(.claimNext)

        await scheduler.trigger()

        let delivered = try await waitForState(
            .delivered,
            recordID: record.id,
            repository: repository
        )
        XCTAssertEqual(delivered.remoteIdentity, "remote-page")
        let callCount = await transport.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testMarkDeliveredSaveFailureRecoversJournalWithoutRecreatingPage() async throws {
        let failure = CaptureSaveFailure()
        let repository = try CaptureRepository(
            inMemory: true,
            beforeSave: failure.check
        )
        let record = try await seedRecord(
            repository,
            destination: .pageParent(pageID: "parent-page")
        )
        let transport = JournaledSchedulerTransport(repository: repository)
        let engine = DeliveryEngine(repository: repository, transport: transport)
        let scheduler = DeliveryScheduler(
            repository: repository,
            engine: engine,
            recoveryRetryDelay: 0.02
        )
        failure.failNext(.markDelivered)

        await scheduler.trigger()

        _ = try await waitForState(
            .delivered,
            recordID: record.id,
            repository: repository
        )
        let remoteCreateCount = await transport.remoteCreateCount
        XCTAssertEqual(remoteCreateCount, 1)
    }

    func testRetryTransitionSaveFailureRecoversWithoutExternalTrigger() async throws {
        let failure = CaptureSaveFailure()
        let repository = try CaptureRepository(
            inMemory: true,
            beforeSave: failure.check
        )
        let record = try await seedRecord(repository)
        let transport = SchedulerDeliveryTransport(actions: [
            .failure(.http(status: 429, retryAfter: 0, message: "Slow down")),
            .receipt(DeliveryReceipt(remoteIdentity: "remote-page", fingerprint: nil)),
        ])
        let engine = DeliveryEngine(repository: repository, transport: transport)
        let scheduler = DeliveryScheduler(
            repository: repository,
            engine: engine,
            recoveryRetryDelay: 0.02
        )
        failure.failNext(.deliveryTransition)

        await scheduler.trigger()

        _ = try await waitForState(
            .delivered,
            recordID: record.id,
            repository: repository
        )
        let callCount = await transport.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testUnauthorizedResumptionSaveFailureRetriesWithoutAnotherReconnect() async throws {
        let failure = CaptureSaveFailure()
        let repository = try CaptureRepository(
            inMemory: true,
            beforeSave: failure.check
        )
        let record = try await seedRecord(repository)
        let transport = SchedulerDeliveryTransport(actions: [
            .failure(.http(status: 401, retryAfter: nil, message: "Reconnect")),
            .receipt(DeliveryReceipt(remoteIdentity: "remote-page", fingerprint: nil)),
        ])
        let engine = DeliveryEngine(repository: repository, transport: transport)
        let scheduler = DeliveryScheduler(
            repository: repository,
            engine: engine,
            recoveryRetryDelay: 0.02
        )
        await scheduler.trigger()
        failure.failNext(.unauthorizedResumption)

        await scheduler.trigger(reconnected: true)

        _ = try await waitForState(
            .delivered,
            recordID: record.id,
            repository: repository
        )
        let callCount = await transport.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testBoundedDeliveryHealthClearsAfterSuccessfulRecoveryDrain() async throws {
        let failure = CaptureSaveFailure()
        let repository = try CaptureRepository(
            inMemory: true,
            beforeSave: failure.check
        )
        let record = try await seedRecord(repository)
        let transport = SchedulerDeliveryTransport(actions: [
            .receipt(DeliveryReceipt(remoteIdentity: "remote-page", fingerprint: nil)),
        ])
        let engine = DeliveryEngine(repository: repository, transport: transport)
        let scheduler = DeliveryScheduler(
            repository: repository,
            engine: engine,
            recoveryRetryDelay: 0.2
        )
        failure.failNext(.claimNext)

        await scheduler.trigger()

        let failedHealth = await scheduler.healthSnapshot()
        XCTAssertTrue(failedHealth.hasDeliveryFailure)

        _ = try await waitForState(
            .delivered,
            recordID: record.id,
            repository: repository
        )
        let recoveredHealth = await scheduler.healthSnapshot()
        XCTAssertFalse(recoveredHealth.hasDeliveryFailure)
    }

    func testRetentionRunsOnlyAfterStartupRecoveryCompletes() async throws {
        let events = SchedulerEventRecorder()
        let repository = try CaptureRepository(inMemory: true)
        let engine = DeliveryEngine(
            repository: repository,
            transport: SchedulerDeliveryTransport(actions: []),
            startupRecovery: { _ in
                await events.append("recovery")
                return 0
            }
        )
        let scheduler = DeliveryScheduler(
            repository: repository,
            engine: engine,
            retentionStartupDelay: 0.01,
            retentionOperation: { _ in
                await events.append("retention")
                return RetentionResult(deletedRecords: 0, deletedDrafts: 0)
            }
        )

        await scheduler.trigger()
        try await waitUntil {
            await events.values.count == 2
        }

        let values = await events.values
        XCTAssertEqual(values, ["recovery", "retention"])
    }

    func testConcurrentTriggerCannotScheduleRetentionBeforeBlockedRecoveryCompletes() async throws {
        let recovery = BlockingStartupRecovery()
        let retention = SchedulerEventRecorder()
        let repository = try CaptureRepository(inMemory: true)
        let engine = DeliveryEngine(
            repository: repository,
            transport: SchedulerDeliveryTransport(actions: []),
            startupRecovery: { _ in
                try await recovery.run()
            }
        )
        let scheduler = DeliveryScheduler(
            repository: repository,
            engine: engine,
            retentionStartupDelay: 0.01,
            retentionOperation: { _ in
                await retention.append("retention")
                return RetentionResult(deletedRecords: 0, deletedDrafts: 0)
            }
        )

        let firstTrigger = Task {
            await scheduler.trigger()
        }
        try await recovery.waitUntilEntered()
        await scheduler.trigger()
        try await Task.sleep(for: .milliseconds(50))

        let prematureRetention = await retention.values
        XCTAssertTrue(prematureRetention.isEmpty)

        await recovery.finish()
        await firstTrigger.value
        try await waitUntil {
            await retention.values == ["retention"]
        }
    }

    func testStartupRetentionCatchesUpAfterThirtyOneDaysUnused() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 20_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository)
        let initialEngine = DeliveryEngine(
            repository: repository,
            transport: SchedulerDeliveryTransport(actions: [
                .receipt(DeliveryReceipt(remoteIdentity: "remote-page", fingerprint: nil)),
            ]),
            clock: clock
        )
        _ = try await initialEngine.drain()
        clock.advance(by: 31 * 86_400)

        let scheduler = DeliveryScheduler(
            repository: repository,
            engine: DeliveryEngine(
                repository: repository,
                transport: SchedulerDeliveryTransport(actions: []),
                clock: clock
            ),
            clock: clock,
            retentionStartupDelay: 0.01
        )
        await scheduler.trigger()

        try await waitUntil {
            try await repository.record(id: record.id) == nil
        }
        let retainedDraft = try await repository.draft(id: record.draftID)
        XCTAssertNil(retainedDraft)
    }

    func testRetentionFailureRetriesAndClearsBoundedHealth() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let retention = FlakyRetentionOperation()
        let scheduler = DeliveryScheduler(
            repository: repository,
            engine: DeliveryEngine(
                repository: repository,
                transport: SchedulerDeliveryTransport(actions: [])
            ),
            retentionStartupDelay: 0.01,
            retentionRetryDelay: 0.2,
            retentionOperation: { date in
                try await retention.run(at: date)
            }
        )

        await scheduler.trigger()
        try await waitUntil {
            await retention.callCount >= 1
        }
        let failedHealth = await scheduler.healthSnapshot()
        XCTAssertTrue(failedHealth.hasRetentionFailure)

        try await waitUntil {
            await retention.callCount >= 2
        }
        let recoveredHealth = await scheduler.healthSnapshot()
        XCTAssertFalse(recoveredHealth.hasRetentionFailure)
    }

    private func seedRecord(
        _ repository: CaptureRepository,
        destination: CaptureDestination = .managed(databaseID: "database-1")
    ) async throws -> CaptureRecordSnapshot {
        let draft = try await repository.saveDraft(
            DraftMutation(
                id: UUID().uuidString,
                title: "Scheduled capture",
                editorDocument: jsonData([
                    "type": "doc",
                    "content": [["type": "paragraph"]],
                ]),
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

    private func waitForState(
        _ state: DeliveryState,
        recordID: String,
        repository: CaptureRepository
    ) async throws -> CaptureRecordSnapshot {
        for _ in 0 ..< 100 {
            if let record = try await repository.record(id: recordID),
               record.state == state
            {
                return record
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let finalRecord = try await repository.record(id: recordID)
        return try XCTUnwrap(finalRecord)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping () async throws -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SchedulerTestError.timedOut
    }
}

private enum SchedulerTestError: Error {
    case timedOut
}

private actor SchedulerEventRecorder {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private actor FlakyRetentionOperation {
    struct ExpectedFailure: Error {}

    private(set) var callCount = 0

    func run(at _: Date) throws -> RetentionResult {
        callCount += 1
        if callCount == 1 {
            throw ExpectedFailure()
        }
        return RetentionResult(deletedRecords: 0, deletedDrafts: 0)
    }
}

private actor BlockingStartupRecovery {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func run() async throws -> Int {
        entered = true
        await withCheckedContinuation { continuation = $0 }
        return 0
    }

    func waitUntilEntered() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !entered {
            guard clock.now < deadline else {
                throw SchedulerTestError.timedOut
            }
            await Task.yield()
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private final class CaptureSaveFailure: Sendable {
    struct ExpectedFailure: Error {}

    private let operation = OSAllocatedUnfairLock<CaptureRepositorySaveOperation?>(
        initialState: nil
    )

    func failNext(_ operation: CaptureRepositorySaveOperation) {
        self.operation.withLock { $0 = operation }
    }

    func check(_ operation: CaptureRepositorySaveOperation) throws {
        try self.operation.withLock {
            if $0 == operation {
                $0 = nil
                throw ExpectedFailure()
            }
        }
    }
}

private actor SchedulerDeliveryTransport: CaptureDeliveryTransport {
    enum Action: Sendable {
        case receipt(DeliveryReceipt)
        case failure(DeliveryTransportError)
    }

    private var actions: [Action]
    private(set) var callCount = 0

    init(actions: [Action]) {
        self.actions = actions
    }

    func findManagedCapture(
        captureID: String,
        databaseID: String
    ) async throws -> DeliveryReceipt? {
        nil
    }

    func createManaged(
        _ record: CaptureRecordSnapshot,
        databaseID: String
    ) async throws -> DeliveryReceipt {
        callCount += 1
        switch actions.removeFirst() {
        case let .receipt(receipt):
            return receipt
        case let .failure(error):
            throw error
        }
    }

    func appendManual(
        _ record: CaptureRecordSnapshot,
        pageID: String
    ) async throws -> DeliveryReceipt {
        throw DeliveryTransportError.transport(message: "Unexpected manual delivery")
    }
}

private actor JournaledSchedulerTransport: CaptureDeliveryTransport {
    private let repository: CaptureRepository
    private(set) var remoteCreateCount = 0

    init(repository: CaptureRepository) {
        self.repository = repository
    }

    func findManagedCapture(
        captureID: String,
        databaseID: String
    ) async throws -> DeliveryReceipt? {
        nil
    }

    func createManaged(
        _ record: CaptureRecordSnapshot,
        databaseID: String
    ) async throws -> DeliveryReceipt {
        throw DeliveryTransportError.transport(message: "Unexpected managed delivery")
    }

    func appendManual(
        _ record: CaptureRecordSnapshot,
        pageID: String
    ) async throws -> DeliveryReceipt {
        throw DeliveryTransportError.transport(message: "Unexpected manual delivery")
    }

    func createChildPage(
        _ record: CaptureRecordSnapshot,
        parentPageID: String
    ) async throws -> DeliveryReceipt {
        if record.operationJournal == nil {
            remoteCreateCount += 1
            _ = try await repository.updateDeliveryJournal(
                recordID: record.id,
                journal: jsonData([
                    "stage": "captureDelivery",
                    "pageID": "journaled-page",
                    "titlePropertyName": "title",
                    "nextBatchIndex": 1,
                    "totalBatchCount": 1,
                ])
            )
        }
        return DeliveryReceipt(remoteIdentity: "journaled-page", fingerprint: nil)
    }
}
