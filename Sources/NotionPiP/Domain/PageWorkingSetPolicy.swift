struct PageWorkingSetMutation: Equatable, Sendable {
    let activePage: StoredPageSnapshot?
    let pinnedPages: [StoredPageSnapshot]
    let recentPages: [StoredPageSnapshot]
    let retainedRestorationIDs: Set<String>
}

/// The value-semantic rules for the collection of pages retained by the app.
struct PageWorkingSetPolicy: Sendable {
    static let standard = PageWorkingSetPolicy(pinLimit: 7, recentLimit: 7)

    let pinLimit: Int
    let recentLimit: Int

    func canonicalID(_ pageID: String) -> String {
        pageID.lowercased()
    }

    func contains(_ pages: [StoredPageSnapshot], pageID: String) -> Bool {
        pages.contains { canonicalID($0.pageID) == canonicalID(pageID) }
    }

    func orderedUnique(_ pages: [StoredPageSnapshot]) -> [StoredPageSnapshot] {
        var seen: Set<String> = []
        return pages
            .sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
                return canonicalID($0.pageID) < canonicalID($1.pageID)
            }
            .filter { seen.insert(canonicalID($0.pageID)).inserted }
    }

    func pinnedPages(from pages: [StoredPageSnapshot]) -> [StoredPageSnapshot] {
        orderedUnique(pages)
    }

    func recentPages(
        from pages: [StoredPageSnapshot],
        pinnedPages: [StoredPageSnapshot]
    ) -> [StoredPageSnapshot] {
        let pinnedIDs = Set(pinnedPages.map { canonicalID($0.pageID) })
        return Array(
            orderedUnique(pages)
                .filter { !pinnedIDs.contains(canonicalID($0.pageID)) }
                .prefix(recentLimit)
        )
    }

    func retainedRestorationIDs(
        pinnedPages: [StoredPageSnapshot],
        recentPages: [StoredPageSnapshot]
    ) -> Set<String> {
        Set((pinnedPages + recentPages).map { canonicalID($0.pageID) })
    }

    func recordVisit(
        _ page: StoredPageSnapshot,
        in snapshot: PageWorkingSetSnapshot
    ) -> PageWorkingSetMutation {
        let pins = pinnedPages(from: snapshot.pinnedPages)
        let recents = recentPages(
            from: [page] + snapshot.recentPages,
            pinnedPages: pins
        )
        return mutation(activePage: page, pinnedPages: pins, recentPages: recents)
    }

    func setPinned(
        _ isPinned: Bool,
        page: StoredPageSnapshot,
        in snapshot: PageWorkingSetSnapshot
    ) throws -> PageWorkingSetMutation {
        var pins = snapshot.pinnedPages.filter {
            canonicalID($0.pageID) != canonicalID(page.pageID)
        }
        var recents = snapshot.recentPages.filter {
            canonicalID($0.pageID) != canonicalID(page.pageID)
        }
        if isPinned {
            guard contains(snapshot.pinnedPages, pageID: page.pageID)
                    || orderedUnique(pins).count < pinLimit else {
                throw PageRepositoryError.pinLimitReached(maximum: pinLimit)
            }
            pins.append(page)
        } else {
            recents.append(page)
        }
        pins = pinnedPages(from: pins)
        recents = recentPages(from: recents, pinnedPages: pins)
        return mutation(
            activePage: snapshot.activePage,
            pinnedPages: pins,
            recentPages: recents
        )
    }

    private func mutation(
        activePage: StoredPageSnapshot?,
        pinnedPages: [StoredPageSnapshot],
        recentPages: [StoredPageSnapshot]
    ) -> PageWorkingSetMutation {
        PageWorkingSetMutation(
            activePage: activePage,
            pinnedPages: pinnedPages,
            recentPages: recentPages,
            retainedRestorationIDs: retainedRestorationIDs(
                pinnedPages: pinnedPages,
                recentPages: recentPages
            )
        )
    }
}
