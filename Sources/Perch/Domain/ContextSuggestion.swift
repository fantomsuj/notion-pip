import Foundation

struct ContextSourceIdentity: Equatable, Sendable {
    let processIdentifier: pid_t?
    let bundleIdentifier: String
    let applicationName: String
}

struct ContextSnapshot: Equatable, Sendable {
    let source: ContextSourceIdentity
    let windowTitle: String?
    let documentURL: URL?
    let exactPage: NotionPageReference?

    var bundleIdentifier: String { source.bundleIdentifier }
    var applicationName: String { source.applicationName }

    init(
        bundleIdentifier: String,
        applicationName: String,
        windowTitle: String?,
        documentURL: URL?,
        sourceProcessIdentifier: pid_t? = nil,
        exactPage: NotionPageReference? = nil
    ) {
        source = ContextSourceIdentity(
            processIdentifier: sourceProcessIdentifier,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName
        )
        self.windowTitle = windowTitle
        self.documentURL = documentURL
        self.exactPage = exactPage
    }

    init(
        source: ContextSourceIdentity,
        windowTitle: String? = nil,
        documentURL: URL? = nil,
        exactPage: NotionPageReference? = nil
    ) {
        self.source = source
        self.windowTitle = windowTitle
        self.documentURL = documentURL
        self.exactPage = exactPage
    }

    var identity: String {
        [
            bundleIdentifier,
            windowTitle ?? "",
            documentURL?.absoluteString ?? "",
            exactPage?.pageID ?? "",
        ].joined(separator: "\u{1F}")
    }
}

enum ContextualNotionPageResolver {
    private static let notionDesktopBundleIdentifier = "notion.id"
    private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.safari",
        "com.apple.safaritechnologypreview",
        "com.brave.browser",
        "com.google.chrome",
        "com.google.chrome.beta",
        "com.google.chrome.canary",
        "com.microsoft.edgemac",
        "company.thebrowser.browser",
        "org.mozilla.firefox",
    ]

    static func resolve(
        rawURL: String,
        sourceBundleIdentifier: String
    ) -> NotionPageReference? {
        let source = sourceBundleIdentifier.lowercased()
        guard source == notionDesktopBundleIdentifier
                || browserBundleIdentifiers.contains(source)
        else {
            return nil
        }
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }

        if url.scheme?.lowercased() == "notion" {
            guard source == notionDesktopBundleIdentifier,
                  url.host?.lowercased() == "www.notion.so",
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else {
                return nil
            }
            components.scheme = "https"
            guard let normalizedURL = components.url else { return nil }
            return try? NotionPageReference(validating: normalizedURL)
        }

        return try? NotionPageReference(validating: url)
    }
}

enum AccessibilityExactPageContextResolver {
    static func snapshot(
        source: ContextSourceIdentity,
        urlAttributeValues: [String]
    ) -> ContextSnapshot? {
        for rawURL in urlAttributeValues {
            if let page = ContextualNotionPageResolver.resolve(
                rawURL: rawURL,
                sourceBundleIdentifier: source.bundleIdentifier
            ) {
                return ContextSnapshot(source: source, exactPage: page)
            }
        }
        return nil
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

struct ContextualPageAction: Equatable, Sendable {
    let page: NotionPageReference
    let sourceApplicationName: String
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
