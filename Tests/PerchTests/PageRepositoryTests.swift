import Foundation
import SwiftData
import XCTest
@testable import Perch

final class PageRepositoryTests: XCTestCase {
    func testDisplayTitleUsesCanonicalIDAndPrefersActiveThenPinnedThenRecent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let active = try page(slug: "Active", id: firstPageID)
        let pinned = try page(slug: "Pinned", id: secondPageID)
        let recent = try page(slug: "Recent", id: "11111111111111111111111111111111")
        let blank = try page(slug: "Blank", id: "22222222222222222222222222222222")

        context.insert(
            ActivePageModel(
                pageID: active.pageID.uppercased(),
                canonicalURL: active.canonicalURL.absoluteString,
                displayTitle: "Active title",
                updatedAt: Date(timeIntervalSince1970: 4)
            )
        )
        context.insert(
            PinnedPageModel(
                stableID: active.pageID,
                canonicalURL: active.canonicalURL.absoluteString,
                displayTitle: "Pinned title",
                pinnedAt: Date(timeIntervalSince1970: 3)
            )
        )
        context.insert(
            RecentPageModel(
                stableID: active.pageID,
                canonicalURL: active.canonicalURL.absoluteString,
                displayTitle: "Recent title",
                visitedAt: Date(timeIntervalSince1970: 2)
            )
        )
        context.insert(
            PinnedPageModel(
                stableID: pinned.pageID,
                canonicalURL: pinned.canonicalURL.absoluteString,
                displayTitle: "Pinned fallback",
                pinnedAt: Date(timeIntervalSince1970: 3)
            )
        )
        context.insert(
            RecentPageModel(
                stableID: pinned.pageID,
                canonicalURL: pinned.canonicalURL.absoluteString,
                displayTitle: "Recent fallback",
                visitedAt: Date(timeIntervalSince1970: 2)
            )
        )
        context.insert(
            RecentPageModel(
                stableID: recent.pageID.uppercased(),
                canonicalURL: recent.canonicalURL.absoluteString,
                displayTitle: "Recent only",
                visitedAt: Date(timeIntervalSince1970: 1)
            )
        )
        context.insert(
            RecentPageModel(
                stableID: blank.pageID,
                canonicalURL: blank.canonicalURL.absoluteString,
                displayTitle: " \n ",
                visitedAt: Date(timeIntervalSince1970: 1)
            )
        )
        try context.save()

        let repository = PageRepository(container: container)
        let activeTitle = await repository.displayTitle(for: active.pageID.uppercased())
        let pinnedTitle = await repository.displayTitle(for: pinned.pageID)
        let recentTitle = await repository.displayTitle(for: recent.pageID)
        let blankTitle = await repository.displayTitle(for: blank.pageID)
        let unknownTitle = await repository.displayTitle(for: "unknown")

        XCTAssertEqual(activeTitle, "Active title")
        XCTAssertEqual(pinnedTitle, "Pinned fallback")
        XCTAssertEqual(recentTitle, "Recent only")
        XCTAssertNil(blankTitle)
        XCTAssertNil(unknownTitle)
    }

    func testDisplayTitleSkipsBlankSnapshotsBeforeContinuingPrecedence() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let page = try self.page(slug: "Project", id: firstPageID)
        context.insert(
            ActivePageModel(
                pageID: page.pageID,
                canonicalURL: page.canonicalURL.absoluteString,
                displayTitle: " \n ",
                updatedAt: Date(timeIntervalSince1970: 3)
            )
        )
        context.insert(
            PinnedPageModel(
                stableID: page.pageID,
                canonicalURL: page.canonicalURL.absoluteString,
                displayTitle: "Pinned title",
                pinnedAt: Date(timeIntervalSince1970: 2)
            )
        )
        context.insert(
            RecentPageModel(
                stableID: page.pageID,
                canonicalURL: page.canonicalURL.absoluteString,
                displayTitle: "Recent title",
                visitedAt: Date(timeIntervalSince1970: 1)
            )
        )
        try context.save()

        let title = await PageRepository(container: container).displayTitle(for: page.pageID)

        XCTAssertEqual(title, "Pinned title")
    }

    func testRecentPiPPagesIncludesRecentlyVisitedPinnedPageInVisitOrder() async throws {
        let clock = TestDateProvider(Date(timeIntervalSince1970: 100))
        let repository = PageRepository(container: try makeContainer(), clock: clock)
        let pinned = try page(slug: "Pinned-project", id: firstPageID)
        let recent = try page(slug: "Recent-notes", id: secondPageID)

        _ = try await repository.setPinned(true, page: pinned)
        _ = try await repository.recordVisit(recent)
        clock.advance(by: 100)
        _ = try await repository.recordVisit(pinned)

        let result = try await repository.recentPiPPages(limit: 5)

        XCTAssertEqual(result.pages.map(\.pageID), [pinned.pageID, recent.pageID])
        XCTAssertEqual(result.activePageID, pinned.pageID)
    }

    func testRecentPiPPagesHonorsLimitAndRetainsMatchingRestorations() async throws {
        let clock = TestDateProvider(Date(timeIntervalSince1970: 1_000))
        let repository = PageRepository(container: try makeContainer(), clock: clock)
        let older = try page(slug: "Older", id: firstPageID)
        let newer = try page(slug: "Newer", id: secondPageID)
        _ = try await repository.recordVisit(older)
        let restoration = try DurablePageRestoration(
            pageID: older.pageID,
            validatingLastURL: older.canonicalURL,
            scrollX: 4,
            scrollY: 80,
            scrollProgress: 0.25,
            updatedAt: clock.now()
        )
        _ = try await repository.saveRestoration(restoration)
        clock.advance(by: 100)
        _ = try await repository.recordVisit(newer)

        let limited = try await repository.recentPiPPages(limit: 1)
        let complete = try await repository.recentPiPPages(limit: 5)

        XCTAssertEqual(limited.pages.map(\.pageID), [newer.pageID])
        XCTAssertEqual(complete.pages.map(\.pageID), [newer.pageID, older.pageID])
        XCTAssertEqual(complete.restoration(for: older.pageID), restoration)
        XCTAssertNil(complete.restoration(for: newer.pageID))
        let workingSet = try await repository.workingSet()
        XCTAssertEqual(workingSet.restorations, [restoration])
    }

    func testRecentPiPPagesDeduplicatesCaseInsensitivelyAndKeepsActiveFallback() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let active = try page(slug: "Active", id: firstPageID)
        context.insert(
            ActivePageModel(
                pageID: active.pageID.uppercased(),
                canonicalURL: active.canonicalURL.absoluteString,
                displayTitle: active.displayTitle,
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        context.insert(
            RecentPageModel(
                stableID: active.pageID,
                canonicalURL: active.canonicalURL.absoluteString,
                displayTitle: active.displayTitle,
                visitedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        try context.save()

        let repository = PageRepository(container: container)
        let result = try await repository.recentPiPPages(limit: -1)
        let fallback = try await repository.recentPiPPages(limit: 5)

        XCTAssertTrue(result.pages.isEmpty)
        XCTAssertEqual(fallback.pages.map(\.pageID), [active.pageID])
        XCTAssertEqual(fallback.activePageID, active.pageID)
    }

    func testRecordVisitUpdatesActivePageAndKeepsOnlySevenUnpinnedRecents() async throws {
        let repository = try PageRepository(container: makeContainer())
        let pages = try (0..<8).map(page(number:))

        for page in pages {
            _ = try await repository.recordVisit(page)
        }

        let workingSet = try await repository.workingSet()
        XCTAssertEqual(workingSet.activePage?.pageID, pages[7].pageID)
        XCTAssertEqual(
            workingSet.recentPages.map(\.pageID),
            pages[1...7].reversed().map(\.pageID)
        )
    }

    func testPinnedPageIsExcludedFromRecentsAndReturnsWhenUnpinned() async throws {
        let clock = AdvancingPageClock(start: Date(timeIntervalSince1970: 1_000))
        let repository = try PageRepository(container: makeContainer(), clock: clock)
        let pinned = try page(number: 0)
        let recent = try page(number: 1)

        _ = try await repository.recordVisit(pinned)
        _ = try await repository.setPinned(true, page: pinned)
        _ = try await repository.recordVisit(recent)

        var workingSet = try await repository.workingSet()
        XCTAssertEqual(workingSet.pinnedPages.map(\.pageID), [pinned.pageID])
        XCTAssertEqual(workingSet.recentPages.map(\.pageID), [recent.pageID])

        _ = try await repository.setPinned(false, page: pinned)
        workingSet = try await repository.workingSet()
        XCTAssertTrue(workingSet.pinnedPages.isEmpty)
        XCTAssertEqual(
            workingSet.recentPages.map(\.pageID),
            [recent.pageID, pinned.pageID]
        )
    }

    func testEighthPinIsRejectedWithoutMutatingExistingPins() async throws {
        let repository = try PageRepository(container: makeContainer())
        let pages = try (0..<8).map(page(number:))
        for page in pages.prefix(7) {
            _ = try await repository.setPinned(true, page: page)
        }

        do {
            _ = try await repository.setPinned(true, page: pages[7])
            XCTFail("Expected the eighth pin to be rejected")
        } catch {
            XCTAssertEqual(error as? PageRepositoryError, .pinLimitReached(maximum: 7))
        }

        let workingSet = try await repository.workingSet()
        XCTAssertEqual(Set(workingSet.pinnedPages.map(\.pageID)), Set(pages.prefix(7).map(\.pageID)))
        XCTAssertFalse(workingSet.pinnedPages.contains { $0.pageID == pages[7].pageID })
    }

    func testFailedPinSaveRollsBackPinAndRecentMetadata() async throws {
        let failure = FailNextPageSave()
        let repository = try PageRepository(
            container: makeContainer(),
            clock: TestDateProvider(Date(timeIntervalSince1970: 4_000)),
            beforeSave: failure.check
        )
        let page = try page(number: 0)

        failure.failNext()
        do {
            _ = try await repository.setPinned(true, page: page)
            XCTFail("Expected injected pin save failure")
        } catch is FailNextPageSave.ExpectedFailure {}

        let workingSet = try await repository.workingSet()
        XCTAssertTrue(workingSet.pinnedPages.isEmpty)
        XCTAssertTrue(workingSet.recentPages.isEmpty)
    }

    func testRolePersistsLocallyWithoutChangingTitlePinOrderOrRecents() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("PinnedRoles.store")
        let first = try page(slug: "Daily-Planner", id: firstPageID)
        let second = try page(slug: "Project-Brief", id: secondPageID)
        let recent = try page(number: 3)

        do {
            let repository = PageRepository(
                container: try PerchPersistence.makeContainer(storeURL: storeURL),
                clock: AdvancingPageClock(start: Date(timeIntervalSince1970: 1_000))
            )
            _ = try await repository.setPinned(true, page: first)
            _ = try await repository.setPinned(true, page: second)
            _ = try await repository.recordVisit(recent)
            _ = try await repository.setRole("  Today\nPlanner  ", pageID: first.pageID)
        }

        let reopened = PageRepository(
            container: try PerchPersistence.makeContainer(storeURL: storeURL)
        )
        let workingSet = try await reopened.workingSet()

        XCTAssertEqual(workingSet.pinnedPages.map(\.pageID), [second.pageID, first.pageID])
        XCTAssertEqual(workingSet.pinnedPages.map(\.role), [nil, "Today Planner"])
        XCTAssertEqual(workingSet.pinnedPages.last?.displayTitle, "Daily Planner")
        XCTAssertEqual(workingSet.recentPages.map(\.pageID), [recent.pageID])
    }

    func testDuplicateRoleIsRejectedWithoutMutatingPersistedRoles() async throws {
        let repository = PageRepository(container: try makeContainer())
        let first = try page(slug: "First", id: firstPageID)
        let second = try page(slug: "Second", id: secondPageID)
        _ = try await repository.setPinned(true, page: first)
        _ = try await repository.setPinned(true, page: second)
        _ = try await repository.setRole("Café", pageID: first.pageID)

        do {
            _ = try await repository.setRole("cafe", pageID: second.pageID)
            XCTFail("Expected duplicate role rejection")
        } catch {
            XCTAssertEqual(error as? PageRepositoryError, .duplicateRole)
        }

        let workingSet = try await repository.workingSet()
        XCTAssertEqual(workingSet.pinnedPages.compactMap(\.role), ["Café"])
    }

    func testClearingRolePreservesPinTimestampAndTitle() async throws {
        let repository = PageRepository(container: try makeContainer())
        let page = try page(slug: "Daily-Planner", id: firstPageID)
        let pinned = try await repository.setPinned(true, page: page)
        _ = try await repository.setRole("Today", pageID: page.pageID)

        let cleared = try await repository.setRole(nil, pageID: page.pageID)

        XCTAssertNil(cleared.role)
        XCTAssertEqual(cleared.displayTitle, "Daily Planner")
        XCTAssertEqual(cleared.timestamp, pinned.timestamp)
    }

    func testRoleCannotBeStoredForAnUnpinnedPage() async throws {
        let repository = PageRepository(container: try makeContainer())
        let page = try page(slug: "Recent", id: firstPageID)
        _ = try await repository.recordVisit(page)

        do {
            _ = try await repository.setRole("Today", pageID: page.pageID)
            XCTFail("Expected roles to be limited to pinned pages")
        } catch {
            XCTAssertEqual(error as? PageRepositoryError, .roleRequiresPinnedPage)
        }

        let workingSet = try await repository.workingSet()
        XCTAssertTrue(workingSet.pinnedPages.isEmpty)
        XCTAssertEqual(workingSet.recentPages.map(\.pageID), [page.pageID])
    }

    func testRestorationOutsideWorkingSetIsPruned() async throws {
        let repository = try PageRepository(container: makeContainer())
        let retained = try page(number: 0)
        let pruned = try page(number: 1)
        _ = try await repository.recordVisit(retained)
        _ = try await repository.saveRestoration(
            try DurablePageRestoration(
                pageID: retained.pageID,
                validatingLastURL: retained.canonicalURL,
                scrollX: 4,
                scrollY: 80,
                scrollProgress: 0.25,
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        _ = try await repository.saveRestoration(
            try DurablePageRestoration(
                pageID: pruned.pageID,
                validatingLastURL: pruned.canonicalURL,
                scrollX: 0,
                scrollY: 10,
                scrollProgress: 0.1,
                updatedAt: Date(timeIntervalSince1970: 2_001)
            )
        )

        let workingSet = try await repository.workingSet()
        XCTAssertEqual(workingSet.restorations.map(\.pageID), [retained.pageID])
        XCTAssertEqual(workingSet.restorations.first?.scrollY, 80)
    }

    func testWorkingSetSkipsCorruptRowsWithoutDiscardingValidRows() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let valid = try page(number: 0)
        context.insert(
            PinnedPageModel(
                stableID: valid.pageID,
                canonicalURL: valid.canonicalURL.absoluteString,
                displayTitle: valid.displayTitle,
                pinnedAt: Date(timeIntervalSince1970: 4_000)
            )
        )
        context.insert(
            RecentPageModel(
                stableID: secondPageID,
                canonicalURL: "https://example.com/not-notion",
                displayTitle: "Corrupt",
                visitedAt: Date(timeIntervalSince1970: 5_000)
            )
        )
        try context.save()

        let workingSet = try await PageRepository(container: container).workingSet()
        XCTAssertEqual(workingSet.pinnedPages.map(\.pageID), [valid.pageID])
        XCTAssertTrue(workingSet.recentPages.isEmpty)
    }

    func testBootstrapActivePageUsesNewestLegacyPin() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let older = try page(number: 1)
        let newer = try page(number: 0)
        context.insert(
            PinnedPageModel(
                stableID: newer.pageID,
                canonicalURL: newer.canonicalURL.absoluteString,
                displayTitle: "Newer",
                pinnedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        context.insert(
            PinnedPageModel(
                stableID: older.pageID,
                canonicalURL: older.canonicalURL.absoluteString,
                displayTitle: "Older",
                pinnedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        try context.save()

        let repository = PageRepository(container: container)
        let workingSet = try await repository.workingSet()
        let pins = try await repository.pinnedPages()

        XCTAssertEqual(workingSet.activePage?.pageID, newer.pageID)
        XCTAssertEqual(pins.map(\.pageID), [newer.pageID, older.pageID])
    }

    func testWorkingSetReadDoesNotDeleteOverflowLegacyPinsOrRestorations() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pages = try (0..<8).map(page(number:))
        for (index, page) in pages.enumerated() {
            let timestamp = Date(timeIntervalSince1970: TimeInterval(index + 1))
            context.insert(
                PinnedPageModel(
                    stableID: page.pageID,
                    canonicalURL: page.canonicalURL.absoluteString,
                    displayTitle: page.displayTitle,
                    pinnedAt: timestamp
                )
            )
            context.insert(
                PageRestorationModel(
                    stableID: page.pageID,
                    lastURL: page.canonicalURL.absoluteString,
                    scrollX: 0,
                    scrollY: Double(index),
                    scrollProgress: 0.5,
                    updatedAt: timestamp
                )
            )
        }
        try context.save()

        let workingSet = try await PageRepository(container: container).workingSet()
        let persistedRestorations = try ModelContext(container).fetch(
            FetchDescriptor<PageRestorationModel>()
        )

        XCTAssertEqual(workingSet.pinnedPages.count, 8)
        XCTAssertEqual(workingSet.restorations.count, 8)
        XCTAssertEqual(persistedRestorations.count, 8)
    }

    func testFailedRecentInsertIsRolledBackBeforeLaterPinSave() async throws {
        let failure = FailNextPageSave()
        let repository = try PageRepository(
            container: makeContainer(),
            clock: TestDateProvider(Date(timeIntervalSince1970: 4_000)),
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
        try PerchPersistence.makeContainer(inMemory: true)
    }

    private func page(slug: String, id: String) throws -> NotionPageReference {
        try NotionPageReference(validating: XCTUnwrap(URL(string: "https://www.notion.so/\(slug)-\(id)")))
    }

    private func page(number: Int) throws -> NotionPageReference {
        let id = String(format: "%032x", number + 1)
        return try page(slug: "Page-\(number)", id: id)
    }

    private var firstPageID: String { "0123456789abcdef0123456789abcdef" }
    private var secondPageID: String { "fedcba9876543210fedcba9876543210" }
}

private final class AdvancingPageClock: DateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) {
        current = start
    }

    func now() -> Date {
        lock.withLock {
            defer { current = current.addingTimeInterval(1) }
            return current
        }
    }
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
