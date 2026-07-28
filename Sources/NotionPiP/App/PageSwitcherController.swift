import Combine
import Foundation

enum PageSwitcherSelection: Equatable, Sendable {
    case dismiss
    case activate(page: NotionPageReference, restoration: DurablePageRestoration?)
}

@MainActor
final class PageSwitcherController: ObservableObject {
    @Published var query = "" {
        didSet { rebuildSections(preservingSelection: true) }
    }
    @Published private(set) var sections: [PageSwitcherSection] = []
    @Published private(set) var selectedPageID: String?
    @Published private(set) var inlineFeedback: String?

    var onWorkingSetChanged: (@MainActor (PageWorkingSetSnapshot) -> Void)?
    private let store: any PageWorkingSetPersisting
    private var snapshot = PageWorkingSetSnapshot(
        activePage: nil,
        pinnedPages: [],
        recentPages: [],
        restorations: []
    )

    init(store: (any PageWorkingSetPersisting)? = nil) {
        self.store = store ?? InMemoryPageWorkingSetStore()
    }

    func load() async {
        do {
            snapshot = try await store.workingSet()
            inlineFeedback = nil
        } catch {
            snapshot = PageWorkingSetSnapshot(
                activePage: nil,
                pinnedPages: [],
                recentPages: [],
                restorations: []
            )
        }
        rebuildSections(preservingSelection: false)
        onWorkingSetChanged?(snapshot)
    }

    func moveSelection(by offset: Int) {
        let items = sections.flatMap(\.items)
        guard !items.isEmpty else {
            selectedPageID = nil
            return
        }
        let currentIndex = selectedPageID.flatMap { selectedID in
            items.firstIndex {
                $0.page.pageID.caseInsensitiveCompare(selectedID) == .orderedSame
            }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
        selectedPageID = items[nextIndex].page.pageID
    }

    func select(pageID: String) {
        guard sections.flatMap(\.items).contains(where: {
            $0.page.pageID.caseInsensitiveCompare(pageID) == .orderedSame
        }) else { return }
        selectedPageID = pageID
    }

    func selectCurrent() -> PageSwitcherSelection? {
        guard let item = selectedItem(),
              let page = try? NotionPageReference(validating: item.page.canonicalURL)
        else {
            return nil
        }
        if item.isActive {
            return .dismiss
        }
        return .activate(
            page: page,
            restoration: snapshot.restoration(for: page.pageID)
        )
    }

    func setPinned(_ isPinned: Bool, pageID: String) async {
        guard let item = sections.flatMap(\.items).first(where: {
            $0.page.pageID.caseInsensitiveCompare(pageID) == .orderedSame
        }),
        let page = try? NotionPageReference(validating: item.page.canonicalURL)
        else {
            return
        }
        do {
            _ = try await store.setPinned(isPinned, page: page)
            snapshot = try await store.workingSet()
            inlineFeedback = nil
            rebuildSections(preservingSelection: true)
            onWorkingSetChanged?(snapshot)
        } catch PageRepositoryError.pinLimitReached {
            inlineFeedback = "Unpin a page first."
        } catch {
            inlineFeedback = "Could not update this favorite."
        }
    }

    private func selectedItem() -> PageSwitcherItem? {
        guard let selectedPageID else { return nil }
        return sections.flatMap(\.items).first {
            $0.page.pageID.caseInsensitiveCompare(selectedPageID) == .orderedSame
        }
    }

    private func rebuildSections(preservingSelection: Bool) {
        let previousSelection = preservingSelection ? selectedPageID : nil
        sections = PageSwitcherMatcher.items(snapshot: snapshot, query: query)
        let items = sections.flatMap(\.items)
        if let previousSelection,
           items.contains(where: {
               $0.page.pageID.caseInsensitiveCompare(previousSelection) == .orderedSame
           }) {
            selectedPageID = previousSelection
        } else {
            selectedPageID = items.first?.page.pageID
        }
    }
}
