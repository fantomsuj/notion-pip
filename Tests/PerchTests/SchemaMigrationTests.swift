import Foundation
import SwiftData
import XCTest
@testable import Perch

final class SchemaMigrationTests: XCTestCase {
    func testV1StoreTraversesAllMigrationsWithoutLosingPageState() async throws {
        let (directory, storeURL) = try makeStore(named: "V1-to-V4.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: PerchSchemaV1.self)
        let pageID = "0123456789abcdef0123456789abcdef"
        let recentID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: configuration(schema: schema, storeURL: storeURL)
            )
            let context = ModelContext(container)
            context.insert(
                PinnedPageSchemaV3.PinnedPageModel(
                    stableID: pageID,
                    canonicalURL: "https://www.notion.so/Original-\(pageID)",
                    displayTitle: "Original",
                    pinnedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
            context.insert(
                RecentPageSchemaV1.RecentPageModel(
                    stableID: recentID,
                    canonicalURL: "https://www.notion.so/Recent-\(recentID)",
                    displayTitle: "Recent",
                    visitedAt: Date(timeIntervalSince1970: 1_500)
                )
            )
            context.insert(
                CaptureDraftSchemaV1.CaptureDraftModel(
                    stableID: "original-draft",
                    revision: 1,
                    title: "Retired",
                    editorDocument: Data("{}".utf8),
                    sourceDocument: nil,
                    dispositionRawValue: "active",
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
            try context.save()
        }

        let migratedContainer = try PerchPersistence.makeContainer(storeURL: storeURL)
        let workingSet = try await PageRepository(container: migratedContainer).workingSet()

        XCTAssertEqual(workingSet.activePage?.pageID, pageID)
        XCTAssertEqual(workingSet.pinnedPages.map(\.pageID), [pageID])
        XCTAssertEqual(workingSet.recentPages.map(\.pageID), [recentID])
        XCTAssertEqual(PerchSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
    }

    func testV2PinnedPageBecomesV3ActivePageAndFirstFavorite() async throws {
        let (directory, storeURL) = try makeStore(named: "V2-to-V4.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: PerchSchemaV2.self)
        let pageID = "0123456789abcdef0123456789abcdef"
        let pageURL = try XCTUnwrap(URL(string: "https://www.notion.so/Legacy-\(pageID)"))

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: configuration(schema: schema, storeURL: storeURL)
            )
            let context = ModelContext(container)
            context.insert(
                PinnedPageSchemaV3.PinnedPageModel(
                    stableID: pageID,
                    canonicalURL: pageURL.absoluteString,
                    displayTitle: "Legacy",
                    pinnedAt: Date(timeIntervalSince1970: 2_000)
                )
            )
            try context.save()
        }

        let migratedContainer = try PerchPersistence.makeContainer(storeURL: storeURL)
        let workingSet = try await PageRepository(container: migratedContainer).workingSet()

        XCTAssertEqual(workingSet.activePage?.pageID, pageID)
        XCTAssertEqual(workingSet.pinnedPages.map(\.pageID), [pageID])
        XCTAssertEqual(PerchSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(PerchMigrationPlan.schemas.count, 5)
    }

    func testV3PinsMigrateToV4WithNilRolesAndPreservedWorkingSetOrder() async throws {
        let (directory, storeURL) = try makeStore(named: "V3-to-V4.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: PerchSchemaV3.self)
        let olderID = "0123456789abcdef0123456789abcdef"
        let newerID = "fedcba9876543210fedcba9876543210"
        let recentID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: configuration(schema: schema, storeURL: storeURL)
            )
            let context = ModelContext(container)
            context.insert(
                PinnedPageSchemaV3.PinnedPageModel(
                    stableID: olderID,
                    canonicalURL: "https://www.notion.so/Older-\(olderID)",
                    displayTitle: "Older",
                    pinnedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
            context.insert(
                PinnedPageSchemaV3.PinnedPageModel(
                    stableID: newerID,
                    canonicalURL: "https://www.notion.so/Newer-\(newerID)",
                    displayTitle: "Newer",
                    pinnedAt: Date(timeIntervalSince1970: 2_000)
                )
            )
            context.insert(
                RecentPageModel(
                    stableID: recentID,
                    canonicalURL: "https://www.notion.so/Recent-\(recentID)",
                    displayTitle: "Recent",
                    visitedAt: Date(timeIntervalSince1970: 3_000)
                )
            )
            try context.save()
        }

        let migratedContainer = try PerchPersistence.makeContainer(storeURL: storeURL)
        let workingSet = try await PageRepository(container: migratedContainer).workingSet()

        XCTAssertEqual(workingSet.pinnedPages.map(\.pageID), [newerID, olderID])
        XCTAssertEqual(workingSet.pinnedPages.map(\.role), [nil, nil])
        XCTAssertEqual(workingSet.recentPages.map(\.pageID), [recentID])
        XCTAssertEqual(PerchSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
        XCTAssertEqual(PerchMigrationPlan.schemas.count, 5)
    }

    func testV4StoreDropsLegacyCaptureEntitiesWhenMigratingToV5() async throws {
        let (directory, storeURL) = try makeStore(named: "V4-to-V5.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: PerchSchemaV4.self)
        let pageID = "0123456789abcdef0123456789abcdef"

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: configuration(schema: schema, storeURL: storeURL)
            )
            let context = ModelContext(container)
            context.insert(
                PinnedPageModel(
                    stableID: pageID,
                    canonicalURL: "https://www.notion.so/Preserved-\(pageID)",
                    displayTitle: "Preserved",
                    pinnedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
            context.insert(
                CaptureDraftModel(
                    stableID: "retired-draft",
                    revision: 1,
                    title: "Retired",
                    editorDocument: Data("{}".utf8),
                    sourceDocument: nil,
                    dispositionRawValue: "active",
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
            try context.save()
        }

        let migratedContainer = try PerchPersistence.makeContainer(storeURL: storeURL)
        let workingSet = try await PageRepository(container: migratedContainer).workingSet()

        XCTAssertEqual(workingSet.pinnedPages.map(\.pageID), [pageID])
        XCTAssertEqual(PerchSchemaV5.models.count, 4)
        XCTAssertFalse(PerchSchemaV5.models.contains { $0 == CaptureDraftModel.self })
        XCTAssertFalse(PerchSchemaV5.models.contains { $0 == CaptureRecordModel.self })
        XCTAssertFalse(PerchSchemaV5.models.contains { $0 == QuickCaptureSettingsModel.self })
    }

    func testV3StoreKeepsActivePageRecentsAndRestorationsThroughV5() async throws {
        let (directory, storeURL) = try makeStore(named: "V3-to-V5.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: PerchSchemaV3.self)
        let pinnedID = "0123456789abcdef0123456789abcdef"
        let recentID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: configuration(schema: schema, storeURL: storeURL)
            )
            let context = ModelContext(container)
            context.insert(
                PinnedPageSchemaV3.PinnedPageModel(
                    stableID: pinnedID,
                    canonicalURL: "https://www.notion.so/Pinned-\(pinnedID)",
                    displayTitle: "Pinned",
                    pinnedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
            context.insert(
                RecentPageSchemaV1.RecentPageModel(
                    stableID: recentID,
                    canonicalURL: "https://www.notion.so/Recent-\(recentID)",
                    displayTitle: "Recent",
                    visitedAt: Date(timeIntervalSince1970: 2_000)
                )
            )
            context.insert(
                ActivePageSchemaV3.ActivePageModel(
                    pageID: recentID,
                    canonicalURL: "https://www.notion.so/Recent-\(recentID)",
                    displayTitle: "Recent",
                    updatedAt: Date(timeIntervalSince1970: 2_000)
                )
            )
            for (pageID, slug) in [(pinnedID, "Pinned"), (recentID, "Recent")] {
                context.insert(
                    PageRestorationSchemaV3.PageRestorationModel(
                        stableID: pageID,
                        lastURL: "https://www.notion.so/\(slug)-\(pageID)",
                        scrollX: 0,
                        scrollY: 120,
                        scrollProgress: 0.4,
                        updatedAt: Date(timeIntervalSince1970: 3_000)
                    )
                )
            }
            context.insert(
                QuickCaptureSettingsSchemaV2.QuickCaptureSettingsModel(
                    destinationKind: "page",
                    destinationID: pinnedID,
                    displayTitle: "Retired",
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
            try context.save()
        }

        let migratedContainer = try PerchPersistence.makeContainer(storeURL: storeURL)
        let workingSet = try await PageRepository(container: migratedContainer).workingSet()

        XCTAssertEqual(workingSet.activePage?.pageID, recentID)
        XCTAssertEqual(workingSet.pinnedPages.map(\.pageID), [pinnedID])
        XCTAssertEqual(workingSet.recentPages.map(\.pageID), [recentID])
        XCTAssertEqual(Set(workingSet.restorations.map(\.pageID)), [pinnedID, recentID])
        XCTAssertEqual(workingSet.restorations.map(\.scrollY), [120, 120])
    }

    func testV4StoreKeepsRolesActivePageAndRestorationsThroughV5() async throws {
        let (directory, storeURL) = try makeStore(named: "V4-roles-to-V5.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: PerchSchemaV4.self)
        let pinnedID = "0123456789abcdef0123456789abcdef"
        let pageURL = "https://www.notion.so/Pinned-\(pinnedID)"

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: configuration(schema: schema, storeURL: storeURL)
            )
            let context = ModelContext(container)
            context.insert(
                PinnedPageSchemaV4.PinnedPageModel(
                    stableID: pinnedID,
                    canonicalURL: pageURL,
                    displayTitle: "Pinned",
                    role: "inbox",
                    pinnedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
            context.insert(
                ActivePageSchemaV3.ActivePageModel(
                    pageID: pinnedID,
                    canonicalURL: pageURL,
                    displayTitle: "Pinned",
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
            context.insert(
                PageRestorationSchemaV3.PageRestorationModel(
                    stableID: pinnedID,
                    lastURL: pageURL,
                    scrollX: 0,
                    scrollY: 300,
                    scrollProgress: 0.75,
                    updatedAt: Date(timeIntervalSince1970: 2_000)
                )
            )
            try context.save()
        }

        let migratedContainer = try PerchPersistence.makeContainer(storeURL: storeURL)
        let workingSet = try await PageRepository(container: migratedContainer).workingSet()

        XCTAssertEqual(workingSet.activePage?.pageID, pinnedID)
        XCTAssertEqual(workingSet.pinnedPages.map(\.role), ["inbox"])
        XCTAssertEqual(workingSet.restorations.map(\.scrollY), [300])
    }

    /// Each schema version must keep describing exactly what shipped. If this
    /// fails, a frozen model was edited: restore it and add a new namespaced
    /// copy, schema version, and migration stage instead.
    func testEverySchemaVersionKeepsItsShippedEntitiesAndAttributes() {
        let captureDraft: Set<String> = [
            "stableID", "revision", "title", "editorDocument", "sourceDocument",
            "dispositionRawValue", "createdAt", "updatedAt", "captureRecordID",
            "returnDraftID",
        ]
        let captureRecord: Set<String> = [
            "stableID", "draftID", "enqueuedDraftRevision", "revision", "title",
            "editorDocument", "sourceDocument", "destinationKind", "destinationID",
            "stateRawValue", "attemptCount", "firstQueuedAt", "nextAttemptAt",
            "inFlightAt", "deliveredAt", "updatedAt", "fingerprint",
            "operationJournal", "remoteIdentity", "safeErrorCode", "safeErrorMessage",
            "safeErrorStatusCode", "safeErrorRetryAfter", "requiresManagedCheck",
        ]
        let pinnedV3: Set<String> = ["stableID", "canonicalURL", "displayTitle", "pinnedAt"]
        let pinnedV4 = pinnedV3.union(["role"])
        let recent: Set<String> = ["stableID", "canonicalURL", "displayTitle", "visitedAt"]
        let quickCaptureSettings: Set<String> = [
            "stableID", "destinationKind", "destinationID", "displayTitle", "updatedAt",
        ]
        let active: Set<String> = [
            "stableID", "pageID", "canonicalURL", "displayTitle", "updatedAt",
        ]
        let restoration: Set<String> = [
            "stableID", "lastURL", "scrollX", "scrollY", "scrollProgress", "updatedAt",
        ]

        let v1: [String: Set<String>] = [
            "CaptureDraftModel": captureDraft,
            "CaptureRecordModel": captureRecord,
            "PinnedPageModel": pinnedV3,
            "RecentPageModel": recent,
        ]
        var v2 = v1
        v2["QuickCaptureSettingsModel"] = quickCaptureSettings
        var v3 = v2
        v3["ActivePageModel"] = active
        v3["PageRestorationModel"] = restoration
        var v4 = v3
        v4["PinnedPageModel"] = pinnedV4
        let v5: [String: Set<String>] = [
            "PinnedPageModel": pinnedV4,
            "RecentPageModel": recent,
            "ActivePageModel": active,
            "PageRestorationModel": restoration,
        ]

        let expected: [(any VersionedSchema.Type, [String: Set<String>])] = [
            (PerchSchemaV1.self, v1),
            (PerchSchemaV2.self, v2),
            (PerchSchemaV3.self, v3),
            (PerchSchemaV4.self, v4),
            (PerchSchemaV5.self, v5),
        ]
        XCTAssertEqual(expected.count, PerchMigrationPlan.schemas.count)
        for (versionedSchema, expectedEntities) in expected {
            let schema = Schema(versionedSchema: versionedSchema)
            let actual = Dictionary(
                uniqueKeysWithValues: schema.entities.map { entity in
                    (entity.name, Set(entity.attributes.map(\.name)))
                }
            )
            XCTAssertEqual(
                actual,
                expectedEntities,
                "Schema \(versionedSchema.versionIdentifier) changed"
            )
        }
    }

    private func makeStore(named name: String) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return (directory, directory.appendingPathComponent(name))
    }

    private func configuration(schema: Schema, storeURL: URL) -> ModelConfiguration {
        ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    }
}
