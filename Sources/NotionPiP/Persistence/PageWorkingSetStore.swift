import Foundation

protocol PageWorkingSetPersisting: Sendable {
    func workingSet() async throws -> PageWorkingSetSnapshot
    func recordVisit(_ page: NotionPageReference) async throws -> StoredPageSnapshot
    func setPinned(
        _ isPinned: Bool,
        page: NotionPageReference
    ) async throws -> StoredPageSnapshot
    func saveRestoration(
        _ restoration: DurablePageRestoration
    ) async throws -> DurablePageRestoration
}

extension PageRepository: PageWorkingSetPersisting {}

actor InMemoryPageWorkingSetStore: PageWorkingSetPersisting {
    private var snapshot: PageWorkingSetSnapshot

    init(
        snapshot: PageWorkingSetSnapshot = PageWorkingSetSnapshot(
            activePage: nil,
            pinnedPages: [],
            recentPages: [],
            restorations: []
        )
    ) {
        self.snapshot = snapshot
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
        let pinnedIDs = Set(snapshot.pinnedPages.map(\.pageID))
        let recents = ([value] + snapshot.recentPages)
            .deduplicatedPages()
            .filter { !pinnedIDs.contains($0.pageID) }
        snapshot = PageWorkingSetSnapshot(
            activePage: value,
            pinnedPages: snapshot.pinnedPages,
            recentPages: Array(recents.prefix(7)),
            restorations: snapshot.restorations
        )
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
        var pins = snapshot.pinnedPages.filter {
            $0.pageID.caseInsensitiveCompare(page.pageID) != .orderedSame
        }
        var recents = snapshot.recentPages.filter {
            $0.pageID.caseInsensitiveCompare(page.pageID) != .orderedSame
        }
        if isPinned {
            guard snapshot.pinnedPages.contains(where: {
                $0.pageID.caseInsensitiveCompare(page.pageID) == .orderedSame
            }) || pins.count < 7 else {
                throw PageRepositoryError.pinLimitReached(maximum: 7)
            }
            pins.insert(value, at: 0)
        } else {
            recents.insert(value, at: 0)
            recents = Array(recents.deduplicatedPages().prefix(7))
        }
        snapshot = PageWorkingSetSnapshot(
            activePage: snapshot.activePage,
            pinnedPages: pins,
            recentPages: recents,
            restorations: snapshot.restorations
        )
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
}

private extension Array where Element == StoredPageSnapshot {
    func deduplicatedPages() -> [StoredPageSnapshot] {
        reduce(into: []) { result, value in
            guard !result.contains(where: {
                $0.pageID.caseInsensitiveCompare(value.pageID) == .orderedSame
            }) else { return }
            result.append(value)
        }
    }
}
