import Foundation

public enum CustomPinnedURLError: Error, Equatable, Sendable {
    case invalidURL
    case inputTooLong
    case unsupportedScheme
    case credentialsNotAllowed
    case missingHost
    case notionPageURL
}

/// A user-saved HTTPS destination that is not a Notion page.
///
/// Custom pins are a beta overlay on top of the Notion working set. They keep a
/// stable canonical URL, never include credentials, and reject URLs that already
/// validate as Notion pages so those continue through the existing pin flow.
public struct CustomPinnedURL: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let canonicalURL: URL
    public let displayTitle: String
    public let pinnedAt: Date

    public var id: String { canonicalURL.absoluteString }

    public var host: String {
        canonicalURL.host ?? canonicalURL.absoluteString
    }

    private static let maximumURLLength = 4_096

    public init(validatingString string: String, pinnedAt: Date = Date()) throws {
        guard let url = Self.normalizedInputURL(from: string) else {
            throw CustomPinnedURLError.invalidURL
        }
        try self.init(validating: url, pinnedAt: pinnedAt)
    }

    public init(validating url: URL, displayTitle: String? = nil, pinnedAt: Date = Date()) throws {
        guard url.absoluteString.utf8.count <= Self.maximumURLLength else {
            throw CustomPinnedURLError.inputTooLong
        }
        guard url.scheme?.lowercased() == "https" else {
            throw CustomPinnedURLError.unsupportedScheme
        }
        guard url.user == nil, url.password == nil else {
            throw CustomPinnedURLError.credentialsNotAllowed
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            throw CustomPinnedURLError.missingHost
        }
        if (try? NotionPageReference(validating: url)) != nil {
            throw CustomPinnedURLError.notionPageURL
        }

        guard let inputComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw CustomPinnedURLError.missingHost
        }

        var canonicalComponents = URLComponents()
        canonicalComponents.scheme = "https"
        canonicalComponents.host = host
        canonicalComponents.port = inputComponents.port
        canonicalComponents.percentEncodedPath = inputComponents.percentEncodedPath.isEmpty
            ? "/"
            : inputComponents.percentEncodedPath
        canonicalComponents.percentEncodedQuery = inputComponents.percentEncodedQuery

        guard let canonicalURL = canonicalComponents.url else {
            throw CustomPinnedURLError.missingHost
        }

        self.canonicalURL = canonicalURL
        self.displayTitle = Self.normalizedTitle(displayTitle) ?? host
        self.pinnedAt = pinnedAt
    }

    func resolvingDisplayTitle(_ rawTitle: String?) -> Self {
        guard let title = Self.normalizedTitle(rawTitle), title != displayTitle else {
            return self
        }
        return CustomPinnedURL(
            canonicalURL: canonicalURL,
            displayTitle: title,
            pinnedAt: pinnedAt
        )
    }

    private init(canonicalURL: URL, displayTitle: String, pinnedAt: Date) {
        self.canonicalURL = canonicalURL
        self.displayTitle = displayTitle
        self.pinnedAt = pinnedAt
    }

    private static func normalizedInputURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    private static func normalizedTitle(_ rawTitle: String?) -> String? {
        guard let title = rawTitle?
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " "),
            !title.isEmpty
        else {
            return nil
        }
        return title
    }
}

enum CustomPinnedURLPolicy {
    static let pinLimit = 7

    static func validationMessage(for error: CustomPinnedURLError) -> String {
        switch error {
        case .invalidURL:
            "Enter a valid HTTPS URL."
        case .inputTooLong:
            "That URL is too long."
        case .unsupportedScheme:
            "Use an HTTPS URL."
        case .credentialsNotAllowed:
            "Remove the username or password from the URL."
        case .missingHost:
            "Use an HTTPS URL with a host, such as https://canvas.example.edu."
        case .notionPageURL:
            "Use Current Page for Notion URLs."
        }
    }
}
