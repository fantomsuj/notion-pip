import XCTest
@testable import NotionPiP

@MainActor
final class PersonalTokenCredentialVaultTests: XCTestCase {
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
