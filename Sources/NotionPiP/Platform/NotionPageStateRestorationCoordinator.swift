import Foundation

struct NotionInteractionStateCache {
    private let capacity: Int
    private var values: [String: Any] = [:]
    private var recency: [String] = []

    init(capacity: Int) {
        self.capacity = max(0, capacity)
    }

    var count: Int { values.count }

    mutating func insert(_ value: Any, forKey key: String) {
        guard capacity > 0 else { return }
        values[key] = value
        recency.removeAll { $0 == key }
        recency.append(key)
        while recency.count > capacity {
            let evicted = recency.removeFirst()
            values.removeValue(forKey: evicted)
        }
    }

    mutating func takeValue(forKey key: String) -> Any? {
        recency.removeAll { $0 == key }
        return values.removeValue(forKey: key)
    }

    mutating func removeValue(forKey key: String) {
        recency.removeAll { $0 == key }
        values.removeValue(forKey: key)
    }

    mutating func retain(keys: Set<String>) {
        recency.removeAll { !keys.contains($0.lowercased()) }
        values = values.filter { keys.contains($0.key.lowercased()) }
    }

    mutating func removeAll() {
        values.removeAll()
        recency.removeAll()
    }
}

@MainActor
final class NotionPageStateRestorationCoordinator {
    enum RestorationPlan {
        case interactionState(Any)
        case load(url: URL, isDurableRestoration: Bool)
    }

    private var interactionStates: NotionInteractionStateCache
    private var durableRestorations: [String: DurablePageRestoration] = [:]
    private var latestScrollSnapshots: [String: NotionScrollSnapshot] = [:]
    private var savedURL: URL?
    private var savedURLPageID: String?
    private var pendingScrollRestoration: DurablePageRestoration?
    private var isAttemptingDurableRestoration = false

    init(interactionCapacity: Int = 14) {
        interactionStates = NotionInteractionStateCache(capacity: interactionCapacity)
    }

    var interactionStateCount: Int { interactionStates.count }

    func prepareActivation(
        of page: NotionPageReference,
        restoration: DurablePageRestoration?
    ) {
        if let restoration, restoration.pageID == page.pageID {
            durableRestorations[page.pageID] = restoration
        }
        savedURL = restoration?.lastURL ?? page.canonicalURL
        savedURLPageID = page.pageID
    }

    func prepareReload(of page: NotionPageReference) {
        discardCachedState(for: page.pageID)
        pendingScrollRestoration = nil
        isAttemptingDurableRestoration = false
        savedURL = page.canonicalURL
        savedURLPageID = page.pageID
    }

    func recordLoad(
        url: URL,
        pageID: String?,
        isDurableRestoration: Bool
    ) {
        savedURL = url
        savedURLPageID = pageID
        isAttemptingDurableRestoration = isDurableRestoration
    }

    func restorationPlan(for page: NotionPageReference) -> RestorationPlan {
        if let interactionState = interactionStates.takeValue(forKey: page.pageID) {
            isAttemptingDurableRestoration = false
            pendingScrollRestoration = nil
            return .interactionState(interactionState)
        }

        let durableRestoration = durableRestorations[page.pageID]
        pendingScrollRestoration = durableRestoration
        let restorationURL = durableRestoration?.lastURL
            ?? ((savedURLPageID == nil || savedURLPageID == page.pageID)
                ? savedURL ?? page.canonicalURL
                : page.canonicalURL)
        let isDurable = durableRestoration != nil
            && restorationURL != page.canonicalURL
        isAttemptingDurableRestoration = isDurable
        return .load(url: restorationURL, isDurableRestoration: isDurable)
    }

    func recordScroll(_ snapshot: NotionScrollSnapshot, pageID: String?) {
        guard let pageID else { return }
        latestScrollSnapshots[pageID] = snapshot
    }

    func capture(
        page: NotionPageReference,
        currentURL: URL?,
        interactionState: Any?,
        now: Date = Date()
    ) -> DurablePageRestoration? {
        if let interactionState {
            interactionStates.insert(interactionState, forKey: page.pageID)
        }
        let trustedURL = currentURL ?? savedURL ?? page.canonicalURL
        let scroll = latestScrollSnapshots[page.pageID]
            ?? NotionScrollSnapshot(x: 0, y: 0, progress: 0)
        guard let restoration = try? DurablePageRestoration(
            pageID: page.pageID,
            validatingLastURL: trustedURL,
            scrollX: scroll.x,
            scrollY: scroll.y,
            scrollProgress: scroll.progress,
            updatedAt: now
        ) else {
            return nil
        }
        durableRestorations[page.pageID] = restoration
        return restoration
    }

    func takePendingScrollRestoration(for pageID: String?) -> DurablePageRestoration? {
        guard let pageID,
              pendingScrollRestoration?.pageID == pageID
        else {
            return nil
        }
        defer { pendingScrollRestoration = nil }
        return pendingScrollRestoration
    }

    func navigationDidFinish() {
        isAttemptingDurableRestoration = false
    }

    func canonicalFallbackAfterFailedDurableRestoration(
        for page: NotionPageReference
    ) -> URL? {
        guard isAttemptingDurableRestoration else { return nil }
        isAttemptingDurableRestoration = false
        pendingScrollRestoration = nil
        durableRestorations.removeValue(forKey: page.pageID)
        return page.canonicalURL
    }

    func recordResolvedPage(_ page: NotionPageReference, at url: URL) {
        savedURL = url
        savedURLPageID = page.pageID
    }

    func rendererDidTerminate(
        page: NotionPageReference?,
        loadedPageID: String? = nil,
        now: Date = Date()
    ) {
        if let page {
            let scroll = loadedPageID == page.pageID
                ? latestScrollSnapshots[page.pageID]
                : nil
            savedURL = page.canonicalURL
            savedURLPageID = page.pageID
            discardCachedState(for: page.pageID)
            if let scroll {
                pendingScrollRestoration = try? DurablePageRestoration(
                    pageID: page.pageID,
                    validatingLastURL: page.canonicalURL,
                    scrollX: scroll.x,
                    scrollY: scroll.y,
                    scrollProgress: scroll.progress,
                    updatedAt: now
                )
            }
        } else {
            pendingScrollRestoration = nil
        }
        isAttemptingDurableRestoration = false
    }

    func discardPendingScrollRestoration() {
        pendingScrollRestoration = nil
    }

    func discardCachedState(for pageID: String) {
        interactionStates.removeValue(forKey: pageID)
        durableRestorations.removeValue(forKey: pageID)
        latestScrollSnapshots.removeValue(forKey: pageID)
    }

    func evictInteractionStates(retaining pageIDs: Set<String>) {
        interactionStates.retain(keys: Set(pageIDs.map { $0.lowercased() }))
    }

    func removeAllInteractionStates() {
        interactionStates.removeAll()
    }
}
