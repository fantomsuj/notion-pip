import Foundation
import XCTest
@testable import NotionPiP

final class HistoryAssemblerTests: XCTestCase {
    func testSectionsUseStablePrecedenceAndDeduplicateByPageID() throws {
        let duplicateID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let pinned = try item(
            id: duplicateID,
            slug: "Pinned-Copy",
            title: "Pinned copy",
            source: .pinned,
            timestamp: 10
        )
        let newerRemoteDuplicate = try item(
            id: duplicateID.uppercased(),
            slug: "Remote-Copy",
            title: "Remote copy",
            source: .notion,
            timestamp: 100
        )
        let draft = try item(id: id(2), title: "Draft", source: .draft, timestamp: 20)
        let captured = try item(id: id(3), title: "Captured", source: .captured, timestamp: 30)
        let remote = try item(id: id(4), title: "Remote", source: .notion, timestamp: 40)
        let input = HistoryInput(items: [remote, newerRemoteDuplicate, captured, draft, pinned])

        let sections = HistoryAssembler.sections(input: input, query: "", limit: 10)

        XCTAssertEqual(sections.map(\.title), ["Pinned", "Drafts", "Captured", "From Notion"])
        XCTAssertEqual(sections.map(\.source), [.pinned, .draft, .captured, .notion])
        XCTAssertEqual(sections.flatMap(\.items).map(\.title), ["Pinned copy", "Draft", "Captured", "Remote"])
        XCTAssertEqual(sections.flatMap(\.items).map(\.page.pageID).filter { $0 == duplicateID }.count, 1)
    }

    func testSearchIsCaseInsensitiveAndOmitsEmptySections() throws {
        let input = HistoryInput(items: [
            try item(id: id(1), title: "Product ROADMAP", source: .pinned, timestamp: 10),
            try item(id: id(2), title: "Meeting notes", source: .draft, timestamp: 20),
        ])

        let sections = HistoryAssembler.sections(input: input, query: "roadmap", limit: 5)

        XCTAssertEqual(sections.map(\.title), ["Pinned"])
        XCTAssertEqual(sections.flatMap(\.items).map(\.title), ["Product ROADMAP"])
    }

    func testRowsSortByDescendingTimestampAndKeepInputOrderForTies() throws {
        let oldest = try item(id: id(1), title: "Oldest", source: .captured, timestamp: 10)
        let tiedFirst = try item(id: id(2), title: "Tied first", source: .captured, timestamp: 20)
        let tiedSecond = try item(id: id(3), title: "Tied second", source: .captured, timestamp: 20)
        let newest = try item(id: id(4), title: "Newest", source: .captured, timestamp: 30)
        let input = HistoryInput(items: [oldest, tiedFirst, tiedSecond, newest])

        let sections = HistoryAssembler.sections(input: input, query: "", limit: 10)

        XCTAssertEqual(
            sections.flatMap(\.items).map(\.title),
            ["Newest", "Tied first", "Tied second", "Oldest"]
        )
    }

    func testLimitAppliesAcrossSectionsAfterPrecedenceAndDeduplication() throws {
        let input = HistoryInput(items: [
            try item(id: id(1), title: "Pinned 1", source: .pinned, timestamp: 10),
            try item(id: id(2), title: "Pinned 2", source: .pinned, timestamp: 20),
            try item(id: id(3), title: "Draft 1", source: .draft, timestamp: 10),
            try item(id: id(4), title: "Draft 2", source: .draft, timestamp: 20),
            try item(id: id(5), title: "Captured 1", source: .captured, timestamp: 10),
            try item(id: id(6), title: "Captured 2", source: .captured, timestamp: 20),
            try item(id: id(7), title: "Remote", source: .notion, timestamp: 30),
        ])

        let sections = HistoryAssembler.sections(input: input, query: "", limit: 5)

        XCTAssertEqual(sections.flatMap(\.items).count, 5)
        XCTAssertEqual(
            sections.flatMap(\.items).map(\.title),
            ["Pinned 2", "Pinned 1", "Draft 2", "Draft 1", "Captured 2"]
        )
        XCTAssertEqual(sections.map(\.title), ["Pinned", "Drafts", "Captured"])
    }

    func testZeroLimitProducesNoSections() throws {
        let input = HistoryInput(items: [
            try item(id: id(1), title: "Pinned", source: .pinned, timestamp: 10),
        ])

        XCTAssertTrue(HistoryAssembler.sections(input: input, query: "", limit: 0).isEmpty)
    }

    private func item(
        id: String,
        slug: String? = nil,
        title: String,
        source: HistorySource,
        timestamp: TimeInterval
    ) throws -> HistoryItem {
        let component = slug.map { "\($0)-\(id)" } ?? id
        let url = try XCTUnwrap(URL(string: "https://www.notion.so/\(component)"))
        return HistoryItem(
            page: try NotionPageReference(validating: url),
            title: title,
            source: source,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }

    private func id(_ value: Int) -> String {
        String(format: "%032x", value)
    }
}
