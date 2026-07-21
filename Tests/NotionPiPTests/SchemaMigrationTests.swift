import Foundation
import SwiftData
import XCTest
@testable import NotionPiP

final class SchemaMigrationTests: XCTestCase {
    func testV1SchemaCanReopenAPersistedDraft() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("NotionPiP.store")
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 1_000))
        var repository: CaptureRepository? = try CaptureRepository(storeURL: storeURL, clock: clock)
        _ = try await repository?.saveDraft(
            DraftMutation(
                id: "capture-reopen",
                title: "Persisted",
                editorDocument: jsonData(["type": "doc", "content": []]),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        repository = nil

        let reopened = try CaptureRepository(storeURL: storeURL, clock: clock)
        let draft = try await reopened.draft(id: "capture-reopen")

        XCTAssertEqual(draft?.title, "Persisted")
        XCTAssertEqual(draft?.revision, 1)
        XCTAssertEqual(NotionPiPSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(NotionPiPMigrationPlan.schemas.count, 1)
    }

    func testDeliveryStateRawValuesAreStable() {
        XCTAssertEqual(DeliveryState.queued.rawValue, "queued")
        XCTAssertEqual(DeliveryState.inFlight.rawValue, "inFlight")
        XCTAssertEqual(DeliveryState.delivered.rawValue, "delivered")
        XCTAssertEqual(DeliveryState.retrying.rawValue, "retrying")
        XCTAssertEqual(DeliveryState.blockedConflict.rawValue, "blockedConflict")
        XCTAssertEqual(DeliveryState.uncertain.rawValue, "uncertain")
    }
}
