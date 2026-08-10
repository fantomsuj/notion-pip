import Security
import XCTest
@testable import NotionPiP

final class LegacyPersonalTokenRemoverTests: XCTestCase {
    func testRemovalDeletesDataProtectionAndLegacyItemsForExactCredential() throws {
        var queries: [[String: Any]] = []
        let remover = LegacyPersonalTokenRemover { query in
            queries.append(query)
            return errSecSuccess
        }

        try remover.remove()

        XCTAssertEqual(queries.count, 2)
        for query in queries {
            XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
            XCTAssertEqual(
                query[kSecAttrService as String] as? String,
                "com.fantomsuj.NotionPiP.personalIntegration"
            )
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "notion-token")
            XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        }
        XCTAssertEqual(
            queries[0][kSecUseDataProtectionKeychain as String] as? Bool,
            true
        )
        XCTAssertNil(queries[1][kSecUseDataProtectionKeychain as String])
    }

    func testRemovalTreatsMissingItemsAsSuccess() throws {
        let remover = LegacyPersonalTokenRemover { _ in errSecItemNotFound }

        XCTAssertNoThrow(try remover.remove())
    }

    func testRemovalAttemptsBothItemsAndReportsUnexpectedStatus() {
        var deletionCount = 0
        let remover = LegacyPersonalTokenRemover { _ in
            deletionCount += 1
            return deletionCount == 1 ? errSecInteractionNotAllowed : errSecSuccess
        }

        XCTAssertThrowsError(try remover.remove()) { error in
            XCTAssertEqual(
                error as? LegacyPersonalTokenRemovalError,
                .unexpectedStatus(errSecInteractionNotAllowed)
            )
        }
        XCTAssertEqual(deletionCount, 2)
    }
}
