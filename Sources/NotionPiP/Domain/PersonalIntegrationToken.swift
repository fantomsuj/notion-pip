import Foundation

enum PersonalIntegrationTokenError: Error, Equatable, Sendable {
    case missing
    case unsupportedFormat
}

struct PersonalIntegrationToken: Equatable, Sendable {
    let value: String

    init(validating rawValue: String) throws {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw PersonalIntegrationTokenError.missing
        }
        guard trimmedValue.hasPrefix("ntn_") else {
            throw PersonalIntegrationTokenError.unsupportedFormat
        }
        value = trimmedValue
    }

    var redactedDescription: String {
        guard value.count > 8 else {
            return "ntn_…"
        }
        return "ntn_…" + String(value.suffix(4))
    }
}
