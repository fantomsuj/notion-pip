import Foundation

enum PinnedPageRole {
    static let maximumLength = 32
    private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

    static func normalized(
        _ rawValue: String?,
        for pageID: String,
        among pinnedPages: [StoredPageSnapshot]
    ) throws -> String? {
        guard let rawValue else { return nil }
        let collapsed = rawValue
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else {
            throw PageRepositoryError.blankRole
        }

        let normalized = String(collapsed.prefix(maximumLength))
        let key = comparisonKey(normalized)
        guard !pinnedPages.contains(where: {
            $0.pageID.caseInsensitiveCompare(pageID) != .orderedSame
                && $0.role.map(comparisonKey) == key
        }) else {
            throw PageRepositoryError.duplicateRole
        }
        return normalized
    }

    static func comparisonKey(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: comparisonLocale
            )
            .lowercased(with: comparisonLocale)
    }
}
