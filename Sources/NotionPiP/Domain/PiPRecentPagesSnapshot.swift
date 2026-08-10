import Foundation

struct PiPRecentPagesSnapshot: Equatable, Sendable {
    static let maximumItems = 5

    let activePageID: String?
    let pages: [StoredPageSnapshot]
    let restorations: [DurablePageRestoration]

    func restoration(for pageID: String) -> DurablePageRestoration? {
        restorations.first {
            $0.pageID.caseInsensitiveCompare(pageID) == .orderedSame
        }
    }
}

protocol PiPRecentPagesProviding: Sendable {
    func recentPiPPages(limit: Int) async throws -> PiPRecentPagesSnapshot
}
