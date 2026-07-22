import Foundation
import XCTest
@testable import NotionPiP

final class DeliveryEngineTests: XCTestCase {
    func testClaimIsPersistedInFlightBeforeTransportAndConcurrentDrainsHaveOneClaimant() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, destination: .managed(databaseID: "database-1"))
        let transport = ScriptedDeliveryTransport(
            repositoryToInspect: repository,
            createActions: [.receipt(DeliveryReceipt(remoteIdentity: "page-1", fingerprint: "fp-1"))],
            delayNanoseconds: 20_000_000
        )
        let engine = DeliveryEngine(repository: repository, transport: transport, clock: clock)

        async let first = engine.drain()
        async let second = engine.drain()
        _ = try await (first, second)

        let createCallCount = await transport.createCallCount
        let observedState = await transport.observedStateDuringCreate
        let stored = try await fetchedRecord(repository, id: record.id)
        XCTAssertEqual(createCallCount, 1)
        XCTAssertEqual(observedState, .inFlight)
        XCTAssertEqual(stored.state, .delivered)
    }

    func testUnauthorizedPausesForReconnectUsingRetryingStateAndSafeMetadata() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, destination: .managed(databaseID: "database-1"))
        let transport = ScriptedDeliveryTransport(
            createActions: [.failure(.http(status: 401, retryAfter: nil, message: "Reconnect required"))]
        )
        let engine = DeliveryEngine(repository: repository, transport: transport, clock: clock)

        let summary = try await engine.drain()
        let stored = try await fetchedRecord(repository, id: record.id)

        XCTAssertTrue(summary.pausedForReconnect)
        XCTAssertEqual(stored.state, .retrying)
        XCTAssertNil(stored.nextAttemptAt)
        XCTAssertEqual(stored.safeError?.code, "unauthorized")
        XCTAssertEqual(stored.safeError?.statusCode, 401)
        _ = try await engine.drain()
        let createCallCount = await transport.createCallCount
        XCTAssertEqual(createCallCount, 1)
    }

    func testUnauthorizedStopsDrainBeforeClaimingLaterRecords() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let first = try await seedRecord(
            repository,
            id: "a-first",
            destination: .managed(databaseID: "database-1")
        )
        let second = try await seedRecord(
            repository,
            id: "b-second",
            destination: .managed(databaseID: "database-1")
        )
        let transport = ScriptedDeliveryTransport(
            createActions: [
                .failure(.http(status: 401, retryAfter: nil, message: "Reconnect")),
                .receipt(DeliveryReceipt(remoteIdentity: "must-not-send", fingerprint: nil)),
            ]
        )
        let engine = DeliveryEngine(repository: repository, transport: transport, clock: clock)

        let summary = try await engine.drain()

        let events = await transport.events
        let firstStored = try await fetchedRecord(repository, id: first.id)
        let secondStored = try await fetchedRecord(repository, id: second.id)
        XCTAssertTrue(summary.pausedForReconnect)
        XCTAssertEqual(events, ["create"])
        XCTAssertEqual(firstStored.state, .retrying)
        XCTAssertNil(firstStored.nextAttemptAt)
        XCTAssertEqual(secondStored.state, .queued)
        XCTAssertEqual(secondStored.attemptCount, 0)
    }

    func testManagedTimeoutChecksCaptureIDBeforeCreatingAgain() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, destination: .managed(databaseID: "database-1"))
        let transport = ScriptedDeliveryTransport(
            createActions: [
                .failure(.http(status: 408, retryAfter: nil, message: "Timed out")),
                .receipt(DeliveryReceipt(remoteIdentity: "page-created", fingerprint: "fp")),
            ],
            findActions: [.match(nil)]
        )
        let engine = DeliveryEngine(repository: repository, transport: transport, clock: clock)

        _ = try await engine.drain()
        let retrying = try await fetchedRecord(repository, id: record.id)
        XCTAssertEqual(retrying.state, .retrying)
        XCTAssertTrue(retrying.requiresManagedCheck)

        clock.advance(by: 10)
        _ = try await engine.drain()

        let events = await transport.events
        let delivered = try await fetchedRecord(repository, id: record.id)
        XCTAssertEqual(events, ["create", "find", "create"])
        XCTAssertEqual(delivered.state, .delivered)
    }

    func testManagedLookupFindingAmbiguousCreateMarksDeliveredWithoutSecondCreate() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, destination: .managed(databaseID: "database-1"))
        let transport = ScriptedDeliveryTransport(
            createActions: [.failure(.ambiguous(message: "Connection lost"))],
            findActions: [.match(DeliveryReceipt(remoteIdentity: "page-found", fingerprint: "fp"))]
        )
        let engine = DeliveryEngine(repository: repository, transport: transport, clock: clock)

        _ = try await engine.drain()
        clock.advance(by: 10)
        _ = try await engine.drain()

        let events = await transport.events
        let delivered = try await fetchedRecord(repository, id: record.id)
        XCTAssertEqual(events, ["create", "find"])
        XCTAssertEqual(delivered.remoteIdentity, "page-found")
    }

    func testManagedServerFailureAlsoChecksCaptureIDBeforeRetry() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, destination: .managed(databaseID: "database-1"))
        let transport = ScriptedDeliveryTransport(
            createActions: [
                .failure(.http(status: 503, retryAfter: nil, message: "Unavailable")),
                .receipt(DeliveryReceipt(remoteIdentity: "page-created", fingerprint: nil)),
            ],
            findActions: [.match(nil)]
        )
        let engine = DeliveryEngine(repository: repository, transport: transport, clock: clock)

        _ = try await engine.drain()
        clock.advance(by: 10)
        _ = try await engine.drain()

        let events = await transport.events
        let stored = try await fetchedRecord(repository, id: record.id)
        XCTAssertEqual(events, ["create", "find", "create"])
        XCTAssertEqual(stored.state, .delivered)
    }

    func testAmbiguousManualAppendBecomesUncertain() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, destination: .manual(pageID: "page-1"))
        let transport = ScriptedDeliveryTransport(appendActions: [.failure(.ambiguous(message: "No response"))])
        let engine = DeliveryEngine(repository: repository, transport: transport, clock: clock)

        _ = try await engine.drain()

        let stored = try await fetchedRecord(repository, id: record.id)
        XCTAssertEqual(stored.state, .uncertain)
        XCTAssertEqual(stored.safeError?.code, "ambiguousManualAppend")
    }

    func testConflictBecomesBlockedConflict() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, destination: .managed(databaseID: "database-1"))
        let transport = ScriptedDeliveryTransport(
            createActions: [.failure(.http(status: 409, retryAfter: nil, message: "Fingerprint changed"))]
        )
        let engine = DeliveryEngine(repository: repository, transport: transport, clock: clock)

        _ = try await engine.drain()

        let stored = try await fetchedRecord(repository, id: record.id)
        XCTAssertEqual(stored.state, .blockedConflict)
    }

    func testRateLimitHonorsRetryAfter() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let clock = TestCaptureClock(now)
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, destination: .manual(pageID: "page-1"))
        let transport = ScriptedDeliveryTransport(
            appendActions: [.failure(.http(status: 429, retryAfter: 75, message: "Slow down"))]
        )
        let engine = DeliveryEngine(repository: repository, transport: transport, clock: clock)

        _ = try await engine.drain()

        let stored = try await fetchedRecord(repository, id: record.id)
        XCTAssertEqual(stored.state, .retrying)
        XCTAssertEqual(stored.nextAttemptAt, now.addingTimeInterval(75))
        XCTAssertEqual(stored.safeError?.retryAfter, 75)
    }

    func testBackoffIsBoundedAndSevenDayWorkMovesToAttention() async throws {
        let policy = RetryPolicy(baseDelay: 5, maximumDelay: 3_600, attentionInterval: 7 * 86_400)
        XCTAssertEqual(policy.delay(forAttempt: 100), 3_600)
        XCTAssertEqual(policy.delay(forAttempt: 1, retryAfter: 50_000), 50_000)

        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, destination: .managed(databaseID: "database-1"))
        clock.advance(by: 7 * 86_400)
        let transport = ScriptedDeliveryTransport()
        let engine = DeliveryEngine(
            repository: repository,
            transport: transport,
            clock: clock,
            retryPolicy: policy
        )

        _ = try await engine.drain()

        let stored = try await fetchedRecord(repository, id: record.id)
        XCTAssertEqual(stored.state, .uncertain)
        XCTAssertEqual(stored.safeError?.code, "requiresAttention")
        let totalDeliveryCallCount = await transport.totalDeliveryCallCount
        XCTAssertEqual(totalDeliveryCallCount, 0)
    }

    func testInterruptedInFlightRecoveryUsesManagedCheckAndManualUncertain() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Recovery.store")

        do {
            let initialRepository = try CaptureRepository(storeURL: storeURL, clock: clock)
            _ = try await seedRecord(
                initialRepository,
                id: "managed",
                destination: .managed(databaseID: "database-1")
            )
            _ = try await seedRecord(
                initialRepository,
                id: "manual",
                destination: .manual(pageID: "page-1")
            )
            _ = try await initialRepository.claimNext(at: clock.now(), retryPolicy: RetryPolicy())
            _ = try await initialRepository.claimNext(at: clock.now(), retryPolicy: RetryPolicy())
        }

        let repository = try CaptureRepository(storeURL: storeURL, clock: clock)

        let engine = DeliveryEngine(
            repository: repository,
            transport: ScriptedDeliveryTransport(),
            clock: clock
        )
        let recovered = try await engine.recoverInterruptedWork()

        XCTAssertEqual(recovered, 2)
        let managedStored = try await fetchedRecord(repository, id: "managed")
        XCTAssertEqual(managedStored.state, .retrying)
        XCTAssertTrue(managedStored.requiresManagedCheck)
        let manualStored = try await fetchedRecord(repository, id: "manual")
        XCTAssertEqual(manualStored.state, .uncertain)
    }

    func testFailedStartupRecoveryIsRetriedOnNextDrain() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let recovery = FlakyStartupRecovery()
        let engine = DeliveryEngine(
            repository: repository,
            transport: ScriptedDeliveryTransport(),
            clock: clock,
            startupRecovery: { date in
                try await recovery.recover(at: date)
            }
        )

        do {
            _ = try await engine.drain()
            XCTFail("Expected first startup recovery to fail")
        } catch is FlakyStartupRecovery.ExpectedFailure {}

        _ = try await engine.drain()
        let callCount = await recovery.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testReplacementJournalIsPersistedBeforeArchiveCanStart() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        let record = try await seedRecord(repository, destination: .managed(databaseID: "database-1"))

        let journaled = try await repository.recordReplacementBeforeArchive(
            recordID: record.id,
            replacementBlockIDs: ["new-2", "new-1"],
            blocksToArchive: ["old-2", "old-1"]
        )

        XCTAssertEqual(
            String(decoding: try XCTUnwrap(journaled.operationJournal), as: UTF8.self),
            #"{"blocksToArchive":["old-1","old-2"],"replacementBlockIDs":["new-1","new-2"],"stage":"replacementWrittenAwaitingArchive"}"#
        )
    }

    private func seedRecord(
        _ repository: CaptureRepository,
        id: String = "capture-1",
        destination: CaptureDestination
    ) async throws -> CaptureRecordSnapshot {
        let draft = try await repository.saveDraft(
            DraftMutation(
                id: id,
                title: "Queue item \(id)",
                editorDocument: jsonData(["type": "doc", "content": []]),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        return try await repository.enqueue(
            draftID: id,
            expectedRevision: draft.revision,
            destination: destination
        )
    }

    private func fetchedRecord(
        _ repository: CaptureRepository,
        id: String
    ) async throws -> CaptureRecordSnapshot {
        let record = try await repository.record(id: id)
        return try XCTUnwrap(record)
    }
}

private actor FlakyStartupRecovery {
    struct ExpectedFailure: Error {}

    private(set) var callCount = 0

    func recover(at _: Date) throws -> Int {
        callCount += 1
        if callCount == 1 { throw ExpectedFailure() }
        return 0
    }
}

private actor ScriptedDeliveryTransport: CaptureDeliveryTransport {
    enum Action: Sendable {
        case receipt(DeliveryReceipt)
        case match(DeliveryReceipt?)
        case failure(DeliveryTransportError)
    }

    private let repositoryToInspect: CaptureRepository?
    private var createActions: [Action]
    private var findActions: [Action]
    private var appendActions: [Action]
    private let delayNanoseconds: UInt64
    private(set) var events: [String] = []
    private(set) var observedStateDuringCreate: DeliveryState?

    init(
        repositoryToInspect: CaptureRepository? = nil,
        createActions: [Action] = [],
        findActions: [Action] = [],
        appendActions: [Action] = [],
        delayNanoseconds: UInt64 = 0
    ) {
        self.repositoryToInspect = repositoryToInspect
        self.createActions = createActions
        self.findActions = findActions
        self.appendActions = appendActions
        self.delayNanoseconds = delayNanoseconds
    }

    var createCallCount: Int { events.filter { $0 == "create" }.count }
    var totalDeliveryCallCount: Int { events.filter { $0 != "find" }.count }

    func findManagedCapture(captureID: String, databaseID: String) async throws -> DeliveryReceipt? {
        events.append("find")
        return switch pop(&findActions, fallback: Action.match(nil)) {
        case let .match(receipt): receipt
        case let .failure(error): throw error
        case .receipt: fatalError("Unexpected scripted receipt for lookup")
        }
    }

    func createManaged(_ record: CaptureRecordSnapshot, databaseID: String) async throws -> DeliveryReceipt {
        events.append("create")
        if let repositoryToInspect {
            observedStateDuringCreate = try await repositoryToInspect.record(id: record.id)?.state
        }
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try receipt(from: pop(
            &createActions,
            fallback: .receipt(DeliveryReceipt(remoteIdentity: "managed-default", fingerprint: nil))
        ))
    }

    func appendManual(_ record: CaptureRecordSnapshot, pageID: String) async throws -> DeliveryReceipt {
        events.append("append")
        return try receipt(from: pop(
            &appendActions,
            fallback: .receipt(DeliveryReceipt(remoteIdentity: pageID, fingerprint: nil))
        ))
    }

    private func receipt(from action: Action) throws -> DeliveryReceipt {
        switch action {
        case let .receipt(receipt): receipt
        case let .failure(error): throw error
        case .match: fatalError("Unexpected scripted lookup result for delivery")
        }
    }

    private func pop(_ actions: inout [Action], fallback: Action) -> Action {
        actions.isEmpty ? fallback : actions.removeFirst()
    }
}
