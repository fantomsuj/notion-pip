import Foundation
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

/// Runs the legacy token deletion once per install. The deletes never read the
/// item; after one clean pass a flag skips the keychain on every later launch.
struct LegacyPersonalTokenCleanup {
    static let completedKey = "legacyPersonalTokenCleanupCompleted"

    private let defaults: UserDefaults
    private let remover: LegacyPersonalTokenRemover

    init(
        defaults: UserDefaults = .standard,
        remover: LegacyPersonalTokenRemover = LegacyPersonalTokenRemover()
    ) {
        self.defaults = defaults
        self.remover = remover
    }

    /// Deletes the legacy items unless an earlier launch already did.
    /// A failed pass leaves the flag unset so the next launch tries again.
    /// - Returns: Whether the keychain was touched.
    @discardableResult
    func runIfNeeded() throws -> Bool {
        guard !defaults.bool(forKey: Self.completedKey) else { return false }
        try remover.remove()
        defaults.set(true, forKey: Self.completedKey)
        return true
    }
}
