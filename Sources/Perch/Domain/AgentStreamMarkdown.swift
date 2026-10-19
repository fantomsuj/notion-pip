import CoreGraphics
import Foundation

/// One block of the stream preview: a heading, list item, paragraph and so on.
struct AgentStreamMarkdownBlock: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case paragraph
        case heading(level: Int)
        /// `marker` is what the preview shows before the item, such as "•" or "2.".
        case listItem(marker: String, indentLevel: Int)
        case quote
        case code
        case divider
    }

    let kind: Kind
    /// Inline Markdown already parsed. Code blocks keep their text as is.
    let content: AttributedString
}

/// A small, line-based Markdown block parser for the agent stream preview.
///
/// SwiftUI `Text` ignores block structure, so the preview splits the text into blocks
/// here and parses only inline syntax inside each block. It covers what agents usually
/// send: ATX headings, bullet, numbered and task lists, quotes, fenced code, dividers and
/// paragraphs.
enum AgentStreamMarkdown {
    struct ParseResult: Equatable {
        var blocks: [AgentStreamMarkdownBlock]
        /// Leading blocks that more appended text can no longer change.
        var stableBlockCount: Int
        /// UTF-8 offset in the input where the first unstable block starts.
        var stableUTF8Offset: Int
    }

    static func parse(_ text: Substring) -> ParseResult {
        var parser = Parser()
        var offset = 0
        // "\r\n" is one Character in Swift, so it needs its own separator check.
        let lines = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "\n" || $0 == "\r\n" }
        )
        for (index, line) in lines.enumerated() {
            // The last line has no newline yet, so its type may still change.
            let isComplete = index < lines.count - 1
            parser.consume(line, startOffset: offset, isComplete: isComplete)
            offset += line.utf8.count
            if line.endIndex < text.endIndex {
                offset += text[line.endIndex].utf8.count
            }
        }
        return parser.finish()
    }

    static func blocks(from text: String) -> [AgentStreamMarkdownBlock] {
        parse(text[...]).blocks
    }

    static func inline(_ source: String) -> AttributedString {
        guard !source.isEmpty else { return AttributedString() }
        do {
            return try AttributedString(
                markdown: source,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(source)
        }
    }

    private enum PendingKind: Equatable {
        case paragraph
        case heading(level: Int)
        case listItem(marker: String, indentLevel: Int)
        case quote
        case code(fence: String)
        case divider

        var acceptsContinuation: Bool {
            switch self {
            case .paragraph, .listItem, .quote: true
            case .heading, .code, .divider: false
            }
        }
    }

    private struct Pending {
        var kind: PendingKind
        var lines: [Substring]
        let startOffset: Int
        let startsOnCompleteLine: Bool
        var isClosed = false
    }

    private struct Parser {
        private var pending: [Pending] = []

        mutating func consume(_ line: Substring, startOffset: Int, isComplete: Bool) {
            if var open = pending.last, case let .code(fence) = open.kind, !open.isClosed {
                if line.drop(while: { $0 == " " }).hasPrefix(fence),
                    leadingSpaces(line) < 4
                {
                    open.isClosed = true
                } else {
                    open.lines.append(line)
                }
                pending[pending.count - 1] = open
                return
            }

            let indent = leadingSpaces(line)
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.isEmpty {
                closeCurrent()
                return
            }

            func start(_ kind: PendingKind, _ content: Substring) -> Pending {
                Pending(
                    kind: kind,
                    lines: [content],
                    startOffset: startOffset,
                    startsOnCompleteLine: isComplete
                )
            }

            if indent < 4, let fence = fenceMarker(trimmed) {
                closeCurrent()
                pending.append(
                    Pending(
                        kind: .code(fence: fence),
                        lines: [],
                        startOffset: startOffset,
                        startsOnCompleteLine: isComplete
                    )
                )
                return
            }
            if indent < 4, case let (level, content)? = parseHeading(trimmed) {
                append(start(.heading(level: level), content))
                return
            }
            if indent < 4, isDivider(trimmed) {
                append(start(.divider, ""))
                return
            }
            if case let (marker, content)? = parseListItem(trimmed) {
                let level = min(indent / 2, 4)
                append(start(.listItem(marker: marker, indentLevel: level), content))
                return
            }
            if indent < 4, trimmed.first == ">" {
                var content = trimmed.dropFirst()
                if content.first == " " { content = content.dropFirst() }
                if let current = openIndex(), pending[current].kind == .quote {
                    pending[current].lines.append(content)
                } else {
                    append(start(.quote, content))
                }
                return
            }
            if let current = openIndex() {
                pending[current].lines.append(trimmed)
            } else {
                append(start(.paragraph, trimmed))
            }
        }

        private mutating func append(_ block: Pending) {
            closeCurrent()
            pending.append(block)
        }

        mutating func finish() -> ParseResult {
            let blocks = pending.map(Self.block(from:))
            // Blocks before the last one that began on a complete line are final:
            // later text either continues that block or starts a new one after it.
            guard let anchor = pending.lastIndex(where: \.startsOnCompleteLine) else {
                return ParseResult(blocks: blocks, stableBlockCount: 0, stableUTF8Offset: 0)
            }
            return ParseResult(
                blocks: blocks,
                stableBlockCount: anchor,
                stableUTF8Offset: pending[anchor].startOffset
            )
        }

        private mutating func closeCurrent() {
            if let current = openIndex() {
                pending[current].isClosed = true
            }
        }

        private func openIndex() -> Int? {
            guard let last = pending.indices.last,
                !pending[last].isClosed,
                pending[last].kind.acceptsContinuation
            else {
                return nil
            }
            return last
        }

        private static func block(from pending: Pending) -> AgentStreamMarkdownBlock {
            let source = pending.lines.joined(separator: "\n")
            switch pending.kind {
            case .paragraph:
                return AgentStreamMarkdownBlock(
                    kind: .paragraph,
                    content: AgentStreamMarkdown.inline(source)
                )
            case let .heading(level):
                return AgentStreamMarkdownBlock(
                    kind: .heading(level: level),
                    content: AgentStreamMarkdown.inline(source)
                )
            case let .listItem(marker, indentLevel):
                return AgentStreamMarkdownBlock(
                    kind: .listItem(marker: marker, indentLevel: indentLevel),
                    content: AgentStreamMarkdown.inline(source)
                )
            case .quote:
                return AgentStreamMarkdownBlock(
                    kind: .quote,
                    content: AgentStreamMarkdown.inline(source)
                )
            case .code:
                return AgentStreamMarkdownBlock(kind: .code, content: AttributedString(source))
            case .divider:
                return AgentStreamMarkdownBlock(kind: .divider, content: AttributedString())
            }
        }

        private func leadingSpaces(_ line: Substring) -> Int {
            var count = 0
            for character in line {
                if character == " " {
                    count += 1
                } else if character == "\t" {
                    count += 4
                } else {
                    break
                }
            }
            return count
        }

        private func fenceMarker(_ trimmed: Substring) -> String? {
            for fence in ["```", "~~~"] where trimmed.hasPrefix(fence) {
                return fence
            }
            return nil
        }

        private func parseHeading(_ trimmed: Substring) -> (Int, Substring)? {
            let hashes = trimmed.prefix(while: { $0 == "#" })
            guard (1...6).contains(hashes.count) else { return nil }
            let rest = trimmed.dropFirst(hashes.count)
            guard rest.isEmpty || rest.first == " " else { return nil }
            var content = rest.drop(while: { $0 == " " })
            // Drop an optional closing run of #s ("## Title ##").
            let withoutClosing = content.reversed().drop(while: { $0 == "#" })
            if withoutClosing.first == " " {
                content = content.dropLast(content.count - withoutClosing.count)
            }
            while content.last == " " { content = content.dropLast() }
            return (hashes.count, content)
        }

        private func isDivider(_ trimmed: Substring) -> Bool {
            let marks = trimmed.filter { $0 != " " }
            guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else {
                return false
            }
            return marks.allSatisfy { $0 == first }
        }

        private func parseListItem(_ trimmed: Substring) -> (String, Substring)? {
            if let first = trimmed.first, "-*+".contains(first) {
                let rest = trimmed.dropFirst()
                guard rest.first == " " else { return nil }
                let content = rest.drop(while: { $0 == " " })
                if content.hasPrefix("[ ] ") {
                    return ("☐", content.dropFirst(4))
                }
                if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
                    return ("☑", content.dropFirst(4))
                }
                return ("•", content)
            }
            let digits = trimmed.prefix(while: \.isASCIIDigit)
            guard (1...9).contains(digits.count) else { return nil }
            let rest = trimmed.dropFirst(digits.count)
            guard let delimiter = rest.first, delimiter == "." || delimiter == ")",
                rest.dropFirst().first == " "
            else {
                return nil
            }
            return ("\(digits)\(delimiter)", rest.dropFirst(2).drop(while: { $0 == " " }))
        }
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}

/// Caches parsed blocks across renders of a growing stream.
///
/// Stream text only grows while receiving, so blocks that can no longer change are kept
/// and only the tail after them is parsed again. Any other change starts over.
@MainActor
final class AgentStreamMarkdownRenderer {
    private var lastText = ""
    private var lastContentType: AgentStreamContentType?
    private var lastBlocks: [AgentStreamMarkdownBlock] = []
    private var stableBlocks: [AgentStreamMarkdownBlock] = []
    private var stableSource = ""
    private var stableUTF8Count = 0
    /// How many blocks the last call parsed again; for tests.
    private(set) var lastParsedBlockCount = 0

    func blocks(
        for text: String,
        contentType: AgentStreamContentType
    ) -> [AgentStreamMarkdownBlock] {
        if text == lastText, contentType == lastContentType {
            lastParsedBlockCount = 0
            return lastBlocks
        }
        defer {
            lastText = text
            lastContentType = contentType
        }

        guard contentType == .markdown else {
            reset()
            lastParsedBlockCount = text.isEmpty ? 0 : 1
            lastBlocks = text.isEmpty
                ? []
                : [AgentStreamMarkdownBlock(kind: .paragraph, content: AttributedString(text))]
            return lastBlocks
        }

        if contentType != lastContentType
            || text.utf8.count < stableUTF8Count
            || !text.utf8.starts(with: stableSource.utf8.prefix(stableUTF8Count))
        {
            reset()
        }

        let tailStart = text.utf8.index(text.utf8.startIndex, offsetBy: stableUTF8Count)
        let tail = text[tailStart...]
        let result = AgentStreamMarkdown.parse(tail)
        lastParsedBlockCount = result.blocks.count
        let unstable = result.blocks.dropFirst(result.stableBlockCount)
        stableBlocks.append(contentsOf: result.blocks.prefix(result.stableBlockCount))
        if result.stableBlockCount > 0 {
            stableSource = text
            stableUTF8Count += result.stableUTF8Offset
        }
        lastBlocks = stableBlocks + unstable
        return lastBlocks
    }

    private func reset() {
        stableBlocks = []
        stableSource = ""
        stableUTF8Count = 0
    }
}

/// Keeps the preview pinned to the newest text unless the user scrolls away from it.
struct AgentStreamAutoScroll: Equatable {
    /// How close to the bottom still counts as "at the bottom", in points.
    static let bottomTolerance: CGFloat = 24

    private(set) var isFollowing = true
    private var lastContentMinY: CGFloat?
    private var lastContentHeight: CGFloat?

    /// Records new geometry and returns true when the preview should jump to the bottom.
    ///
    /// Only scrolling (the content's top moving) changes whether we follow. Growth alone
    /// keeps the current choice, so new text never reads as the user scrolling up.
    mutating func update(
        contentMinY: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> Bool {
        defer {
            lastContentMinY = contentMinY
            lastContentHeight = contentHeight
        }
        if let lastContentMinY, abs(lastContentMinY - contentMinY) > 0.5 {
            let distanceFromBottom = contentMinY + contentHeight - viewportHeight
            isFollowing = distanceFromBottom <= Self.bottomTolerance
        }
        guard let lastContentHeight else { return false }
        return isFollowing && contentHeight > lastContentHeight + 0.5
    }
}
