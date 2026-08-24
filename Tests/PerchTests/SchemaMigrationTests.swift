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
                CaptureDraftModel(
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
