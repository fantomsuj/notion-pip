import Security
import XCTest
@testable import Perch

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
                "com.fantomsuj.Perch.personalIntegration"
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

    func testCleanupDeletesOnceThenSkipsTheKeychainOnLaterLaunches() throws {
        let defaults = try makeCleanupDefaults()
        var queries: [[String: Any]] = []
        let remover = LegacyPersonalTokenRemover { query in
            queries.append(query)
            return errSecItemNotFound
        }

        XCTAssertTrue(try LegacyPersonalTokenCleanup(defaults: defaults, remover: remover).runIfNeeded())
        XCTAssertEqual(queries.count, 2)

        XCTAssertFalse(try LegacyPersonalTokenCleanup(defaults: defaults, remover: remover).runIfNeeded())
        XCTAssertEqual(queries.count, 2)
    }

    func testCleanupNeverAsksTheKeychainToReturnTheToken() throws {
        let defaults = try makeCleanupDefaults()
        var queries: [[String: Any]] = []
        let remover = LegacyPersonalTokenRemover { query in
            queries.append(query)
            return errSecSuccess
        }

        try LegacyPersonalTokenCleanup(defaults: defaults, remover: remover).runIfNeeded()

        XCTAssertEqual(queries.count, 2)
        for query in queries {
            XCTAssertNil(query[kSecReturnData as String])
            XCTAssertNil(query[kSecReturnAttributes as String])
            XCTAssertNil(query[kSecReturnRef as String])
        }
    }

    func testFailedCleanupRetriesOnTheNextLaunch() throws {
        let defaults = try makeCleanupDefaults()
        var deletionCount = 0
        var failing = true
        let remover = LegacyPersonalTokenRemover { _ in
            deletionCount += 1
            return failing ? errSecInteractionNotAllowed : errSecSuccess
        }

        XCTAssertThrowsError(
            try LegacyPersonalTokenCleanup(defaults: defaults, remover: remover).runIfNeeded()
        )
        failing = false

        XCTAssertTrue(try LegacyPersonalTokenCleanup(defaults: defaults, remover: remover).runIfNeeded())
        XCTAssertEqual(deletionCount, 4)
        XCTAssertFalse(try LegacyPersonalTokenCleanup(defaults: defaults, remover: remover).runIfNeeded())
        XCTAssertEqual(deletionCount, 4)
    }

    private func makeCleanupDefaults() throws -> UserDefaults {
        let suiteName = "LegacyPersonalTokenCleanupTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
