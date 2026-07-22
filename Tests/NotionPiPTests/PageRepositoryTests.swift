import Foundation
import SwiftData
import XCTest
@testable import NotionPiP

final class PageRepositoryTests: XCTestCase {
    func testFailedPinMutationIsRolledBackBeforeLaterRecentSave() async throws {
        let failure = FailNextPageSave()
        let repository = try PageRepository(
            container: makeContainer(),
            clock: TestCaptureClock(Date(timeIntervalSince1970: 4_000)),
            beforeSave: failure.check
        )
        let original = try page(slug: "Original", id: firstPageID)
        let failedChange = try page(slug: "Failed-Change", id: firstPageID)
        _ = try await repository.pin(original)

        failure.failNext()
        do {
            _ = try await repository.pin(failedChange)
            XCTFail("Expected injected pin save failure")
        } catch is FailNextPageSave.ExpectedFailure {}

        _ = try await repository.recordRecent(try page(slug: "Recent", id: secondPageID))
        let pinned = try await repository.pinnedPages()
        XCTAssertEqual(pinned.count, 1)
        XCTAssertEqual(pinned.first?.displayTitle, "Original")
    }

    func testFailedRecentInsertIsRolledBackBeforeLaterPinSave() async throws {
        let failure = FailNextPageSave()
        let repository = try PageRepository(
            container: makeContainer(),
            clock: TestCaptureClock(Date(timeIntervalSince1970: 4_000)),
            beforeSave: failure.check
        )

        failure.failNext()
        do {
            _ = try await repository.recordRecent(try page(slug: "Failed-Recent", id: firstPageID))
            XCTFail("Expected injected recent save failure")
        } catch is FailNextPageSave.ExpectedFailure {}

        _ = try await repository.pin(try page(slug: "Pinned", id: secondPageID))
        let recents = try await repository.recentPages()
        XCTAssertTrue(recents.isEmpty)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: NotionPiPSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: NotionPiPMigrationPlan.self,
            configurations: configuration
        )
    }

    private func page(slug: String, id: String) throws -> NotionPageReference {
        try NotionPageReference(validating: XCTUnwrap(URL(string: "https://www.notion.so/\(slug)-\(id)")))
    }

    private var firstPageID: String { "0123456789abcdef0123456789abcdef" }
    private var secondPageID: String { "fedcba9876543210fedcba9876543210" }
}

private final class FailNextPageSave: @unchecked Sendable {
    struct ExpectedFailure: Error {}

    private let lock = NSLock()
    private var shouldFail = false

    func failNext() {
        lock.withLock { shouldFail = true }
    }

    func check() throws {
        try lock.withLock {
            if shouldFail {
                shouldFail = false
                throw ExpectedFailure()
            }
        }
    }
}
