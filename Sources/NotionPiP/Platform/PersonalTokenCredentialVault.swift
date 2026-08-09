import Foundation
import OSLog
import Security

protocol SecretStoring: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete() throws
}

enum KeychainSecretStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

struct KeychainClient {
    let copyMatching: ([String: Any]) -> (OSStatus, Data?)
    let update: ([String: Any], [String: Any]) -> OSStatus
    let add: ([String: Any]) -> OSStatus
    let delete: ([String: Any]) -> OSStatus

    static var live: KeychainClient {
        KeychainClient(
            copyMatching: { query in
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                return (status, result as? Data)
            },
            update: { query, attributes in
                SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            },
            add: { query in
                SecItemAdd(query as CFDictionary, nil)
            },
            delete: { query in
                SecItemDelete(query as CFDictionary)
            }
        )
    }
}

final class KeychainSecretStore: SecretStoring {
    private let logger = Logger(
        subsystem: "com.fantomsuj.NotionPiP",
        category: "keychain"
    )
    private let service: String
    private let account: String
    private let client: KeychainClient

    init(
        service: String = "com.fantomsuj.NotionPiP.personalIntegration",
        account: String = "notion-token",
        client: KeychainClient = .live
    ) {
        self.service = service
        self.account = account
        self.client = client
    }

    func read() throws -> Data? {
        do {
            if let data = try read(matching: dataProtectionQuery) {
                return data
            }
        } catch let error as KeychainSecretStoreError where error.isMissingEntitlement {
            logLegacyFallback()
            return try read(matching: legacyQuery)
        }
        guard let legacyData = try read(matching: legacyQuery) else {
            return nil
        }

        try write(legacyData)
        return legacyData
    }

    private func read(matching baseQuery: [String: Any]) throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (status, data) = client.copyMatching(query)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSecretStoreError.unexpectedStatus(status)
        }
        return data
    }

    func write(_ data: Data) throws {
        do {
            try write(data, matching: dataProtectionQuery)
            try deleteLegacyItem()
        } catch let error as KeychainSecretStoreError where error.isMissingEntitlement {
            logLegacyFallback()
            try write(data, matching: legacyQuery)
        }
    }

    private func write(_ data: Data, matching query: [String: Any]) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = client.update(query, attributes)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainSecretStoreError.unexpectedStatus(updateStatus)
        }

        var insertQuery = query
        attributes.forEach { insertQuery[$0.key] = $0.value }
        let insertStatus = client.add(insertQuery)
        guard insertStatus == errSecSuccess else {
            throw KeychainSecretStoreError.unexpectedStatus(insertStatus)
        }
    }

    func delete() throws {
        let statuses = [
            client.delete(dataProtectionQuery),
            client.delete(legacyQuery),
        ]
        if let unexpectedStatus = statuses.first(where: {
            $0 != errSecSuccess && $0 != errSecItemNotFound
        }) {
            throw KeychainSecretStoreError.unexpectedStatus(unexpectedStatus)
        }
    }

    private func deleteLegacyItem() throws {
        let status = client.delete(legacyQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.unexpectedStatus(status)
        }
    }

    private var legacyQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    private var dataProtectionQuery: [String: Any] {
        var query = legacyQuery
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }

    private func logLegacyFallback() {
        logger.notice(
            "Data-protection Keychain unavailable; using legacy Keychain status=\(errSecMissingEntitlement, privacy: .public)"
        )
    }
}

private extension KeychainSecretStoreError {
    var isMissingEntitlement: Bool {
        self == .unexpectedStatus(errSecMissingEntitlement)
    }
}

@MainActor
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
