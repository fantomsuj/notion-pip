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

    func testBrowserApplicationNameDoesNotSuggestAPageAboutThatBrowser() {
        let chromeNotes = page(1, title: "Google Chrome shortcuts")
        let snapshot = workingSet(pinned: [chromeNotes])

        XCTAssertNil(
            ContextSuggestionMatcher.bestSuggestion(
                in: snapshot,
                context: ContextSnapshot(
                    bundleIdentifier: "com.google.Chrome",
                    applicationName: "Google Chrome",
                    windowTitle: "Pull requests · GitHub - Google Chrome",
                    documentURL: URL(string: "https://github.com/fantomsuj/notion-pip/pulls")!
                ),
                activePageID: nil
            )
        )
    }

    func testBrowserWindowChromeSuffixDoesNotSuggestABrowserNamedPage() {
        let safariBookmarks = page(1, title: "Safari bookmarks")
        let snapshot = workingSet(pinned: [safariBookmarks])

        XCTAssertNil(
            ContextSuggestionMatcher.bestSuggestion(
                in: snapshot,
                context: ContextSnapshot(
                    bundleIdentifier: "com.apple.Safari",
                    applicationName: "Safari",
                    windowTitle: "Inbox - Safari",
                    documentURL: URL(string: "https://mail.example.com/inbox")!
                ),
                activePageID: nil
            )
        )
    }

    func testNativeAppRoleMatchesWithoutWindowTitleOverlap() throws {
        let buildNotes = page(1, title: "Build Notes", role: "Xcode")
        let snapshot = workingSet(pinned: [buildNotes])

        let suggestion = ContextSuggestionMatcher.bestSuggestion(
            in: snapshot,
            context: ContextSnapshot(
                bundleIdentifier: "com.apple.dt.Xcode",
                applicationName: "Xcode",
                windowTitle: "Package.swift",
                documentURL: nil
            ),
            activePageID: nil
        )

        XCTAssertEqual(suggestion?.page.pageID, buildNotes.pageID)
        XCTAssertEqual(suggestion?.label, "Xcode")
    }

    func testNativeAppNameMatchesAPageTitledForThatApp() throws {
        let slackStandup = page(1, title: "Slack standup")
        let snapshot = workingSet(pinned: [slackStandup])

        let suggestion = ContextSuggestionMatcher.bestSuggestion(
            in: snapshot,
            context: ContextSnapshot(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                applicationName: "Slack",
                windowTitle: "engineering-project",
                documentURL: nil
            ),
            activePageID: nil
        )

        XCTAssertEqual(suggestion?.page.pageID, slackStandup.pageID)
    }

    func testExactWorkingSetPageFromDocumentURLOutranksTitleOverlap() throws {
        let exactPage = page(1, title: "Roadmap")
        let titleOverlap = page(2, title: "GitHub Reading List")
        let snapshot = workingSet(pinned: [titleOverlap, exactPage])

        let suggestion = ContextSuggestionMatcher.bestSuggestion(
            in: snapshot,
            context: ContextSnapshot(
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                windowTitle: "GitHub",
                documentURL: exactPage.canonicalURL
            ),
            activePageID: nil
        )

        XCTAssertEqual(suggestion?.page.pageID, exactPage.pageID)
    }

    func testNotionHostDoesNotSuggestAnUnrelatedNotionTitledPage() {
        let notionTips = page(1, title: "Notion tips")
        let snapshot = workingSet(pinned: [notionTips])
        let otherPageID = String(format: "%032x", 99)

        XCTAssertNil(
            ContextSuggestionMatcher.bestSuggestion(
                in: snapshot,
                context: ContextSnapshot(
                    bundleIdentifier: "com.google.Chrome",
                    applicationName: "Google Chrome",
                    windowTitle: "Private",
                    documentURL: URL(string: "https://www.notion.com/Private-\(otherPageID)")!
                ),
                activePageID: nil
            )
        )
    }

    func testHostMatchesPinnedRoleWhenTheWindowTitleIsGeneric() throws {
        let linear = page(1, title: "Daily Planner", role: "Linear")
        let snapshot = workingSet(pinned: [linear])

        let suggestion = ContextSuggestionMatcher.bestSuggestion(
            in: snapshot,
            context: ContextSnapshot(
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                windowTitle: "Dashboard",
                documentURL: URL(string: "https://linear.app/acme/issue/ABC-1")!
            ),
            activePageID: nil
        )

        XCTAssertEqual(suggestion?.page.pageID, linear.pageID)
        XCTAssertEqual(suggestion?.label, "Linear")
    }

    func testPluralWindowTitleMatchesSingularPageTitle() throws {
        let meetingNotes = page(1, title: "Meeting notes")
        let snapshot = workingSet(pinned: [meetingNotes])

        let suggestion = ContextSuggestionMatcher.bestSuggestion(
            in: snapshot,
            context: ContextSnapshot(
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                windowTitle: "Meetings with Alex",
                documentURL: nil
            ),
            activePageID: nil
        )

        XCTAssertEqual(suggestion?.page.pageID, meetingNotes.pageID)
    }

    func testNotionDesktopApplicationNameDoesNotSuggestAGenericNotionTitledPage() {
        let notionTips = page(1, title: "Notion tips")
        let snapshot = workingSet(pinned: [notionTips])

        XCTAssertNil(
            ContextSuggestionMatcher.bestSuggestion(
                in: snapshot,
                context: ContextSnapshot(
                    bundleIdentifier: "notion.id",
                    applicationName: "Notion",
                    windowTitle: "All pages",
                    documentURL: nil
                ),
                activePageID: nil
            )
        )
    }

    func testFileURLHomeDirectoriesDoNotMatchGenericPageTitles() {
        let documents = page(1, title: "Documents")
        let snapshot = workingSet(pinned: [documents])

        XCTAssertNil(
            ContextSuggestionMatcher.bestSuggestion(
                in: snapshot,
                context: ContextSnapshot(
                    bundleIdentifier: "com.apple.dt.Xcode",
                    applicationName: "Xcode",
                    windowTitle: "Package.swift",
                    documentURL: URL(string: "file:///Users/alex/Documents/Projects/perch/Package.swift")!
                ),
                activePageID: nil
            )
        )
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
