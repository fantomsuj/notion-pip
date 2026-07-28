import Foundation

struct PageSwitcherItem: Equatable, Identifiable, Sendable {
    let page: StoredPageSnapshot
    let isPinned: Bool
    let isActive: Bool

    var id: String { page.pageID }
}

struct PageSwitcherSection: Equatable, Identifiable, Sendable {
    let title: String
    let items: [PageSwitcherItem]

    var id: String { title }
}

enum PageSwitcherMatcher {
    static func sections(
        pinned: [PageSwitcherItem],
        recents: [PageSwitcherItem],
        activePageID: String?,
        query: String
    ) -> [PageSwitcherSection] {
        let pinned = deduplicated(pinned).map { item in
            PageSwitcherItem(
                page: item.page,
                isPinned: true,
                isActive: isSamePage(item.page.pageID, activePageID)
            )
        }
        let pinnedIDs = Set(pinned.map { $0.page.pageID.lowercased() })
        let recents = deduplicated(recents)
            .filter { !pinnedIDs.contains($0.page.pageID.lowercased()) }
            .map { item in
            PageSwitcherItem(
                page: item.page,
                isPinned: false,
                isActive: isSamePage(item.page.pageID, activePageID)
            )
        }
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else {
            return [
                PageSwitcherSection(title: "Pinned", items: pinned),
                PageSwitcherSection(title: "Recent", items: recents),
            ].filter { !$0.items.isEmpty }
        }

        let results = (pinned + recents).compactMap { item -> ScoredItem? in
            guard let score = score(item: item, query: normalizedQuery) else { return nil }
            return ScoredItem(item: item, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.item.isPinned != rhs.item.isPinned { return lhs.item.isPinned }
            if lhs.item.page.timestamp != rhs.item.page.timestamp {
                return lhs.item.page.timestamp > rhs.item.page.timestamp
            }
            return lhs.item.page.pageID < rhs.item.page.pageID
        }
        .map(\.item)

        guard !results.isEmpty else { return [] }
        return [PageSwitcherSection(title: "Results", items: results)]
    }

    static func items(
        snapshot: PageWorkingSetSnapshot,
        query: String
    ) -> [PageSwitcherSection] {
        sections(
            pinned: snapshot.pinnedPages.map {
                PageSwitcherItem(page: $0, isPinned: true, isActive: false)
            },
            recents: snapshot.recentPages.map {
                PageSwitcherItem(page: $0, isPinned: false, isActive: false)
            },
            activePageID: snapshot.activePage?.pageID,
            query: query
        )
    }

    private struct ScoredItem {
        let item: PageSwitcherItem
        let score: Int
    }

    private static func score(item: PageSwitcherItem, query: String) -> Int? {
        if let title = item.page.displayTitle,
           let score = subsequenceScore(query: query, candidate: normalize(title)) {
            return 100_000 + score
        }
        return subsequenceScore(query: query, candidate: normalize(item.page.pageID))
    }

    private static func subsequenceScore(query: String, candidate: String) -> Int? {
        let queryTokens = query.split(separator: " ").map(String.init)
        guard !queryTokens.isEmpty else { return nil }
        if candidate == query { return 20_000 }

        let characters = Array(candidate)
        var cursor = 0
        var score = candidate.hasPrefix(query) ? 4_000 : 0

        for token in queryTokens {
            var previousMatch: Int?
            var tokenStart: Int?
            for queryCharacter in token {
                guard cursor < characters.count,
                      let index = characters[cursor...].firstIndex(of: queryCharacter)
                else {
                    return nil
                }
                if tokenStart == nil { tokenStart = index }
                if index == 0 || characters[index - 1].isWhitespace {
                    score += 45
                }
                if let previousMatch {
                    let gap = index - previousMatch - 1
                    score += gap == 0 ? 35 : max(0, 12 - gap)
                    score -= gap
                } else {
                    score += 20
                }
                previousMatch = index
                cursor = index + 1
            }
            if let tokenStart, tokenStart == 0 {
                score += 60
            }
        }
        score -= max(0, candidate.count - query.count) / 4
        return score
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func isSamePage(_ lhs: String, _ rhs: String?) -> Bool {
        guard let rhs else { return false }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func deduplicated(
        _ items: [PageSwitcherItem]
    ) -> [PageSwitcherItem] {
        var seen: Set<String> = []
        return items.filter {
            seen.insert($0.page.pageID.lowercased()).inserted
        }
    }
}
