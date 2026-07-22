import Foundation
import Security

protocol SecretStoring: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete() throws
}

enum KeychainSecretStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

final class KeychainSecretStore: SecretStoring {
    private let service: String
    private let account: String

    init(
        service: String = "com.fantomsuj.NotionPiP.personalIntegration",
        account: String = "notion-token"
    ) {
        self.service = service
        self.account = account
    }

    func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSecretStoreError.unexpectedStatus(status)
        }
        return result as? Data
    }

    func write(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainSecretStoreError.unexpectedStatus(updateStatus)
        }

        var insertQuery = baseQuery
        attributes.forEach { insertQuery[$0.key] = $0.value }
        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw KeychainSecretStoreError.unexpectedStatus(insertStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}

final class PersonalTokenCredentialVault {
    private let store: any SecretStoring

    init(store: any SecretStoring = KeychainSecretStore()) {
        self.store = store
    }

    func save(_ token: PersonalIntegrationToken) throws {
        try store.write(Data(token.value.utf8))
    }

    func load() throws -> PersonalIntegrationToken? {
        guard let data = try store.read(), let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return try PersonalIntegrationToken(validating: value)
    }

    func disconnect() throws {
        try store.delete()
    }
}
