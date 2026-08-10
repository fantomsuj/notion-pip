import Foundation

protocol PageWorkingSetPersisting: Sendable {
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
    }

    func workingSet() -> PageWorkingSetSnapshot {
        snapshot
    }

    func recordVisit(_ page: NotionPageReference) -> StoredPageSnapshot {
        let value = StoredPageSnapshot(
            pageID: page.pageID,
            canonicalURL: page.canonicalURL,
            displayTitle: page.displayTitle,
            timestamp: Date()
        )
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
        apply(try policy.setPinned(isPinned, page: value, in: snapshot))
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
    }
}
