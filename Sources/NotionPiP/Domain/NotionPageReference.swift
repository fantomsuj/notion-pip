import Foundation

public enum NotionPageReferenceError: Error, Equatable, Sendable {
    case inputTooLong
    case unsupportedScheme
    case unsupportedHost
    case credentialsNotAllowed
    case missingPageID
}

public struct NotionPageReference: Equatable, Hashable, Sendable {
    public let pageID: String
    public let canonicalURL: URL
    public let displayTitle: String?

    private static let maximumURLLength = 4_096
    private static let supportedHosts = ["app.notion.com", "notion.so", "www.notion.so"]

    public init(validating url: URL) throws {
        guard url.absoluteString.utf8.count <= Self.maximumURLLength else {
            throw NotionPageReferenceError.inputTooLong
        }
        guard url.scheme?.lowercased() == "https" else {
            throw NotionPageReferenceError.unsupportedScheme
        }
        guard url.user == nil, url.password == nil else {
            throw NotionPageReferenceError.credentialsNotAllowed
        }
        guard let host = url.host?.lowercased(), Self.supportedHosts.contains(host) else {
            throw NotionPageReferenceError.unsupportedHost
        }

        let component = url.lastPathComponent
        let extraction = try Self.extractPageID(from: component)

        var canonicalComponents = URLComponents()
        canonicalComponents.scheme = "https"
        canonicalComponents.host = host == "app.notion.com" ? host : "www.notion.so"
        canonicalComponents.path = host == "app.notion.com"
            ? url.path
            : "/\(component)"

        guard let canonicalURL = canonicalComponents.url else {
            throw NotionPageReferenceError.missingPageID
        }

        pageID = extraction.pageID
        self.canonicalURL = canonicalURL
        displayTitle = Self.displayTitle(from: extraction.titlePrefix)
    }

    private static func extractPageID(from component: String) throws -> (pageID: String, titlePrefix: String) {
        guard !component.isEmpty else {
            throw NotionPageReferenceError.missingPageID
        }

        var cursor = component.endIndex
        var identifierCharacters: [Character] = []

        while cursor > component.startIndex, identifierCharacters.count < 32 {
            let precedingIndex = component.index(before: cursor)
            let character = component[precedingIndex]
            cursor = precedingIndex

            if character == "-" {
                continue
            }
            guard character.isASCIIHexDigit else {
                throw NotionPageReferenceError.missingPageID
            }
            identifierCharacters.append(character)
        }

        guard identifierCharacters.count == 32 else {
            throw NotionPageReferenceError.missingPageID
        }

        let pageID = String(identifierCharacters.reversed()).lowercased()
        return (pageID, String(component[..<cursor]))
    }

    private static func displayTitle(from prefix: String) -> String? {
        let title = prefix
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return title.isEmpty ? nil : title
    }
}

private extension Character {
    var isASCIIHexDigit: Bool {
        unicodeScalars.count == 1 && unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48 ... 57, 65 ... 70, 97 ... 102:
                true
            default:
                false
            }
        }
    }
}
