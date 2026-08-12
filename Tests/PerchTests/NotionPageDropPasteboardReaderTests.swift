import AppKit
import XCTest
@testable import Perch

@MainActor
final class NotionPageDropPasteboardReaderTests: XCTestCase {
    func testAcceptsOneURLItem() throws {
        let pasteboard = makePasteboard()
        writeItem(url: try validURL(), to: pasteboard)

        let candidate = NotionPageDropPasteboardReader.candidate(from: pasteboard)

        XCTAssertEqual(candidate?.page.pageID, pageID)
    }

    func testAcceptsOneWholeStringURL() throws {
        let pasteboard = makePasteboard()
        let url = try validURL()
        writeItem(string: "  \(url.absoluteString)\n", to: pasteboard)

        XCTAssertEqual(
            NotionPageDropPasteboardReader.candidate(from: pasteboard)?.page.canonicalURL,
            try NotionPageReference(validating: url).canonicalURL
        )
    }

    func testPropagatesURLNameWithoutMutatingPasteboard() throws {
        let pasteboard = makePasteboard()
        writeItem(url: try validURL(), urlName: "  Team\nBrief  ", to: pasteboard)
        let changeCount = pasteboard.changeCount

        let candidate = NotionPageDropPasteboardReader.candidate(from: pasteboard)

        XCTAssertEqual(candidate?.sourceLabel, "Team Brief")
        XCTAssertEqual(pasteboard.changeCount, changeCount)
    }

    func testURLTakesPrecedenceOverStringFallback() throws {
        let pasteboard = makePasteboard()
        writeItem(
            url: try XCTUnwrap(URL(string: "https://example.com/not-notion")),
            string: try validURL().absoluteString,
            to: pasteboard
        )

        XCTAssertNil(NotionPageDropPasteboardReader.candidate(from: pasteboard))
    }

    func testRejectsWhitespacePaddedURLRepresentation() throws {
        let pasteboard = makePasteboard()
        let item = NSPasteboardItem()
        item.setString(" \(try validURL().absoluteString) ", forType: .URL)
        XCTAssertTrue(pasteboard.writeObjects([item]))

        XCTAssertNil(NotionPageDropPasteboardReader.candidate(from: pasteboard))
    }

    func testRejectsNoURLOrEmbeddedProse() throws {
        let noURL = makePasteboard()
        writeItem(string: "A page title", to: noURL)
        let prose = makePasteboard()
        writeItem(string: "Open \(try validURL().absoluteString) now", to: prose)

        XCTAssertNil(NotionPageDropPasteboardReader.candidate(from: noURL))
        XCTAssertNil(NotionPageDropPasteboardReader.candidate(from: prose))
    }

    func testRejectsInvalidNotionURLsAndUnsupportedFileRepresentations() throws {
        let invalid = makePasteboard()
        writeItem(
            url: try XCTUnwrap(URL(string: "https://www.notion.so/not-a-page")),
            to: invalid
        )
        let file = makePasteboard()
        writeItem(fileURL: URL(fileURLWithPath: "/tmp/example.webloc"), to: file)
        let webloc = makePasteboard()
        writeWebloc(to: webloc)

        XCTAssertNil(NotionPageDropPasteboardReader.candidate(from: invalid))
        XCTAssertNil(NotionPageDropPasteboardReader.candidate(from: file))
        XCTAssertNil(NotionPageDropPasteboardReader.candidate(from: webloc))
    }

    func testRejectsTwoPasteboardItemsAndMultipleURLValues() throws {
        let twoItems = makePasteboard()
        let url = try validURL()
        let first = makeItem(url: url)
        let second = makeItem(url: url)
        XCTAssertTrue(twoItems.writeObjects([first, second]))

        let multipleURLs = makePasteboard()
        let urls = "\(url.absoluteString)\nhttps://www.notion.so/Other-fedcba9876543210fedcba9876543210"
        let item = NSPasteboardItem()
        item.setString(urls, forType: .URL)
        XCTAssertTrue(multipleURLs.writeObjects([item]))

        XCTAssertNil(NotionPageDropPasteboardReader.candidate(from: twoItems))
        XCTAssertNil(NotionPageDropPasteboardReader.candidate(from: multipleURLs))
    }

    private var pageID: String { "0123456789abcdef0123456789abcdef" }

    private func validURL() throws -> URL {
        try XCTUnwrap(URL(string: "https://www.notion.so/Project-Brief-\(pageID)"))
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("NotionPageDropPasteboardReaderTests.\(UUID())"))
        pasteboard.clearContents()
        return pasteboard
    }

    private func makeItem(
        url: URL? = nil,
        string: String? = nil,
        urlName: String? = nil
    ) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        if let url {
            item.setString(url.absoluteString, forType: .URL)
        }
        if let string {
            item.setString(string, forType: .string)
        }
        if let urlName {
            item.setString(urlName, forType: .init("public.url-name"))
        }
        return item
    }

    private func writeItem(
        url: URL? = nil,
        string: String? = nil,
        urlName: String? = nil,
        to pasteboard: NSPasteboard
    ) {
        XCTAssertTrue(pasteboard.writeObjects([makeItem(url: url, string: string, urlName: urlName)]))
    }

    private func writeItem(fileURL: URL, to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        XCTAssertTrue(pasteboard.writeObjects([item]))
    }

    private func writeWebloc(to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        item.setData(Data(), forType: .init("com.apple.web-internet-location"))
        XCTAssertTrue(pasteboard.writeObjects([item]))
    }
}
