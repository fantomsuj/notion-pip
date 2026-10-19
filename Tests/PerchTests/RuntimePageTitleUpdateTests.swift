import Foundation
import XCTest
@testable import Perch

@MainActor
final class RuntimePageTitleUpdateTests: XCTestCase {
    func testTypingTitleUpdatesInMemoryAndSavesOnceWithoutReopeningPage() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let scheduler = RuntimeShortcutGestureScheduler()
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            pageMetadataSaveScheduler: scheduler
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)
        try await repository.waitUntilSaveCount(1)

        for title in ["R", "Ro", "Roadmap 2"] {
            runtime.updateActivePageMetadata(page.resolvingDisplayTitle(title))
        }

        XCTAssertEqual(runtime.activePage?.displayTitle, "Roadmap 2")
        XCTAssertEqual(panel.currentPage?.displayTitle, "Roadmap 2")
        XCTAssertEqual(panel.shownPages, [page])
        XCTAssertTrue(panel.replacedPages.isEmpty)
        XCTAssertEqual(scheduler.pendingCount, 1)
        let metadataBeforeDebounce = await repository.savedMetadata()
        XCTAssertTrue(metadataBeforeDebounce.isEmpty)

        scheduler.fireNext()
        try await repository.waitUntilMetadataSaveCount(1)

        let savedMetadata = await repository.savedMetadata()
        let savedVisits = await repository.savedPages()
        XCTAssertEqual(savedMetadata.map(\.displayTitle), ["Roadmap 2"])
        XCTAssertEqual(savedVisits, [page])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testTitleChangeWhileStashedKeepsPanelStashed() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let scheduler = RuntimeShortcutGestureScheduler()
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            pageMetadataSaveScheduler: scheduler
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)
        try await repository.waitUntilSaveCount(1)
        panel.simulateStashedState()

        runtime.updateActivePageMetadata(page.resolvingDisplayTitle("Renamed"))
        scheduler.fireNext()
        try await repository.waitUntilMetadataSaveCount(1)

        XCTAssertTrue(panel.isStashed)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(runtime.pipPresentationState, .stashed)
        XCTAssertEqual(panel.shownPages, [page])
        XCTAssertEqual(runtime.activePage?.displayTitle, "Renamed")
        let savedVisits = await repository.savedPages()
        XCTAssertEqual(savedVisits, [page])
    }

    func testSlugChangeForSamePageUpdatesURLWithoutReplacingPage() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let scheduler = RuntimeShortcutGestureScheduler()
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            pageMetadataSaveScheduler: scheduler
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let renamed = try makePage(id: firstPageID, title: "Q4-Roadmap")
        runtime.activate(page: page, source: .typedURL)
        try await repository.waitUntilSaveCount(1)

        runtime.updateActivePageMetadata(renamed)

        XCTAssertTrue(panel.replacedPages.isEmpty)
        XCTAssertEqual(panel.shownPages, [page])
        XCTAssertEqual(panel.currentPage, renamed)
        XCTAssertEqual(runtime.activePage, renamed)
    }

    func testDifferentPageIDStillActivatesAndRecordsVisit() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let scheduler = RuntimeShortcutGestureScheduler()
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            pageMetadataSaveScheduler: scheduler
        )
        let first = try makePage(id: firstPageID, title: "Roadmap")
        let second = try makePage(id: secondPageID, title: "Notes")
        runtime.activate(page: first, source: .typedURL)
        try await repository.waitUntilSaveCount(1)

        runtime.updateActivePageMetadata(second)
        try await repository.waitUntilSaveCount(2)

        let savedVisits = await repository.savedPages()
        XCTAssertEqual(savedVisits, [first, second])
        XCTAssertEqual(runtime.activePage, second)
        XCTAssertEqual(runtime.lastActivationSource, .notionWebSession)
        XCTAssertEqual(panel.currentPage, second)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testOpeningAnotherPageSavesPendingTitleFirst() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let scheduler = RuntimeShortcutGestureScheduler()
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            pageMetadataSaveScheduler: scheduler
        )
        let first = try makePage(id: firstPageID, title: "Roadmap")
        let renamed = first.resolvingDisplayTitle("Q4 Roadmap")
        let second = try makePage(id: secondPageID, title: "Notes")
        runtime.activate(page: first, source: .typedURL)
        try await repository.waitUntilSaveCount(1)

        runtime.updateActivePageMetadata(renamed)
        runtime.activate(page: second, source: .pagePicker)
        try await repository.waitUntilSaveCount(2)
        try await repository.waitUntilMetadataSaveCount(1)

        let savedMetadata = await repository.savedMetadata()
        XCTAssertEqual(savedMetadata, [renamed])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testQuitSavesPendingTitle() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let scheduler = RuntimeShortcutGestureScheduler()
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            pageMetadataSaveScheduler: scheduler
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let renamed = page.resolvingDisplayTitle("Q4 Roadmap")
        runtime.activate(page: page, source: .typedURL)
        try await repository.waitUntilSaveCount(1)

        runtime.updateActivePageMetadata(renamed)
        await runtime.prepareForTermination()

        let savedMetadata = await repository.savedMetadata()
        XCTAssertEqual(savedMetadata, [renamed])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testUnchangedMetadataSchedulesNothing() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let scheduler = RuntimeShortcutGestureScheduler()
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            pageMetadataSaveScheduler: scheduler
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)
        try await repository.waitUntilSaveCount(1)

        runtime.updateActivePageMetadata(page)

        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertTrue(panel.metadataUpdates.isEmpty)
    }
}
