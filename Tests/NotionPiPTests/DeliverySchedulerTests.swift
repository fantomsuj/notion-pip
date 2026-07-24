import Foundation
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

    private func seedRecord(
        _ repository: CaptureRepository
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
            destination: .managed(databaseID: "database-1")
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
