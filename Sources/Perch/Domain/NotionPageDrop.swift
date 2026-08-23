import Foundation

protocol NotionPageDropTitleProviding: Sendable {
    func displayTitle(for pageID: String) async -> String?
}

struct NotionPageDrop: Equatable, Sendable {
    let page: NotionPageReference
    let sourceLabel: String?

    init(validating url: URL, sourceLabel: String?) throws {
        page = try NotionPageReference(validating: url)
        self.sourceLabel = Self.normalizedLabel(sourceLabel)
    }

    func displayLabel(localTitle: String?) -> String {
        Self.normalizedLabel(localTitle)
            ?? sourceLabel
            ?? Self.normalizedLabel(page.displayTitle)
            ?? "Notion page"
    }

    private static func normalizedLabel(_ rawLabel: String?) -> String? {
        guard let rawLabel else { return nil }

        let scalars = rawLabel.unicodeScalars.map { scalar -> Unicode.Scalar in
            isSeparator(scalar) ? " " : scalar
        }
        let normalized = String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(80))
    }

    private static func isSeparator(_ scalar: Unicode.Scalar) -> Bool {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return true
        }
        switch scalar.properties.generalCategory {
        case .control:
            return true
        default:
            break
        }
        switch scalar.value {
        case 0x061C, 0x200E ... 0x200F, 0x202A ... 0x202E, 0x2066 ... 0x2069:
            return true
        default:
            return false
        }
    }
}
