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

enum ContextualApplicationKind {
    static let notionDesktopBundleIdentifier = "notion.id"
    static let browserBundleIdentifiers: Set<String> = [
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

    static func ignoresApplicationName(bundleIdentifier: String) -> Bool {
        let source = bundleIdentifier.lowercased()
        return source == notionDesktopBundleIdentifier
            || browserBundleIdentifiers.contains(source)
    }

    static func isTrustedPageSource(bundleIdentifier: String) -> Bool {
        ignoresApplicationName(bundleIdentifier: bundleIdentifier)
    }
}

enum ContextualNotionPageResolver {
    static func resolve(
        rawURL: String,
        sourceBundleIdentifier: String
    ) -> NotionPageReference? {
        let source = sourceBundleIdentifier.lowercased()
        guard ContextualApplicationKind.isTrustedPageSource(bundleIdentifier: source)
        else {
            return nil
        }
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }

        if url.scheme?.lowercased() == "notion" {
            guard source == ContextualApplicationKind.notionDesktopBundleIdentifier,
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
        "http", "https", "net", "new", "org", "page", "tab", "the", "this",
        "that", "untitled", "window", "with", "www",
    ]
    private static let pathNoise: Set<String> = [
        "applications", "bin", "contents", "desktop", "documents", "downloads",
        "file", "files", "folder", "folders", "home", "library", "private",
        "projects", "resources", "source", "sources", "src", "test", "tests",
        "tmp", "user", "users", "usr", "var", "volumes",
    ]
    private static let browserTitleNames = [
        "Google Chrome Canary",
        "Google Chrome Beta",
        "Google Chrome",
        "Safari Technology Preview",
        "Microsoft Edge",
        "Mozilla Firefox",
        "Chrome",
        "Safari",
        "Firefox",
        "Brave",
        "Arc",
        "Notion",
    ]

    static func bestSuggestion(
        in snapshot: PageWorkingSetSnapshot,
        context: ContextSnapshot,
        activePageID: String?
    ) -> ContextSuggestion? {
        var seen: Set<String> = []
        let candidates = (
            snapshot.pinnedPages.map { ($0, true) }
                + snapshot.recentPages.map { ($0, false) }
        ).filter { page, _ in
            seen.insert(page.pageID.lowercased()).inserted
                && page.pageID.caseInsensitiveCompare(activePageID ?? "") != .orderedSame
        }

        let signals = MatchSignals(context: context)
        if let exactPageID = signals.exactPageID,
           let exactPage = candidates.first(where: {
               $0.0.pageID.caseInsensitiveCompare(exactPageID) == .orderedSame
           }),
           let exactSuggestion = suggestion(for: exactPage.0, in: snapshot, context: context)
        {
            return exactSuggestion
        }

        guard !signals.roleMatchTokens.isEmpty else { return nil }

        let ranked = candidates.compactMap { page, isPinned -> RankedCandidate? in
            guard let suggestion = suggestion(for: page, in: snapshot, context: context) else {
                return nil
            }

            let roleTokens = tokens(in: page.role ?? "")
            let titleTokens = tokens(in: page.displayTitle ?? "")
            let roleContentOverlap = roleTokens.intersection(signals.contentTokens).count
            let roleApplicationOverlap = signals.ignoresApplicationName
                ? 0
                : roleTokens.intersection(signals.applicationTokens).count
            let titleContentOverlap = titleTokens.intersection(signals.contentTokens).count
            let titleApplicationOverlap = signals.ignoresApplicationName
                ? 0
                : titleTokens.intersection(signals.applicationTokens).count
            guard roleContentOverlap > 0
                    || roleApplicationOverlap > 0
                    || titleContentOverlap > 0
                    || titleApplicationOverlap > 0
            else { return nil }

            var score = roleContentOverlap * 300
                + roleApplicationOverlap * 300
                + titleContentOverlap * 150
                + titleApplicationOverlap * 150
            if !roleTokens.isEmpty, roleTokens.isSubset(of: signals.roleMatchTokens) {
                score += 200
            }
            if !roleTokens.isEmpty,
               !signals.hostTokens.isEmpty,
               roleTokens.isSubset(of: signals.hostTokens)
            {
                score += 80
            }
            if !titleTokens.isEmpty, titleTokens.isSubset(of: signals.contentTokens) {
                score += 80
            }
            if isPinned { score += 20 }
            guard score >= minimumScore else { return nil }

            return RankedCandidate(
                suggestion: suggestion,
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

    private struct MatchSignals {
        let ignoresApplicationName: Bool
        let exactPageID: String?
        let applicationTokens: Set<String>
        let contentTokens: Set<String>
        let hostTokens: Set<String>
        let roleMatchTokens: Set<String>

        init(context: ContextSnapshot) {
            ignoresApplicationName = ContextualApplicationKind.ignoresApplicationName(
                bundleIdentifier: context.bundleIdentifier
            )
            exactPageID = context.exactPage?.pageID ?? ContextualNotionPageResolver.resolve(
                rawURL: context.documentURL?.absoluteString ?? "",
                sourceBundleIdentifier: context.bundleIdentifier
            )?.pageID

            let lastBundleComponent = context.bundleIdentifier
                .split(separator: ".")
                .last
                .map(String.init) ?? ""
            applicationTokens = ContextSuggestionMatcher.tokens(
                in: [lastBundleComponent, context.applicationName].joined(separator: " ")
            )

            let titleTokens = ContextSuggestionMatcher.tokens(
                in: ContextSuggestionMatcher.strippedWindowTitle(
                    context.windowTitle,
                    applicationName: context.applicationName
                )
            )
            let isNotionDocument = exactPageID != nil
                || context.documentURL.flatMap { try? NotionPageReference(validating: $0) } != nil
            if isNotionDocument {
                hostTokens = []
                contentTokens = titleTokens
            } else {
                hostTokens = ContextSuggestionMatcher.hostTokens(from: context.documentURL)
                let pathTokens = ContextSuggestionMatcher.pathTokens(from: context.documentURL)
                contentTokens = titleTokens.union(hostTokens).union(pathTokens)
            }

            if ignoresApplicationName {
                roleMatchTokens = contentTokens
            } else {
                roleMatchTokens = contentTokens.union(applicationTokens)
            }
        }
    }

    private static func suggestion(
        for page: StoredPageSnapshot,
        in snapshot: PageWorkingSetSnapshot,
        context: ContextSnapshot
    ) -> ContextSuggestion? {
        guard let validatedReference = try? NotionPageReference(validating: page.canonicalURL) else {
            return nil
        }
        let reference = validatedReference.resolvingDisplayTitle(page.displayTitle)
        return ContextSuggestion(
            page: reference,
            label: page.role ?? page.displayTitle ?? "Notion page",
            sourceApplicationName: context.applicationName,
            sourceDescription: sourceDescription(for: context),
            contextIdentity: context.identity,
            restoration: snapshot.restoration(for: page.pageID)
        )
    }

    private static func tokens(in value: String) -> Set<String> {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var result: Set<String> = []
        for raw in folded.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let token = String(raw)
            guard token.count >= 3, !stopWords.contains(token) else { continue }
            result.insert(token)
            if token.count >= 4, token.hasSuffix("s"), !token.hasSuffix("ss") {
                let stem = String(token.dropLast())
                if stem.count >= 3, !stopWords.contains(stem) {
                    result.insert(stem)
                }
            }
        }
        return result
    }

    private static func hostTokens(from url: URL?) -> Set<String> {
        guard let host = url?.host else { return [] }
        return tokens(
            in: host
                .split(separator: ".")
                .filter { $0.lowercased() != "www" }
                .joined(separator: " ")
        )
    }

    private static func pathTokens(from url: URL?) -> Set<String> {
        guard let url else { return [] }
        let isFile = url.scheme?.lowercased() == "file"
        let limit = isFile ? 3 : 4
        let components = url.path.split(separator: "/").suffix(limit)
        return tokens(in: components.joined(separator: " "))
            .subtracting(pathNoise)
    }

    private static func strippedWindowTitle(_ title: String?, applicationName: String) -> String {
        guard var current = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !current.isEmpty
        else { return "" }

        let names = [applicationName] + browserTitleNames
        let separators = [" - ", " — ", " – "]
        for name in names {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            for separator in separators {
                let suffix = separator + trimmedName
                if current.lowercased().hasSuffix(suffix.lowercased()) {
                    current.removeLast(suffix.count)
                    return current.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return current
    }

    private static func sourceDescription(for context: ContextSnapshot) -> String? {
        if let host = context.documentURL?.host, !host.isEmpty {
            return host
        }
        let title = strippedWindowTitle(
            context.windowTitle,
            applicationName: context.applicationName
        )
        guard !title.isEmpty else { return nil }
        return String(title.prefix(80))
    }
}
