import Foundation
import XCTest
@testable import Perch

final class ContextSuggestionMatcherTests: XCTestCase {
    func testRoleMatchOutranksTitleMatch() throws {
        let roleMatch = page(1, title: "Daily Planner", role: "GitHub")
        let titleMatch = page(2, title: "GitHub Reading List")
        let snapshot = workingSet(pinned: [titleMatch, roleMatch])

        let suggestion = ContextSuggestionMatcher.bestSuggestion(
            in: snapshot,
            context: ContextSnapshot(
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                windowTitle: "Pull requests · GitHub",
                documentURL: URL(string: "https://github.com/fantomsuj/notion-pip/pulls")!
            ),
            activePageID: nil
        )

        XCTAssertEqual(suggestion?.page.pageID, roleMatch.pageID)
    }

    func testTitleMatchUsesBrowserDocumentURLTokens() throws {
        let target = page(1, title: "Notion PiP Project")
        let snapshot = workingSet(pinned: [target])

        let suggestion = ContextSuggestionMatcher.bestSuggestion(
            in: snapshot,
            context: ContextSnapshot(
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Pull requests",
                documentURL: URL(string: "https://github.com/fantomsuj/notion-pip/pulls")!
            ),
            activePageID: nil
        )

        XCTAssertEqual(suggestion?.page.pageID, target.pageID)
    }

    func testCurrentPageIsNeverSuggested() throws {
        let current = page(1, title: "GitHub")
        let fallback = page(2, title: "GitHub Notes")
        let snapshot = workingSet(pinned: [current, fallback])

        let suggestion = ContextSuggestionMatcher.bestSuggestion(
            in: snapshot,
            context: ContextSnapshot(
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                windowTitle: "GitHub",
                documentURL: nil
            ),
            activePageID: current.pageID
        )

        XCTAssertEqual(suggestion?.page.pageID, fallback.pageID)
    }

    func testLowConfidenceContextReturnsNoSuggestion() {
        let snapshot = workingSet(pinned: [page(1, title: "Project Brief")])

        XCTAssertNil(
            ContextSuggestionMatcher.bestSuggestion(
                in: snapshot,
                context: ContextSnapshot(
                    bundleIdentifier: "com.apple.mail",
                    applicationName: "Mail",
                    windowTitle: "Inbox",
                    documentURL: nil
                ),
                activePageID: nil
            )
        )
    }

    func testPinnedPageWinsAnEqualScoreTie() throws {
        let pinned = page(2, title: "GitHub")
        let recent = page(1, title: "GitHub")
        let snapshot = workingSet(pinned: [pinned], recent: [recent])

        let suggestion = ContextSuggestionMatcher.bestSuggestion(
            in: snapshot,
            context: ContextSnapshot(
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                windowTitle: "GitHub",
                documentURL: nil
            ),
            activePageID: nil
        )

        XCTAssertEqual(suggestion?.page.pageID, pinned.pageID)
    }

    func testSuggestionCarriesSavedRestorationPosition() throws {
        let target = page(1, title: "GitHub")
        let restoration = try DurablePageRestoration(
            pageID: target.pageID,
            validatingLastURL: target.canonicalURL,
            scrollX: 0,
            scrollY: 840,
            scrollProgress: 0.6,
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let snapshot = workingSet(pinned: [target], restorations: [restoration])

        let suggestion = ContextSuggestionMatcher.bestSuggestion(
            in: snapshot,
            context: ContextSnapshot(
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                windowTitle: "GitHub",
                documentURL: nil
            ),
            activePageID: nil
        )

        XCTAssertEqual(suggestion?.restoration, restoration)
    }

    private func page(
        _ number: Int,
        title: String,
        role: String? = nil,
        timestamp: TimeInterval = 10
    ) -> StoredPageSnapshot {
        let pageID = String(format: "%032x", number)
        return StoredPageSnapshot(
            pageID: pageID,
            canonicalURL: URL(string: "https://www.notion.com/\(pageID)")!,
            displayTitle: title,
            role: role,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }

    private func workingSet(
        pinned: [StoredPageSnapshot],
        recent: [StoredPageSnapshot] = [],
        restorations: [DurablePageRestoration] = []
    ) -> PageWorkingSetSnapshot {
        PageWorkingSetSnapshot(
            activePage: nil,
            pinnedPages: pinned,
            recentPages: recent,
            restorations: restorations
        )
    }
}
