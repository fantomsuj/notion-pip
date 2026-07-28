import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class PageSwitcherMatcherTests: XCTestCase {
    func testEmptyQueryPreservesPinnedAndRecentSectionsInStoredOrder() throws {
        let pinned = [try item(number: 2, title: "Second", pinned: true, timestamp: 20),
                      try item(number: 1, title: "First", pinned: true, timestamp: 10)]
        let recent = [try item(number: 4, title: "Fourth", pinned: false, timestamp: 40),
                      try item(number: 3, title: "Third", pinned: false, timestamp: 30)]

        let sections = PageSwitcherMatcher.sections(
            pinned: pinned,
            recents: recent,
            activePageID: recent[0].page.pageID,
            query: ""
        )

        XCTAssertEqual(sections.map(\.title), ["Pinned", "Recent"])
        XCTAssertEqual(
            sections.flatMap(\.items).map(\.page.displayTitle),
            ["Second", "First", "Fourth", "Third"]
        )
        XCTAssertTrue(sections[1].items[0].isActive)
    }

    func testFuzzyMatchingNormalizesDiacriticsAndMatchesOrderedTokenSubsequences() throws {
        let target = try item(
            number: 1,
            title: "Café Product Roadmap",
            pinned: false,
            timestamp: 10
        )
        let distractor = try item(number: 2, title: "Release Notes", pinned: false, timestamp: 20)

        let sections = PageSwitcherMatcher.sections(
            pinned: [],
            recents: [distractor, target],
            activePageID: nil,
            query: "cfe rdmp"
        )

        XCTAssertEqual(sections.flatMap(\.items).map(\.page.pageID), [target.page.pageID])
    }

    func testTitleMatchRanksAheadOfPinnedPageIDMatch() throws {
        let titleMatch = try item(number: 1, title: "Alpha Feature", pinned: false, timestamp: 10)
        let idMatch = try item(
            id: "af000000000000000000000000000000",
            title: "Unrelated",
            pinned: true,
            timestamp: 20
        )

        let sections = PageSwitcherMatcher.sections(
            pinned: [idMatch],
            recents: [titleMatch],
            activePageID: nil,
            query: "af"
        )

        XCTAssertEqual(
            sections.flatMap(\.items).map(\.page.pageID),
            [titleMatch.page.pageID, idMatch.page.pageID]
        )
    }

    func testEqualScoresBreakTiesByPinnedThenTimestampThenStableID() throws {
        let pinnedOlder = try item(number: 3, title: "Plan", pinned: true, timestamp: 10)
        let pinnedNewerHighID = try item(number: 2, title: "Plan", pinned: true, timestamp: 20)
        let pinnedNewerLowID = try item(number: 1, title: "Plan", pinned: true, timestamp: 20)
        let recentNewest = try item(number: 4, title: "Plan", pinned: false, timestamp: 30)

        let sections = PageSwitcherMatcher.sections(
            pinned: [pinnedOlder, pinnedNewerHighID, pinnedNewerLowID],
            recents: [recentNewest],
            activePageID: nil,
            query: "plan"
        )

        XCTAssertEqual(
            sections.flatMap(\.items).map(\.page.pageID),
            [
                pinnedNewerLowID.page.pageID,
                pinnedNewerHighID.page.pageID,
                pinnedOlder.page.pageID,
                recentNewest.page.pageID,
            ]
        )
    }

    func testUnmatchedQueryReturnsNoSections() throws {
        let page = try item(number: 1, title: "Roadmap", pinned: false, timestamp: 10)

        XCTAssertTrue(
            PageSwitcherMatcher.sections(
                pinned: [],
                recents: [page],
                activePageID: nil,
                query: "zzzz"
            ).isEmpty
        )
    }

    func testControllerTraversesRowsAndActiveSelectionDismissesWithoutActivation() async throws {
        let active = try item(number: 1, title: "Active", pinned: true, timestamp: 20)
        let recent = try item(number: 2, title: "Recent", pinned: false, timestamp: 10)
        let store = InMemoryPageWorkingSetStore(
            snapshot: PageWorkingSetSnapshot(
                activePage: active.page,
                pinnedPages: [active.page],
                recentPages: [recent.page],
                restorations: []
            )
        )
        let controller = PageSwitcherController(store: store)
        await controller.load()

        XCTAssertEqual(controller.selectedPageID, active.page.pageID)
        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.selectedPageID, recent.page.pageID)
        controller.moveSelection(by: -1)

        XCTAssertEqual(controller.selectCurrent(), .dismiss)
    }

    func testControllerSurfacesPinLimitFeedbackWithoutChangingPins() async throws {
        let pages = try (0..<8).map {
            try item(number: $0 + 1, title: "Page \($0 + 1)", pinned: $0 < 7, timestamp: Double($0))
        }
        let store = InMemoryPageWorkingSetStore(
            snapshot: PageWorkingSetSnapshot(
                activePage: pages[7].page,
                pinnedPages: pages.prefix(7).map(\.page),
                recentPages: [pages[7].page],
                restorations: []
            )
        )
        let controller = PageSwitcherController(store: store)
        await controller.load()

        await controller.setPinned(true, pageID: pages[7].page.pageID)

        XCTAssertEqual(controller.inlineFeedback, "Unpin a page first.")
        XCTAssertEqual(controller.sections.first?.items.count, 7)
    }

    private func item(
        number: Int,
        title: String,
        pinned: Bool,
        timestamp: TimeInterval
    ) throws -> PageSwitcherItem {
        try item(
            id: String(format: "%032x", number),
            title: title,
            pinned: pinned,
            timestamp: timestamp
        )
    }

    private func item(
        id: String,
        title: String,
        pinned: Bool,
        timestamp: TimeInterval
    ) throws -> PageSwitcherItem {
        let page = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/\(title.replacingOccurrences(of: " ", with: "-"))-\(id)"))
        )
        return PageSwitcherItem(
            page: StoredPageSnapshot(
                pageID: page.pageID,
                canonicalURL: page.canonicalURL,
                displayTitle: title,
                timestamp: Date(timeIntervalSince1970: timestamp)
            ),
            isPinned: pinned,
            isActive: false
        )
    }
}
