import Foundation
import XCTest
@testable import Perch

final class MarginNoteTests: XCTestCase {
    private let fixedTime: (Date) -> String = { _ in "Nov 7, 11:42 AM" }

    func testMarkdownLinksTheWindowTitleToItsDocument() throws {
        let note = MarginNote(
            text: "Ask about rate limits",
            createdAt: Date(timeIntervalSince1970: 0),
            source: MarginNoteSource(
                applicationName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                windowTitle: "Rate limits",
                documentURL: try XCTUnwrap(URL(string: "https://docs.stripe.com/rate-limits"))
            )
        )

        XCTAssertEqual(
            note.markdown(formatTime: fixedTime),
            "- Ask about rate limits — _Safari · [Rate limits](https://docs.stripe.com/rate-limits) · Nov 7, 11:42 AM_"
        )
    }

    func testMarkdownWithOnlyAnAppName() {
        let note = MarginNote(
            text: "Call back",
            createdAt: Date(timeIntervalSince1970: 0),
            source: MarginNoteSource(applicationName: "Slack")
        )

        XCTAssertEqual(note.markdown(formatTime: fixedTime), "- Call back — _Slack · Nov 7, 11:42 AM_")
    }

    func testMarkdownWithoutASourceKeepsTheTime() {
        let note = MarginNote(text: "Idea", createdAt: Date(timeIntervalSince1970: 0), source: nil)

        XCTAssertEqual(note.markdown(formatTime: fixedTime), "- Idea — _Nov 7, 11:42 AM_")
    }

    func testMarkdownJoinsLinesIntoOneBullet() {
        let note = MarginNote(
            text: "first line\n\n  second line  ",
            createdAt: Date(timeIntervalSince1970: 0),
            source: nil
        )

        XCTAssertEqual(note.markdown(formatTime: fixedTime), "- first line second line — _Nov 7, 11:42 AM_")
    }

    func testMarkdownEscapesTitlesAndSkipsUnsafeLinks() throws {
        let note = MarginNote(
            text: "Check",
            createdAt: Date(timeIntervalSince1970: 0),
            source: MarginNoteSource(
                applicationName: "Preview",
                windowTitle: "notes_[draft].pdf",
                documentURL: try XCTUnwrap(URL(string: "javascript:alert(1)"))
            )
        )

        XCTAssertEqual(
            note.markdown(formatTime: fixedTime),
            "- Check — _Preview · notes\\_\\[draft\\].pdf · Nov 7, 11:42 AM_"
        )
    }

    func testWindowTitleMatchingTheAppNameIsLeftOut() {
        let source = MarginNoteSource(applicationName: "Finder", windowTitle: "Finder")
        let note = MarginNote(text: "x", createdAt: Date(timeIntervalSince1970: 0), source: source)

        XCTAssertEqual(source.summary, "Finder")
        XCTAssertEqual(note.markdown(formatTime: fixedTime), "- x — _Finder · Nov 7, 11:42 AM_")
    }

    func testNormalizedTextDropsBlankNotes() {
        XCTAssertNil(MarginNote.normalizedText("  \n "))
        XCTAssertEqual(MarginNote.normalizedText("  hi \n"), "hi")
    }
}
