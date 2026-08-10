import Foundation
import XCTest
@testable import Perch

final class NotionPageReferenceTests: XCTestCase {
    private let pageID = "0123456789abcdef0123456789abcdef"

    func testSluggedPageExtractsLowercaseIDTitleAndCanonicalURL() throws {
        let input = try XCTUnwrap(
            URL(string: "https://notion.com/Project-Roadmap-0123456789ABCDEF0123456789ABCDEF")
        )

        let page = try NotionPageReference(validating: input)

        XCTAssertEqual(page.pageID, pageID)
        XCTAssertEqual(page.displayTitle, "Project Roadmap")
        XCTAssertEqual(
            page.canonicalURL.absoluteString,
            "https://www.notion.com/Project-Roadmap-0123456789ABCDEF0123456789ABCDEF"
        )
    }

    func testBarePageIDHasNoDisplayTitle() throws {
        let input = try XCTUnwrap(URL(string: "https://www.notion.com/\(pageID)"))

        let page = try NotionPageReference(validating: input)

        XCTAssertEqual(page.pageID, pageID)
        XCTAssertNil(page.displayTitle)
        XCTAssertEqual(page.canonicalURL.absoluteString, "https://www.notion.com/\(pageID)")
    }

    func testHyphenatedUUIDIsAcceptedAndCanonicalComponentIsPreserved() throws {
        let input = try XCTUnwrap(
            URL(string: "https://www.notion.com/01234567-89ab-cdef-0123-456789abcdef")
        )

        let page = try NotionPageReference(validating: input)

        XCTAssertEqual(page.pageID, pageID)
        XCTAssertNil(page.displayTitle)
        XCTAssertEqual(
            page.canonicalURL.absoluteString,
            "https://www.notion.com/01234567-89ab-cdef-0123-456789abcdef"
        )
    }

    func testCanonicalURLStripsQueryAndFragmentAndNormalizesHost() throws {
        let input = try XCTUnwrap(
            URL(string: "https://notion.com/Roadmap-\(pageID)?view=table#updates")
        )

        let page = try NotionPageReference(validating: input)

        XCTAssertEqual(page.canonicalURL.absoluteString, "https://www.notion.com/Roadmap-\(pageID)")
        XCTAssertNil(page.canonicalURL.query)
        XCTAssertNil(page.canonicalURL.fragment)
    }

    func testWWWWorkspaceRoutePreservesPathWhileStrippingQueryAndFragment() throws {
        let input = try XCTUnwrap(
            URL(string: "https://www.notion.com/acme/Roadmap-\(pageID)?view=table#updates")
        )

        let page = try NotionPageReference(validating: input)

        XCTAssertEqual(page.pageID, pageID)
        XCTAssertEqual(
            page.canonicalURL.absoluteString,
            "https://www.notion.com/acme/Roadmap-\(pageID)"
        )
        XCTAssertNil(page.canonicalURL.query)
        XCTAssertNil(page.canonicalURL.fragment)
    }

    func testBareNotionComWorkspaceRouteNormalizesHostWhilePreservingPath() throws {
        let input = try XCTUnwrap(
            URL(string: "https://notion.com/acme/Roadmap-\(pageID)?view=table#updates")
        )

        let page = try NotionPageReference(validating: input)

        XCTAssertEqual(
            page.canonicalURL.absoluteString,
            "https://www.notion.com/acme/Roadmap-\(pageID)"
        )
    }

    func testCanonicalURLPreservesPercentEncodedWorkspaceSegments() throws {
        let input = try XCTUnwrap(
            URL(string: "https://www.notion.com/acme%2Fworkspace/Roadmap-\(pageID)")
        )

        let page = try NotionPageReference(validating: input)

        XCTAssertEqual(
            page.canonicalURL.absoluteString,
            "https://www.notion.com/acme%2Fworkspace/Roadmap-\(pageID)"
        )
    }

    func testAppHostRemainsAppHostWhileCanonicalURLStripsQueryAndFragment() throws {
        let input = try XCTUnwrap(
            URL(string: "https://app.notion.com/p/acme/Roadmap-\(pageID)?view=table#updates")
        )

        let page = try NotionPageReference(validating: input)

        XCTAssertEqual(page.pageID, pageID)
        XCTAssertEqual(page.displayTitle, "Roadmap")
        XCTAssertEqual(
            page.canonicalURL.absoluteString,
            "https://app.notion.com/p/acme/Roadmap-\(pageID)"
        )
        XCTAssertNil(page.canonicalURL.query)
        XCTAssertNil(page.canonicalURL.fragment)
    }

    func testLegacyNotionSoURLCanonicalizesToNotionCom() throws {
        let input = try XCTUnwrap(
            URL(string: "https://www.notion.so/Roadmap-\(pageID)?view=table#updates")
        )

        let page = try NotionPageReference(validating: input)

        XCTAssertEqual(page.canonicalURL.absoluteString, "https://www.notion.com/Roadmap-\(pageID)")
    }

    func testCredentialsAreRejected() throws {
        try assertRejected(
            "https://user:password@www.notion.com/\(pageID)",
            as: .credentialsNotAllowed
        )
    }

    func testNonHTTPSURLIsRejected() throws {
        try assertRejected("http://www.notion.com/\(pageID)", as: .unsupportedScheme)
    }

    func testWrongHostIsRejected() throws {
        try assertRejected("https://example.com/\(pageID)", as: .unsupportedHost)
        try assertRejected("https://notion.com.example.com/\(pageID)", as: .unsupportedHost)
    }

    func testWorkspaceHomeAndSearchURLsWithoutPageIDsAreRejected() throws {
        try assertRejected("https://www.notion.com", as: .missingPageID)
        try assertRejected("https://www.notion.com/workspace", as: .missingPageID)
        try assertRejected("https://www.notion.com/search", as: .missingPageID)
    }

    func testOversizedURLIsRejected() throws {
        let oversizedSlug = String(repeating: "a", count: 4_097)
        try assertRejected(
            "https://www.notion.com/\(oversizedSlug)-\(pageID)",
            as: .inputTooLong
        )
    }

    private func assertRejected(
        _ rawURL: String,
        as expectedError: NotionPageReferenceError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = try XCTUnwrap(URL(string: rawURL), file: file, line: line)

        XCTAssertThrowsError(
            try NotionPageReference(validating: url),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? NotionPageReferenceError, expectedError, file: file, line: line)
        }
    }
}
