import Foundation

protocol PageWorkingSetPersisting: PiPRecentPagesProviding, Sendable {
    func workingSet() async throws -> PageWorkingSetSnapshot
    func recordVisit(_ page: NotionPageReference) async throws -> StoredPageSnapshot
    func setPinned(
        _ isPinned: Bool,
        page: NotionPageReference
    ) async throws -> StoredPageSnapshot
    func setRole(_ role: String?, pageID: String) async throws -> StoredPageSnapshot
    func saveRestoration(
        _ restoration: DurablePageRestoration
    ) async throws -> DurablePageRestoration
}

extension PageRepository: PageWorkingSetPersisting {}

actor InMemoryPageWorkingSetStore: PageWorkingSetPersisting {
    private var snapshot: PageWorkingSetSnapshot
    private var recentHistory: [StoredPageSnapshot]
    private let policy: PageWorkingSetPolicy

    init(
        snapshot: PageWorkingSetSnapshot = PageWorkingSetSnapshot(
            activePage: nil,
            pinnedPages: [],
            recentPages: [],
            restorations: []
        ),
        policy: PageWorkingSetPolicy = .standard
    ) {
        self.snapshot = snapshot
        self.policy = policy
        recentHistory = Self.prunedRecentHistory(
            [snapshot.activePage].compactMap { $0 }
                + snapshot.pinnedPages
                + snapshot.recentPages,
            pinnedPages: snapshot.pinnedPages,
            policy: policy
        )
    }

    func workingSet() -> PageWorkingSetSnapshot {
        snapshot
    }

    func recentPiPPages(limit: Int) -> PiPRecentPagesSnapshot {
        PiPRecentPagesSnapshot.assemble(
            activePage: snapshot.activePage,
            recentHistory: recentHistory,
            restorations: snapshot.restorations,
            limit: limit,
            policy: policy
        )
    }

    func recordVisit(_ page: NotionPageReference) -> StoredPageSnapshot {
        let value = StoredPageSnapshot(
            pageID: page.pageID,
            canonicalURL: page.canonicalURL,
            displayTitle: page.displayTitle,
            timestamp: Date()
        )
        recentHistory = policy.orderedUnique([value] + recentHistory)
        apply(policy.recordVisit(value, in: snapshot))
        return value
    }

    func setPinned(
        _ isPinned: Bool,
        page: NotionPageReference
    ) throws -> StoredPageSnapshot {
        let value = StoredPageSnapshot(
            pageID: page.pageID,
            canonicalURL: page.canonicalURL,
            displayTitle: page.displayTitle,
            timestamp: Date()
        )
        let mutation = try policy.setPinned(isPinned, page: value, in: snapshot)
        upsertRecentHistory(value)
        apply(mutation)
        return value
    }

    func saveRestoration(
        _ restoration: DurablePageRestoration
    ) -> DurablePageRestoration {
        let values = ([restoration] + snapshot.restorations).reduce(
            into: [DurablePageRestoration]()
        ) { result, value in
            guard !result.contains(where: {
                $0.pageID.caseInsensitiveCompare(value.pageID) == .orderedSame
            }) else { return }
            result.append(value)
        }
        snapshot = PageWorkingSetSnapshot(
            activePage: snapshot.activePage,
            pinnedPages: snapshot.pinnedPages,
            recentPages: snapshot.recentPages,
            restorations: values
        )
        return restoration
    }

    func setRole(_ rawRole: String?, pageID: String) throws -> StoredPageSnapshot {
        guard let index = snapshot.pinnedPages.firstIndex(where: {
            $0.pageID.caseInsensitiveCompare(pageID) == .orderedSame
        }) else {
            throw PageRepositoryError.roleRequiresPinnedPage
        }
        let role = try PinnedPageRole.normalized(
            rawRole,
            for: pageID,
            among: snapshot.pinnedPages
        )
        let current = snapshot.pinnedPages[index]
        let updated = StoredPageSnapshot(
            pageID: current.pageID,
            canonicalURL: current.canonicalURL,
            displayTitle: current.displayTitle,
            role: role,
            timestamp: current.timestamp
        )
        var pinnedPages = snapshot.pinnedPages
        pinnedPages[index] = updated
        snapshot = PageWorkingSetSnapshot(
            activePage: snapshot.activePage,
            pinnedPages: pinnedPages,
            recentPages: snapshot.recentPages,
            restorations: snapshot.restorations
        )
        return updated
    }

    private func apply(_ mutation: PageWorkingSetMutation) {
        snapshot = PageWorkingSetSnapshot(
            activePage: mutation.activePage,
            pinnedPages: mutation.pinnedPages,
            recentPages: mutation.recentPages,
            restorations: snapshot.restorations.filter {
                mutation.retainedRestorationIDs.contains(policy.canonicalID($0.pageID))
            }
        )
        pruneRecentHistory()
    }

    private func upsertRecentHistory(_ page: StoredPageSnapshot) {
        let pageID = policy.canonicalID(page.pageID)
        if let current = recentHistory.first(where: {
            policy.canonicalID($0.pageID) == pageID
        }) {
            recentHistory.removeAll {
                policy.canonicalID($0.pageID) == pageID
            }
            recentHistory.append(
                StoredPageSnapshot(
                    pageID: page.pageID,
                    canonicalURL: page.canonicalURL,
                    displayTitle: page.displayTitle,
                    role: current.role,
                    timestamp: current.timestamp
                )
            )
        } else {
            recentHistory.append(page)
        }
        recentHistory = policy.orderedUnique(recentHistory)
    }

    private func pruneRecentHistory() {
        recentHistory = Self.prunedRecentHistory(
            recentHistory,
            pinnedPages: snapshot.pinnedPages,
            policy: policy
        )
    }

    private static func prunedRecentHistory(
        _ recentHistory: [StoredPageSnapshot],
        pinnedPages: [StoredPageSnapshot],
        policy: PageWorkingSetPolicy
    ) -> [StoredPageSnapshot] {
        let pinnedIDs = Set(pinnedPages.map { policy.canonicalID($0.pageID) })
        let orderedHistory = policy.orderedUnique(recentHistory)
        let pinnedHistory = orderedHistory.filter {
            pinnedIDs.contains(policy.canonicalID($0.pageID))
        }
        let unpinnedHistory = orderedHistory.filter {
            !pinnedIDs.contains(policy.canonicalID($0.pageID))
        }
        return policy.orderedUnique(
            pinnedHistory + Array(unpinnedHistory.prefix(policy.recentLimit))
        )
    }
}
