import Foundation

enum PageRepositoryError: Error, Equatable, Sendable {
    case pinLimitReached(maximum: Int)
    case invalidRestoration
}

struct DurablePageRestoration: Equatable, Sendable {
    let pageID: String
    let lastURL: URL
    let scrollX: Double
    let scrollY: Double
    let scrollProgress: Double
    let updatedAt: Date

    init(
        pageID: String,
        validatingLastURL lastURL: URL,
        scrollX: Double,
        scrollY: Double,
        scrollProgress: Double,
        updatedAt: Date
    ) throws {
        guard let page = try? NotionPageReference(validating: lastURL),
              page.pageID.caseInsensitiveCompare(pageID) == .orderedSame,
              scrollX.isFinite,
              scrollY.isFinite,
              scrollProgress.isFinite,
              (0 ... 1).contains(scrollProgress)
        else {
            throw PageRepositoryError.invalidRestoration
        }
        self.pageID = page.pageID
        self.lastURL = lastURL
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.scrollProgress = scrollProgress
        self.updatedAt = updatedAt
    }
}

struct PageWorkingSetSnapshot: Equatable, Sendable {
    let activePage: StoredPageSnapshot?
    let pinnedPages: [StoredPageSnapshot]
    let recentPages: [StoredPageSnapshot]
    let restorations: [DurablePageRestoration]

    func restoration(for pageID: String) -> DurablePageRestoration? {
        restorations.first {
            $0.pageID.caseInsensitiveCompare(pageID) == .orderedSame
        }
    }
}
