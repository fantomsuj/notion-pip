import Foundation
import SwiftData
import XCTest
@testable import NotionPiP

final class SchemaMigrationTests: XCTestCase {
    func testV1StoreMigratesToV2WithoutLosingExistingDraft() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("V1-to-V2.store")
        let v1Schema = Schema(versionedSchema: NotionPiPSchemaV1.self)
        let v1Configuration = ModelConfiguration(
            schema: v1Schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        do {
            let v1Container = try ModelContainer(
                for: v1Schema,
                configurations: v1Configuration
            )
            let context = ModelContext(v1Container)
            context.insert(
                CaptureDraftModel(
                    stableID: "legacy-draft",
                    revision: 1,
                    title: "Preserved",
                    editorDocument: jsonData(["type": "doc", "content": []]),
                    sourceDocument: nil,
                    dispositionRawValue: DraftDisposition.active.rawValue,
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
            try context.save()
        }

        let migratedContainer = try NotionPiPPersistence.makeContainer(storeURL: storeURL)
        let captureRepository = CaptureRepository(container: migratedContainer)
        let destinationRepository = QuickCaptureDestinationRepository(
            container: migratedContainer
        )

        let migratedDraft = try await captureRepository.draft(id: "legacy-draft")
        let migratedDestination = try await destinationRepository.defaultDestination()
        XCTAssertEqual(migratedDraft?.title, "Preserved")
        XCTAssertNil(migratedDestination)
        XCTAssertEqual(NotionPiPSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(NotionPiPMigrationPlan.schemas.count, 2)
    }

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
        XCTAssertEqual(NotionPiPMigrationPlan.schemas.count, 2)
    }

    func testDeliveryStateRawValuesAreStable() {
        XCTAssertEqual(DeliveryState.queued.rawValue, "queued")
        XCTAssertEqual(DeliveryState.inFlight.rawValue, "inFlight")
        XCTAssertEqual(DeliveryState.delivered.rawValue, "delivered")
        XCTAssertEqual(DeliveryState.retrying.rawValue, "retrying")
        XCTAssertEqual(DeliveryState.blockedConflict.rawValue, "blockedConflict")
        XCTAssertEqual(DeliveryState.uncertain.rawValue, "uncertain")
    }

    func testReturnDraftRelationshipSurvivesReopenAndCanBeConsumed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("ReturnDraft.store")
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 2_000))
        do {
            let initial = try CaptureRepository(storeURL: storeURL, clock: clock)
            _ = try await initial.saveDraft(
                DraftMutation(
                    id: "capture-a",
                    title: "A",
                    editorDocument: jsonData(["type": "doc", "content": []]),
                    sourceDocument: nil,
                    disposition: .active
                ),
                expectedRevision: 0
            )
            _ = try await initial.saveDraft(
                DraftMutation(
                    id: "capture-b",
                    title: "B",
                    editorDocument: jsonData(["type": "doc", "content": []]),
                    sourceDocument: nil,
                    disposition: .active
                ),
                expectedRevision: 0
            )
        }

        let reopened = try CaptureRepository(storeURL: storeURL, clock: clock)
        let fetchedSecond = try await reopened.draft(id: "capture-b")
        let second = try XCTUnwrap(fetchedSecond)
        XCTAssertEqual(second.returnDraftID, "capture-a")
        _ = try await reopened.enqueue(
            draftID: second.id,
            expectedRevision: second.revision,
            destination: .manual(pageID: "page-1")
        )
        let returned = try await reopened.draft(id: "capture-a")
        XCTAssertEqual(returned?.disposition, .active)
    }
}
