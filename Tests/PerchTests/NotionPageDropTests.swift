import Foundation
import XCTest
@testable import Perch

final class NotionPageDropTests: XCTestCase {
    func testValidatingBuildsCanonicalPageAndCleansSourceLabel() throws {
        let drop = try NotionPageDrop(
            validating: try XCTUnwrap(URL(string: "https://notion.so/Project-Brief-0123456789ABCDEF0123456789ABCDEF")),
            sourceLabel: "  Project\n\tBrief  "
        )

        XCTAssertEqual(drop.page.pageID, "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(
            drop.page.canonicalURL.absoluteString,
            "https://www.notion.com/Project-Brief-0123456789ABCDEF0123456789ABCDEF"
        )
        XCTAssertEqual(drop.sourceLabel, "Project Brief")
    }

    func testSourceLabelRemovesControlAndBidirectionalFormattingScalars() throws {
        let drop = try makeDrop(sourceLabel: "Alpha\u{0000}\u{061C}Beta\u{200E}Gamma\u{202E}Delta\u{2066}Epsilon")

        XCTAssertEqual(drop.sourceLabel, "Alpha Beta Gamma Delta Epsilon")
    }

    func testSourceLabelCapsAtEightyCharacters() throws {
        let label = String(repeating: "🙂", count: 81)
        let drop = try makeDrop(sourceLabel: label)

        XCTAssertEqual(drop.sourceLabel?.count, 80)
        XCTAssertEqual(drop.sourceLabel, String(repeating: "🙂", count: 80))
    }

    func testDisplayLabelPrefersLocalThenSourceThenSlugThenFallback() throws {
        let source = try makeDrop(sourceLabel: "Shared link")
        let slug = try makeDrop(sourceLabel: nil)
        let fallback = try NotionPageDrop(
            validating: try XCTUnwrap(URL(string: "https://www.notion.so/0123456789abcdef0123456789abcdef")),
            sourceLabel: nil
        )

        XCTAssertEqual(source.displayLabel(localTitle: " Local title "), "Local title")
        XCTAssertEqual(source.displayLabel(localTitle: " \n "), "Shared link")
        XCTAssertEqual(slug.displayLabel(localTitle: nil), "Project Brief")
        XCTAssertEqual(fallback.displayLabel(localTitle: nil), "Notion page")
    }

    func testValidatingDefersMalformedURLsToNotionPageReference() throws {
        let oversized = try XCTUnwrap(
            URL(
                string: "https://www.notion.so/Project-0123456789abcdef0123456789abcdef?x="
                    + String(repeating: "a", count: 4_100)
            )
        )
        let cases: [(URL, NotionPageReferenceError)] = [
            (try XCTUnwrap(URL(string: "https://www.notion.so/Project-not-an-id")), .missingPageID),
            (try XCTUnwrap(URL(string: "http://www.notion.so/Project-0123456789abcdef0123456789abcdef")), .unsupportedScheme),
            (try XCTUnwrap(URL(string: "https://www.notion.so.example/Project-0123456789abcdef0123456789abcdef")), .unsupportedHost),
            (try XCTUnwrap(URL(string: "https://user:password@www.notion.so/Project-0123456789abcdef0123456789abcdef")), .credentialsNotAllowed),
            (oversized, .inputTooLong),
        ]

        for (url, expectedError) in cases {
            XCTAssertThrowsError(try NotionPageDrop(validating: url, sourceLabel: nil)) { error in
                XCTAssertEqual(error as? NotionPageReferenceError, expectedError)
            }
        }
    }

    private func makeDrop(sourceLabel: String?) throws -> NotionPageDrop {
        try NotionPageDrop(
            validating: try XCTUnwrap(URL(string: "https://www.notion.so/Project-Brief-0123456789abcdef0123456789abcdef")),
            sourceLabel: sourceLabel
        )
    }
}
