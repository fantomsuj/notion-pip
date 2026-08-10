import Security
import XCTest
@testable import NotionPiP

@MainActor
final class PersonalTokenCredentialVaultTests: XCTestCase {
    func testKeychainStoreOptsPrimaryOperationsIntoDataProtection() throws {
        var copyQueries: [[String: Any]] = []
        var updateQueries: [[String: Any]] = []
        var deleteQueries: [[String: Any]] = []
        let client = KeychainClient(
            copyMatching: { query in
                copyQueries.append(query)
                return (errSecSuccess, Data("ntn_existing-token-1234".utf8))
            },
            update: { query, _ in
                updateQueries.append(query)
                return errSecSuccess
            },
            add: { _ in
                XCTFail("An existing protected item should be updated")
                return errSecSuccess
            },
            delete: { query in
                deleteQueries.append(query)
                return errSecItemNotFound
            }
        )
        let store = KeychainSecretStore(
            service: "test.service",
            account: "test-account",
            client: client
        )

        XCTAssertNotNil(try store.read())
        try store.write(Data("ntn_updated-token-5678".utf8))
        try store.delete()

        XCTAssertEqual(copyQueries.count, 1)
        XCTAssertEqual(
            copyQueries[0][kSecUseDataProtectionKeychain as String] as? Bool,
            true
        )
        XCTAssertEqual(updateQueries.count, 1)
        XCTAssertEqual(
            updateQueries[0][kSecUseDataProtectionKeychain as String] as? Bool,
            true
        )
        XCTAssertTrue(deleteQueries.contains { query in
            query[kSecUseDataProtectionKeychain as String] as? Bool == true
        })
    }

    func testReadingLegacyCredentialMigratesItIntoDataProtectionKeychain() throws {
        var copyQueries: [[String: Any]] = []
        var insertedQuery: [String: Any]?
        var deleteQueries: [[String: Any]] = []
        let legacyData = Data("ntn_legacy-token-1234".utf8)
        let client = KeychainClient(
            copyMatching: { query in
                copyQueries.append(query)
                if query[kSecUseDataProtectionKeychain as String] as? Bool == true {
                    return (errSecItemNotFound, nil)
                }
                return (errSecSuccess, legacyData)
            },
            update: { query, _ in
                XCTAssertEqual(
                    query[kSecUseDataProtectionKeychain as String] as? Bool,
                    true
                )
                return errSecItemNotFound
            },
            add: { query in
                insertedQuery = query
                return errSecSuccess
            },
            delete: { query in
                deleteQueries.append(query)
                return errSecSuccess
            }
        )
        let store = KeychainSecretStore(
            service: "test.service",
            account: "test-account",
            client: client
        )

        XCTAssertEqual(try store.read(), legacyData)

        XCTAssertEqual(copyQueries.count, 2)
        XCTAssertEqual(
            copyQueries.first?[kSecUseDataProtectionKeychain as String] as? Bool,
            true
        )
        XCTAssertNil(copyQueries.last?[kSecUseDataProtectionKeychain as String])
        XCTAssertEqual(
            insertedQuery?[kSecUseDataProtectionKeychain as String] as? Bool,
            true
        )
        XCTAssertEqual(
            insertedQuery?[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        XCTAssertEqual(deleteQueries.count, 1)
        XCTAssertNil(deleteQueries[0][kSecUseDataProtectionKeychain as String])
    }

    func testReadingFallsBackToLegacyKeychainWhenDataProtectionIsUnavailable() throws {
        var copyQueries: [[String: Any]] = []
        var updateQueries: [[String: Any]] = []
        let legacyData = Data("ntn_legacy-token-1234".utf8)
        let client = KeychainClient(
            copyMatching: { query in
                copyQueries.append(query)
                if query[kSecUseDataProtectionKeychain as String] as? Bool == true {
                    return (errSecMissingEntitlement, nil)
                }
                return (errSecSuccess, legacyData)
            },
            update: { query, _ in
                updateQueries.append(query)
                return errSecMissingEntitlement
            },
            add: { _ in
                XCTFail("An unavailable data-protection keychain should not be written")
                return errSecSuccess
            },
            delete: { _ in
                XCTFail("The legacy item must remain when migration is unavailable")
                return errSecSuccess
            }
        )
        let store = KeychainSecretStore(
            service: "test.service",
            account: "test-account",
            client: client
        )

        XCTAssertEqual(try store.read(), legacyData)

        XCTAssertEqual(copyQueries.count, 2)
        XCTAssertEqual(
            copyQueries.first?[kSecUseDataProtectionKeychain as String] as? Bool,
            true
        )
        XCTAssertNil(copyQueries.last?[kSecUseDataProtectionKeychain as String])
        XCTAssertTrue(updateQueries.isEmpty)
    }

    func testWritingFallsBackToLegacyKeychainWhenDataProtectionIsUnavailable() throws {
        var updateQueries: [[String: Any]] = []
        var updatedLegacyData: Data?
        let tokenData = Data("ntn_updated-token-5678".utf8)
        let client = KeychainClient(
            copyMatching: { _ in
                XCTFail("Writing should not perform a read")
                return (errSecItemNotFound, nil)
            },
            update: { query, attributes in
                updateQueries.append(query)
                if query[kSecUseDataProtectionKeychain as String] as? Bool == true {
                    return errSecMissingEntitlement
                }
                updatedLegacyData = attributes[kSecValueData as String] as? Data
                return errSecSuccess
            },
            add: { _ in
                XCTFail("The existing legacy item should be updated")
                return errSecSuccess
            },
            delete: { _ in
                XCTFail("Saving to the legacy keychain should not delete the item")
                return errSecSuccess
            }
        )
        let store = KeychainSecretStore(
            service: "test.service",
            account: "test-account",
            client: client
        )

        try store.write(tokenData)

        XCTAssertEqual(updateQueries.count, 2)
        XCTAssertEqual(
            updateQueries.first?[kSecUseDataProtectionKeychain as String] as? Bool,
            true
        )
        XCTAssertNil(updateQueries.last?[kSecUseDataProtectionKeychain as String])
        XCTAssertEqual(updatedLegacyData, tokenData)
    }

    func testSavingTokenReplacesExistingCredential() throws {
        let secureStore = InMemorySecretStore()
        let vault = PersonalTokenCredentialVault(store: secureStore)
        try vault.save(PersonalIntegrationToken(validating: "ntn_first-token-1234"))
        try vault.save(PersonalIntegrationToken(validating: "ntn_second-token-5678"))

        XCTAssertEqual(try vault.load()?.redactedDescription, "ntn_…5678")
        XCTAssertEqual(secureStore.saveCount, 2)
    }

    func testDisconnectDeletesToken() throws {
        let secureStore = InMemorySecretStore()
        let vault = PersonalTokenCredentialVault(store: secureStore)
        try vault.save(PersonalIntegrationToken(validating: "ntn_personal-token-1234"))

        try vault.disconnect()

        XCTAssertNil(try vault.load())
    }
}

private final class InMemorySecretStore: SecretStoring {
    var data: Data?
    private(set) var saveCount = 0

    func read() throws -> Data? { data }

    func write(_ data: Data) throws {
        self.data = data
        saveCount += 1
    }

    func delete() throws {
        data = nil
    }
}
