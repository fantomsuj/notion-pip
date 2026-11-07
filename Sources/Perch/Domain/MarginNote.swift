import Foundation

/// Where a margin note was jotted: the app in front, and when the app shares
/// them, its window title and document (a page URL in Safari, a file in most
/// document apps).
struct MarginNoteSource: Codable, Equatable, Sendable {
    var applicationName: String
    var bundleIdentifier: String?
    var windowTitle: String?
    var documentURL: URL?

    /// One short line for the note card, such as `Safari · Rate limits`.
    var summary: String {
        guard let windowTitle = Self.trimmed(windowTitle),
              windowTitle != applicationName
        else {
            return applicationName
        }
        return "\(applicationName) · \(windowTitle)"
    }

    fileprivate static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A thought jotted from the pointer in any app, kept with its time and source.
struct MarginNote: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var text: String
    var createdAt: Date
    var source: MarginNoteSource?

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date,
        source: MarginNoteSource?
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.source = source
    }

    /// The trimmed note, or nil when there is nothing worth saving.
    static func normalizedText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// One Notion bullet: the note, then its source and time in italics.
    ///
    /// `- Ask about rate limits — _Safari · [Rate limits](https://…) · Nov 7, 11:42 AM_`
    ///
    /// Line breaks inside the note become spaces so the note stays one block.
    func markdown(formatTime: (Date) -> String = MarginNote.defaultTimeFormatter) -> String {
        let body = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        var details: [String] = []
        if let source {
            details.append(Self.escaped(source.applicationName))
            let title = MarginNoteSource.trimmed(source.windowTitle)
                .flatMap { $0 == source.applicationName ? nil : $0 }
            switch (title, Self.linkableURL(source.documentURL)) {
            case let (title?, url?):
                details.append("[\(Self.escaped(title))](\(url.absoluteString))")
            case let (title?, nil):
                details.append(Self.escaped(title))
            case let (nil, url?):
                details.append("<\(url.absoluteString)>")
            case (nil, nil):
                break
            }
        }
        details.append(formatTime(createdAt))

        return "- \(body) — _\(details.joined(separator: " · "))_"
    }

    static let defaultTimeFormatter: @Sendable (Date) -> String = { date in
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private static func linkableURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme)
        else {
            return nil
        }
        let text = url.absoluteString
        guard !text.contains(where: { $0.isWhitespace || $0 == ")" || $0 == ">" }) else {
            return nil
        }
        return url
    }

    /// Escapes the characters that would turn a title into Markdown syntax.
    private static func escaped(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            if "\\`*_[]<>#|".contains(character) {
                result.append("\\")
            }
            result.append(character == "\n" ? " " : character)
        }
        return result
    }
}
