import Foundation
import XCTest
@testable import Perch

final class PinnedPageRoleTests: XCTestCase {
    func testNormalizationTrimsCollapsesWhitespaceAndCapsUserPerceivedCharacters() throws {
        let longRole = "  Today\n\t " + String(repeating: "🧑🏽‍💻", count: 40)

        let role = try XCTUnwrap(
            PinnedPageRole.normalized(longRole, for: "page", among: [])
        )

        XCTAssertTrue(role.hasPrefix("Today "))
        XCTAssertEqual(role.count, PinnedPageRole.maximumLength)
        XCTAssertFalse(role.contains("\n"))
        XCTAssertFalse(role.contains("\t"))
    }

    func testNormalizationRejectsBlankRole() {
        XCTAssertThrowsError(
            try PinnedPageRole.normalized(" \n\t ", for: "page", among: [])
        ) {
            XCTAssertEqual($0 as? PageRepositoryError, .blankRole)
        }
    }

    func testNormalizationRejectsCaseAndDiacriticInsensitiveDuplicate() throws {
        let pinned = StoredPageSnapshot(
            pageID: "first",
            canonicalURL: try XCTUnwrap(URL(string: "https://www.notion.so/First-0123456789abcdef0123456789abcdef")),
            displayTitle: "First",
            role: "Résumé",
            timestamp: .distantPast
        )

        XCTAssertThrowsError(
            try PinnedPageRole.normalized(
                "resume",
                for: "second",
                among: [pinned]
            )
        ) {
            XCTAssertEqual($0 as? PageRepositoryError, .duplicateRole)
        }
    }
}
