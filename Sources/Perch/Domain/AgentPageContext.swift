import Foundation

/// The open page, read for pasting into a local coding agent.
struct AgentPageSnapshot: Equatable, Sendable {
    /// How much of the page the snapshot holds.
    enum Coverage: String, Equatable, Sendable {
        /// Notion blocks the web view had rendered, converted to Markdown.
        case renderedBlocks = "rendered blocks only"
        /// The page's visible text, without Markdown structure.
        case visibleText = "visible text only"
        /// Title and URL only, because the page could not be read.
        case linkOnly = "link only"
    }

    let title: String
    let url: URL
    let body: String
    let coverage: Coverage
    let wasTruncatedByReader: Bool

    init(
        title: String,
        url: URL,
        body: String,
        coverage: Coverage,
        wasTruncatedByReader: Bool = false
    ) {
        self.title = title
        self.url = url
        self.body = body
        self.coverage = coverage
        self.wasTruncatedByReader = wasTruncatedByReader
    }

    /// A snapshot that carries only the page's identity.
    static func linkOnly(title: String, url: URL) -> Self {
        Self(title: title, url: url, body: "", coverage: .linkOnly)
    }

    /// Validates the value returned by `NotionPageReader.script`.
    ///
    /// - Parameters:
    ///   - javaScriptValue: The script's return value.
    ///   - url: The page URL Perch trusts; the script never supplies it.
    ///   - fallbackTitle: Used when the page does not expose a title.
    init?(javaScriptValue: Any?, url: URL, fallbackTitle: String) {
        guard let value = javaScriptValue as? [String: Any],
              (value["version"] as? NSNumber)?.intValue == 1,
              let body = value["body"] as? String,
              let coverageName = value["coverage"] as? String
        else {
            return nil
        }

        let coverage: Coverage
        switch coverageName {
        case "blocks":
            coverage = .renderedBlocks
        case "text":
            coverage = .visibleText
        default:
            return nil
        }

        let readTitle = Self.singleLine(value["title"] as? String ?? "")
        self.init(
            title: readTitle.isEmpty ? Self.singleLine(fallbackTitle) : readTitle,
            url: url,
            body: body,
            coverage: coverage,
            wasTruncatedByReader: (value["truncated"] as? NSNumber)?.boolValue ?? false
        )
    }

    var wordCount: Int {
        body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Builds the Markdown that Copy for Agent puts on the clipboard.
enum AgentPageContextFormatter {
    /// Matches the total cap on streamed agent Markdown.
    static let maximumUTF8Bytes = 512 * 1_024
    static let truncationMarker = "\n\n[Truncated by Perch]"

    static func markdown(for snapshot: AgentPageSnapshot, copiedAt: Date) -> String {
        let title = snapshot.title.isEmpty ? "Untitled" : snapshot.title
        let header = frontMatter(
            for: snapshot,
            title: title,
            copiedAt: copiedAt,
            truncated: snapshot.wasTruncatedByReader
        )
        let heading = "# \(title)"
        let document = snapshot.body.isEmpty
            ? "\(header)\n\(heading)\n"
            : "\(header)\n\(heading)\n\n\(snapshot.body)\n"
        guard document.utf8.count > maximumUTF8Bytes else {
            return document
        }

        let truncatedHeader = frontMatter(
            for: snapshot,
            title: title,
            copiedAt: copiedAt,
            truncated: true
        )
        let prefix = "\(truncatedHeader)\n\(heading)\n\n"
        let budget = maximumUTF8Bytes
            - prefix.utf8.count
            - truncationMarker.utf8.count
            - 1
        return prefix + prefixFitting(snapshot.body, utf8Budget: budget) + truncationMarker + "\n"
    }

    private static func frontMatter(
        for snapshot: AgentPageSnapshot,
        title: String,
        copiedAt: Date,
        truncated: Bool
    ) -> String {
        var lines = [
            "---",
            "source: Perch",
            "title: \(yamlQuoted(title))",
            "url: \(yamlQuoted(snapshot.url.absoluteString))",
            "copied: \(copiedAt.formatted(.iso8601))",
            "coverage: \(snapshot.coverage.rawValue)",
        ]
        if truncated {
            lines.append("truncated: true")
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func prefixFitting(_ text: String, utf8Budget: Int) -> String {
        guard utf8Budget > 0 else { return "" }
        var used = 0
        var end = text.startIndex
        for index in text.indices {
            let size = text[index].utf8.count
            guard used + size <= utf8Budget else { break }
            used += size
            end = text.index(after: index)
        }
        return String(text[..<end])
    }
}
