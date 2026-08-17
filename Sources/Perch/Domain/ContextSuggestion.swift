import Foundation

struct ContextSnapshot: Equatable, Sendable {
    let bundleIdentifier: String
    let applicationName: String
    let windowTitle: String?
    let documentURL: URL?

    var identity: String {
        [
            bundleIdentifier,
            windowTitle ?? "",
            documentURL?.absoluteString ?? "",
        ].joined(separator: "\u{1F}")
    }
}

struct ContextSuggestion: Equatable, Sendable {
    let page: NotionPageReference
    let label: String
    let sourceApplicationName: String
    let sourceDescription: String?
    let contextIdentity: String
    let restoration: DurablePageRestoration?

    var suppressionKey: String {
        contextIdentity + "\u{1E}" + page.pageID.lowercased()
    }
}

enum ContextSuggestionMatcher {
    private static let minimumScore = 150
    private static let stopWords: Set<String> = [
        "and", "app", "application", "browser", "com", "for", "from",
        "http", "https", "net", "org", "page", "the", "with", "www",
    ]

    static func bestSuggestion(
        in snapshot: PageWorkingSetSnapshot,
        context: ContextSnapshot,
        activePageID: String?
    ) -> ContextSuggestion? {
        let contextTokens = tokens(
            in: [
                context.bundleIdentifier,
                context.applicationName,
                context.windowTitle ?? "",
                context.documentURL?.host ?? "",
                context.documentURL?.path ?? "",
            ].joined(separator: " ")
        )
        guard !contextTokens.isEmpty else { return nil }

        var seen: Set<String> = []
        let candidates = (
            snapshot.pinnedPages.map { ($0, true) }
                + snapshot.recentPages.map { ($0, false) }
        ).filter { page, _ in
            seen.insert(page.pageID.lowercased()).inserted
                && page.pageID.caseInsensitiveCompare(activePageID ?? "") != .orderedSame
        }

        let ranked = candidates.compactMap { page, isPinned -> RankedCandidate? in
            guard let validatedReference = try? NotionPageReference(validating: page.canonicalURL) else {
                return nil
            }
            let reference = validatedReference.resolvingDisplayTitle(page.displayTitle)

            let roleTokens = tokens(in: page.role ?? "")
            let titleTokens = tokens(in: page.displayTitle ?? "")
            let roleOverlap = roleTokens.intersection(contextTokens).count
            let titleOverlap = titleTokens.intersection(contextTokens).count
            guard roleOverlap > 0 || titleOverlap > 0 else { return nil }

            var score = roleOverlap * 300 + titleOverlap * 150
            if !roleTokens.isEmpty, roleTokens.isSubset(of: contextTokens) {
                score += 200
            }
            if !titleTokens.isEmpty, titleTokens.isSubset(of: contextTokens) {
                score += 80
            }
            if isPinned { score += 20 }
            guard score >= minimumScore else { return nil }

            let label = page.role ?? page.displayTitle ?? "Notion page"
            return RankedCandidate(
                suggestion: ContextSuggestion(
                    page: reference,
                    label: label,
                    sourceApplicationName: context.applicationName,
                    sourceDescription: sourceDescription(for: context),
                    contextIdentity: context.identity,
                    restoration: snapshot.restoration(for: page.pageID)
                ),
                score: score,
                isPinned: isPinned,
                timestamp: page.timestamp,
                pageID: page.pageID.lowercased()
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
            return lhs.pageID < rhs.pageID
        }

        return ranked.first?.suggestion
    }

    private struct RankedCandidate {
        let suggestion: ContextSuggestion
        let score: Int
        let isPinned: Bool
        let timestamp: Date
        let pageID: String
    }

    private static func tokens(in value: String) -> Set<String> {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return Set(
            folded
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 3 && !stopWords.contains($0) }
        )
    }

    private static func sourceDescription(for context: ContextSnapshot) -> String? {
        if let host = context.documentURL?.host, !host.isEmpty {
            return host
        }
        guard let title = context.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }
        return String(title.prefix(80))
    }
}
