import Foundation

public enum HistorySource: String, CaseIterable, Equatable, Sendable {
    case pinned
    case draft
    case captured
    case notion

    public var sectionTitle: String {
        switch self {
        case .pinned:
            "Pinned"
        case .draft:
            "Drafts"
        case .captured:
            "Captured"
        case .notion:
            "From Notion"
        }
    }
}

public struct HistoryItem: Equatable, Sendable {
    public let page: NotionPageReference
    public let title: String
    public let source: HistorySource
    public let timestamp: Date

    public init(
        page: NotionPageReference,
        title: String,
        source: HistorySource,
        timestamp: Date
    ) {
        self.page = page
        self.title = title
        self.source = source
        self.timestamp = timestamp
    }
}

public struct HistoryInput: Equatable, Sendable {
    public let items: [HistoryItem]

    public init(items: [HistoryItem]) {
        self.items = items
    }
}

public struct HistorySection: Equatable, Sendable {
    public let title: String
    public let source: HistorySource
    public let items: [HistoryItem]

    public init(title: String, source: HistorySource, items: [HistoryItem]) {
        self.title = title
        self.source = source
        self.items = items
    }
}

public enum HistoryAssembler {
    public static func sections(
        input: HistoryInput,
        query: String,
        limit: Int
    ) -> [HistorySection] {
        guard limit > 0 else { return [] }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = input.items.enumerated().filter { _, item in
            normalizedQuery.isEmpty
                || item.title.localizedCaseInsensitiveContains(normalizedQuery)
                || item.page.displayTitle?.localizedCaseInsensitiveContains(normalizedQuery) == true
                || item.page.pageID.localizedCaseInsensitiveContains(normalizedQuery)
        }

        var sections: [HistorySection] = []
        var seenPageIDs: Set<String> = []
        var remainingRows = limit

        for source in HistorySource.allCases where remainingRows > 0 {
            let sortedItems = candidates
                .filter { $0.element.source == source }
                .sorted { left, right in
                    if left.element.timestamp == right.element.timestamp {
                        return left.offset < right.offset
                    }
                    return left.element.timestamp > right.element.timestamp
                }

            var sectionItems: [HistoryItem] = []
            for candidate in sortedItems where remainingRows > 0 {
                let pageID = candidate.element.page.pageID.lowercased()
                guard seenPageIDs.insert(pageID).inserted else { continue }
                sectionItems.append(candidate.element)
                remainingRows -= 1
            }

            if !sectionItems.isEmpty {
                sections.append(
                    HistorySection(
                        title: source.sectionTitle,
                        source: source,
                        items: sectionItems
                    )
                )
            }
        }

        return sections
    }
}
