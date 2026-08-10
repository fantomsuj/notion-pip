import Security

enum LegacyPersonalTokenRemovalError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

struct LegacyPersonalTokenRemover {
    private static let service = "com.fantomsuj.Perch.personalIntegration"
    private static let account = "notion-token"

    private let deleteItem: ([String: Any]) -> OSStatus

    init(
        _ deleteItem: @escaping ([String: Any]) -> OSStatus = { query in
            SecItemDelete(query as CFDictionary)
        }
    ) {
        self.deleteItem = deleteItem
    }

    func remove() throws {
        let statuses = [
            deleteItem(dataProtectionQuery),
            deleteItem(legacyQuery),
        ]
        if let unexpectedStatus = statuses.first(where: {
            $0 != errSecSuccess && $0 != errSecItemNotFound
        }) {
            throw LegacyPersonalTokenRemovalError.unexpectedStatus(unexpectedStatus)
        }
    }

    private var legacyQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    private var dataProtectionQuery: [String: Any] {
        var query = legacyQuery
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }
}
