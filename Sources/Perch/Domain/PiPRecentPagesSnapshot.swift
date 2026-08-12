import Foundation

struct PiPRecentPagesSnapshot: Equatable, Sendable {
    static let maximumItems = 5

    let activePageID: String?
    let pages: [StoredPageSnapshot]
    let restorations: [DurablePageRestoration]

    static func assemble(
        activePage: StoredPageSnapshot?,
        recentHistory: [StoredPageSnapshot],
        restorations: [DurablePageRestoration],
        limit: Int,
        policy: PageWorkingSetPolicy = .standard
    ) -> PiPRecentPagesSnapshot {
        let candidates = [activePage].compactMap { $0 } + recentHistory
        return PiPRecentPagesSnapshot(
            activePageID: activePage?.pageID,
            pages: Array(policy.orderedUnique(candidates).prefix(max(limit, 0))),
            restorations: restorations
        )
    }

    func restoration(for pageID: String) -> DurablePageRestoration? {
        restorations.first {
            $0.pageID.caseInsensitiveCompare(pageID) == .orderedSame
        }
    }
}

protocol PiPRecentPagesProviding: Sendable {
    func recentPiPPages(limit: Int) async throws -> PiPRecentPagesSnapshot
}
