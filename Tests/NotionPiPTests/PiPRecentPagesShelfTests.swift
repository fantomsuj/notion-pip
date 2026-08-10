import Foundation
import XCTest
@testable import NotionPiP

final class PiPRecentPagesShelfTests: XCTestCase {
    func testAccessibilityCopyDescribesCurrentAndRestorableRows() {
        XCTAssertEqual(
            PiPRecentPagesShelfAccessibility.rowLabel(
                title: "Product roadmap",
                recency: "Current",
                isCurrent: true
            ),
            "Product roadmap, Current, active Notion PiP page"
        )
        XCTAssertEqual(
            PiPRecentPagesShelfAccessibility.rowHint(isCurrent: false),
            "Restore this recent page in Notion PiP"
        )
        XCTAssertEqual(
            PiPRecentPagesShelfAccessibility.rowHint(isCurrent: true),
            "Restore the current Notion PiP page without reloading"
        )
    }

    @MainActor
    func testLoadPublishesFiveRowsAndMarksCurrentPage() async throws {
        let snapshot = try makeRecentSnapshot(count: 7, activeIndex: 1)
        let controller = PiPRecentPagesShelfController(
            store: RecentPagesStore(snapshot: snapshot),
            clock: TestDateProvider(Date(timeIntervalSince1970: 10_000)),
            timeZone: utc
        )

        await controller.load()

        XCTAssertEqual(controller.items.count, 5)
        XCTAssertEqual(controller.items.filter(\.isCurrent).map(\.page.pageID), [
            snapshot.pages[1].pageID
        ])
        XCTAssertTrue(controller.isAvailable)
    }

    @MainActor
    func testSelectionValidatesURLAndIncludesMatchingRestoration() async throws {
        let snapshot = try makeRecentSnapshot(count: 2, activeIndex: 0, restorationIndex: 1)
        let controller = PiPRecentPagesShelfController(
            store: RecentPagesStore(snapshot: snapshot),
            clock: TestDateProvider(Date(timeIntervalSince1970: 10_000)),
            timeZone: utc
        )
        await controller.load()

        let selection = try XCTUnwrap(controller.selection(for: snapshot.pages[1].pageID.uppercased()))

        XCTAssertEqual(selection.page.pageID, snapshot.pages[1].pageID)
        XCTAssertEqual(selection.restoration, snapshot.restorations.first)
    }

    @MainActor
    func testSelectionForCurrentPageStillReturnsSelection() async throws {
        let snapshot = try makeRecentSnapshot(count: 2, activeIndex: 0)
        let controller = PiPRecentPagesShelfController(
            store: RecentPagesStore(snapshot: snapshot),
            clock: TestDateProvider(Date(timeIntervalSince1970: 10_000)),
            timeZone: utc
        )
        await controller.load()

        XCTAssertEqual(
            controller.selection(for: snapshot.pages[0].pageID)?.page.pageID,
            snapshot.pages[0].pageID
        )
    }

    @MainActor
    func testInvalidStoredURLCannotProduceSelection() async throws {
        let invalid = StoredPageSnapshot(
            pageID: pageID(0),
            canonicalURL: try XCTUnwrap(URL(string: "https://example.com/not-notion")),
            displayTitle: "Invalid",
            timestamp: Date(timeIntervalSince1970: 9_000)
        )
        let snapshot = PiPRecentPagesSnapshot(
            activePageID: invalid.pageID,
            pages: [invalid],
            restorations: []
        )
        let controller = PiPRecentPagesShelfController(
            store: RecentPagesStore(snapshot: snapshot),
            clock: TestDateProvider(Date(timeIntervalSince1970: 10_000)),
            timeZone: utc
        )
        await controller.load()

        XCTAssertNil(controller.selection(for: invalid.pageID))
    }

    @MainActor
    func testRepositoryFailureSuppressesShelfAvailability() async {
        let controller = PiPRecentPagesShelfController(
            store: FailingRecentPagesStore(),
            clock: TestDateProvider(Date(timeIntervalSince1970: 10_000)),
            timeZone: utc
        )

        await controller.load()

        XCTAssertTrue(controller.items.isEmpty)
        XCTAssertFalse(controller.isAvailable)
    }

    @MainActor
    func testOverlappingLoadsIgnoreStaleSlowerCompletion() async throws {
        let stale = try makeRecentSnapshot(count: 2, activeIndex: 0, titlePrefix: "Stale")
        let fresh = try makeRecentSnapshot(count: 3, activeIndex: 1, titlePrefix: "Fresh")
        let store = DelayedRecentPagesStore(
            responses: [
                .init(snapshot: stale, delay: .milliseconds(100)),
                .init(snapshot: fresh, delay: .zero)
            ]
        )
        let controller = PiPRecentPagesShelfController(
            store: store,
            clock: TestDateProvider(Date(timeIntervalSince1970: 10_000)),
            timeZone: utc
        )

        let staleLoad = Task { await controller.load() }
        await store.waitUntilRequestCount(1)
        await controller.load()
        await staleLoad.value

        XCTAssertEqual(controller.items.map(\.page.displayTitle), fresh.pages.map(\.displayTitle))
        XCTAssertEqual(controller.items.filter(\.isCurrent).map(\.page.pageID), [fresh.pages[1].pageID])
    }

    func testRecencyClassificationAndLabelsAreDeterministic() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let locale = Locale(identifier: "en_US_POSIX")
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))
        )

        let cases: [(TimeInterval, String)] = [
            (30, "Just now"),
            (8 * 60, "8 min ago"),
            (2 * 60 * 60, "2 hr ago"),
            (25 * 60 * 60, "Yesterday"),
            (3 * 24 * 60 * 60, "Fri"),
            (11 * 24 * 60 * 60, "Jul 30")
        ]

        XCTAssertEqual(PiPRecentPageRecency.current.label(locale: locale, calendar: calendar), "Current")
        for (age, expected) in cases {
            let recency = PiPRecentPageRecency.classify(
                visitedAt: now.addingTimeInterval(-age),
                now: now,
                calendar: calendar
            )
            XCTAssertEqual(recency.label(locale: locale, calendar: calendar), expected)
        }
        XCTAssertEqual(
            PiPRecentPageRecency.classify(
                visitedAt: now.addingTimeInterval(60),
                now: now,
                calendar: calendar
            ),
            .justNow
        )
    }

    private func makeRecentSnapshot(
        count: Int,
        activeIndex: Int,
        restorationIndex: Int? = nil,
        titlePrefix: String = "Page"
    ) throws -> PiPRecentPagesSnapshot {
        let pages = try (0..<count).map { index in
            StoredPageSnapshot(
                pageID: pageID(index),
                canonicalURL: try pageURL(index),
                displayTitle: "\(titlePrefix) \(index)",
                timestamp: Date(timeIntervalSince1970: 10_000 - Double(index * 60))
            )
        }
        let restorations = try restorationIndex.map { index in
            [try DurablePageRestoration(
                pageID: pages[index].pageID,
                validatingLastURL: pages[index].canonicalURL,
                scrollX: 0,
                scrollY: 42,
                scrollProgress: 0.5,
                updatedAt: Date(timeIntervalSince1970: 10_000)
            )]
        } ?? []
        return PiPRecentPagesSnapshot(
            activePageID: pages[activeIndex].pageID,
            pages: pages,
            restorations: restorations
        )
    }

    private func pageID(_ index: Int) -> String {
        String(format: "%032x", index + 1)
    }

    private func pageURL(_ index: Int) throws -> URL {
        try XCTUnwrap(URL(string: "https://www.notion.so/Page-\(index)-\(pageID(index))"))
    }

    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }
}

private actor RecentPagesStore: PiPRecentPagesProviding {
    let snapshot: PiPRecentPagesSnapshot

    init(snapshot: PiPRecentPagesSnapshot) {
        self.snapshot = snapshot
    }

    func recentPiPPages(limit: Int) -> PiPRecentPagesSnapshot {
        PiPRecentPagesSnapshot(
            activePageID: snapshot.activePageID,
            pages: Array(snapshot.pages.prefix(max(limit, 0))),
            restorations: snapshot.restorations
        )
    }
}

private actor FailingRecentPagesStore: PiPRecentPagesProviding {
    enum Failure: Error { case unavailable }

    func recentPiPPages(limit: Int) throws -> PiPRecentPagesSnapshot {
        throw Failure.unavailable
    }
}

private actor DelayedRecentPagesStore: PiPRecentPagesProviding {
    struct Response: Sendable {
        let snapshot: PiPRecentPagesSnapshot
        let delay: Duration
    }

    private let responses: [Response]
    private var requestCount = 0

    init(responses: [Response]) {
        self.responses = responses
    }

    func recentPiPPages(limit: Int) async throws -> PiPRecentPagesSnapshot {
        let index = requestCount
        requestCount += 1
        let response = responses[index]
        try await Task.sleep(for: response.delay)
        return PiPRecentPagesSnapshot(
            activePageID: response.snapshot.activePageID,
            pages: Array(response.snapshot.pages.prefix(max(limit, 0))),
            restorations: response.snapshot.restorations
        )
    }

    func waitUntilRequestCount(_ expected: Int) async {
        while requestCount < expected {
            await Task.yield()
        }
    }
}
