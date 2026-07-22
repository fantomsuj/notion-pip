import Foundation
import SwiftData
import XCTest
@testable import NotionPiP

final class PageRepositoryTests: XCTestCase {
    func testCaptureRepositoryAcceptsSharedContainer() throws {
        let repository = CaptureRepository(container: try makeContainer())

        XCTAssertNotNil(repository)
    }

    func testSharedContainerPreservesInterleavedCaptureAndPageWritesAfterReopen() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("NotionPiP.store")
        let firstPage = try page(slug: "First", id: firstPageID)
        let secondPage = try page(slug: "Second", id: secondPageID)
        let document = Data(#"{"type":"doc","content":[{"type":"paragraph"}]}"#.utf8)

        do {
            let container = try NotionPiPPersistence.makeContainer(storeURL: storeURL)
            let pageRepository = PageRepository(container: container)
            let captureRepository = CaptureRepository(container: container)

            _ = try await pageRepository.replaceCurrent(with: firstPage)
            let draft = try await captureRepository.saveDraft(
                DraftMutation(
                    id: "shared-draft",
                    title: "First draft",
                    editorDocument: document,
                    sourceDocument: nil,
                    disposition: .active
                ),
                expectedRevision: 0
            )
            _ = try await pageRepository.replaceCurrent(with: secondPage)
            _ = try await captureRepository.saveDraft(
                DraftMutation(
                    id: draft.id,
                    title: "Updated draft",
                    editorDocument: document,
                    sourceDocument: nil,
                    disposition: .active
                ),
                expectedRevision: draft.revision
            )
        }

        let reopenedContainer = try NotionPiPPersistence.makeContainer(storeURL: storeURL)
        let reopenedPageRepository = PageRepository(container: reopenedContainer)
        let reopenedCaptureRepository = CaptureRepository(container: reopenedContainer)
        let currentPage = try await reopenedPageRepository.currentPinnedPage()
        let draft = try await reopenedCaptureRepository.draft(id: "shared-draft")

        XCTAssertEqual(currentPage?.pageID, secondPageID)
        XCTAssertEqual(draft?.title, "Updated draft")
        XCTAssertEqual(draft?.revision, 2)
    }

    func testReplacingCurrentPageKeepsOnlyLatestSelection() async throws {
        let repository = try PageRepository(container: makeContainer())
        let first = try page(slug: "First", id: firstPageID)
        let second = try page(slug: "Second", id: secondPageID)

        _ = try await repository.replaceCurrent(with: first)
        _ = try await repository.replaceCurrent(with: second)

        let current = try await repository.currentPinnedPage()
        let pinnedPageIDs = try await repository.pinnedPages().map(\.pageID)
        XCTAssertEqual(current?.pageID, secondPageID)
        XCTAssertEqual(pinnedPageIDs, [secondPageID])
    }

    func testCurrentPageSurvivesReopeningOnDiskStore() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let storeURL = temporaryDirectory.appendingPathComponent("NotionPiP.store")
        let page = try page(slug: "Reopen", id: firstPageID)

        do {
            let container = try NotionPiPPersistence.makeContainer(storeURL: storeURL)
            let repository = PageRepository(container: container)
            _ = try await repository.replaceCurrent(with: page)
        }

        let reopenedContainer = try NotionPiPPersistence.makeContainer(storeURL: storeURL)
        let reopenedRepository = PageRepository(container: reopenedContainer)
        let current = try await reopenedRepository.currentPinnedPage()
        XCTAssertEqual(current?.pageID, page.pageID)
        XCTAssertEqual(current?.canonicalURL, page.canonicalURL)
    }

    func testCorruptStoredCurrentPageThrowsInvalidStoredValue() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(
            PinnedPageModel(
                stableID: firstPageID,
                canonicalURL: "not a Notion URL",
                displayTitle: "Corrupt",
                pinnedAt: Date(timeIntervalSince1970: 4_000)
            )
        )
        try context.save()
        let repository = PageRepository(container: container)

        do {
            _ = try await repository.currentPinnedPage()
            XCTFail("Expected corrupt stored page to throw")
        } catch {
            XCTAssertEqual(
                error as? CaptureRepositoryError,
                .invalidStoredValue("not a Notion URL")
            )
        }
    }

    func testStoredPageIDMismatchThrowsInvalidStoredValue() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let mismatchedPage = try page(slug: "Mismatch", id: secondPageID)
        context.insert(
            PinnedPageModel(
                stableID: firstPageID,
                canonicalURL: mismatchedPage.canonicalURL.absoluteString,
                displayTitle: mismatchedPage.displayTitle,
                pinnedAt: Date(timeIntervalSince1970: 4_000)
            )
        )
        try context.save()
        let repository = PageRepository(container: container)

        do {
            _ = try await repository.currentPinnedPage()
            XCTFail("Expected mismatched stored page ID to throw")
        } catch {
            XCTAssertEqual(
                error as? CaptureRepositoryError,
                .invalidStoredValue(mismatchedPage.canonicalURL.absoluteString)
            )
        }
    }

    func testFailedReplacementRollsBackToPreviousCurrentPage() async throws {
        let failure = FailNextPageSave()
        let repository = try PageRepository(
            container: makeContainer(),
            clock: TestCaptureClock(Date(timeIntervalSince1970: 4_000)),
            beforeSave: failure.check
        )
        let original = try page(slug: "Original", id: firstPageID)
        let failedReplacement = try page(slug: "Failed-Replacement", id: secondPageID)
        _ = try await repository.replaceCurrent(with: original)

        failure.failNext()
        do {
            _ = try await repository.replaceCurrent(with: failedReplacement)
            XCTFail("Expected injected replacement save failure")
        } catch is FailNextPageSave.ExpectedFailure {}

        let current = try await repository.currentPinnedPage()
        let pinnedPageIDs = try await repository.pinnedPages().map(\.pageID)
        XCTAssertEqual(current?.pageID, original.pageID)
        XCTAssertEqual(current?.canonicalURL, original.canonicalURL)
        XCTAssertEqual(pinnedPageIDs, [original.pageID])
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
        try NotionPiPPersistence.makeContainer(inMemory: true)
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
