import Foundation
import OSLog
import SwiftData

typealias PageRepositorySaveCheck = @Sendable () throws -> Void

/// The page tables a repository read helper fetches. Tests use it to inject a
/// read failure into one table and prove nothing is pruned afterwards.
enum PageRepositoryReadScope: Sendable, Equatable {
    case activePage
    case pinnedPages
    case recentPages
    case restorations
}

typealias PageRepositoryReadCheck = @Sendable (PageRepositoryReadScope) throws -> Void

struct StoredPageSnapshot: Equatable, Sendable {
    let pageID: String
    let canonicalURL: URL
    let displayTitle: String?
    let role: String?
    let timestamp: Date

    init(
        pageID: String,
        canonicalURL: URL,
        displayTitle: String?,
        role: String? = nil,
        timestamp: Date
    ) {
        self.pageID = pageID
        self.canonicalURL = canonicalURL
        self.displayTitle = displayTitle
        self.role = role
        self.timestamp = timestamp
    }
}

@ModelActor
actor PageRepository: NotionPageDropTitleProviding {
    private let logger = Logger(
        subsystem: "com.fantomsuj.Perch",
        category: "page-working-set"
    )
    private var clock: any DateProviding = SystemDateProvider()
    private var beforeSave: PageRepositorySaveCheck = {}
    private var beforeRead: PageRepositoryReadCheck = { _ in }
    private var isStorePrepared = false
    private let policy = PageWorkingSetPolicy.standard

    init(
        container: ModelContainer,
        clock: any DateProviding = SystemDateProvider(),
        beforeSave: @escaping PageRepositorySaveCheck = {},
        beforeRead: @escaping PageRepositoryReadCheck = { _ in }
    ) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        modelContainer = container
        self.clock = clock
        self.beforeSave = beforeSave
        self.beforeRead = beforeRead
    }

    /// Runs the one-time store maintenance: the legacy active-page bootstrap
    /// and pruning of restorations outside the working set.
    ///
    /// It runs once per opened store, before the first working-set read, and
    /// never again on later reads. Any read error throws before anything is
    /// deleted or saved, and leaves the maintenance pending for the next call.
    func prepareStoreIfNeeded() throws {
        guard !isStorePrepared else { return }
        try bootstrapActivePageIfNeeded()
        try pruneRestorationsToCurrentUnion()
        isStorePrepared = true
    }

    /// Reads the working set. After the one-time maintenance in
    /// ``prepareStoreIfNeeded()``, this never deletes or saves anything.
    func workingSet() throws -> PageWorkingSetSnapshot {
        try prepareStoreIfNeeded()
        let pins = policy.pinnedPages(from: try validPinnedPages())
        let recents = policy.recentPages(from: try validRecentPages(), pinnedPages: pins)
        let workingSetIDs = policy.retainedRestorationIDs(
            pinnedPages: pins,
            recentPages: recents
        )
        let restorations = try readRestorations(retaining: workingSetIDs)

        return PageWorkingSetSnapshot(
            activePage: try validActivePage(),
            pinnedPages: pins,
            recentPages: recents,
            restorations: restorations
        )
    }

    func recentPiPPages(limit: Int) throws -> PiPRecentPagesSnapshot {
        let workingSet = try workingSet()
        return PiPRecentPagesSnapshot.assemble(
            activePage: workingSet.activePage,
            recentHistory: try validRecentPages(),
            restorations: workingSet.restorations,
            limit: limit,
            policy: policy
        )
    }

    func recordVisit(_ page: NotionPageReference) throws -> StoredPageSnapshot {
        try rollingBackOnFailure { try applyVisit(page) }
    }

    func setPinned(_ isPinned: Bool, page: NotionPageReference) throws -> StoredPageSnapshot {
        try rollingBackOnFailure { try applyPinned(isPinned, page: page) }
    }

    func recordRecent(_ page: NotionPageReference) throws -> StoredPageSnapshot {
        try rollingBackOnFailure { try applyRecent(page) }
    }

    private func applyVisit(_ page: NotionPageReference) throws -> StoredPageSnapshot {
        let now = clock.now()
        let pageID = policy.canonicalID(page.pageID)
        let activeModels = try modelContext.fetch(FetchDescriptor<ActivePageModel>())
        let active = activeModels.first(where: { $0.stableID == "active" })
            ?? ActivePageModel(
                pageID: pageID,
                canonicalURL: page.canonicalURL.absoluteString,
                displayTitle: page.displayTitle,
                updatedAt: now
            )
        if active.modelContext == nil {
            modelContext.insert(active)
        }
        for duplicate in activeModels where duplicate !== active {
            modelContext.delete(duplicate)
        }
        active.pageID = pageID
        active.canonicalURL = page.canonicalURL.absoluteString
        active.displayTitle = page.displayTitle
        active.updatedAt = now

        let recent = try upsertRecent(page, visitedAt: now, refreshTimestamp: true)
        try pruneRecentModels()
        try pruneRestorationsToCurrentUnion()
        try saveOrRollback()
        return try snapshot(recent)
    }

    private func applyPinned(
        _ isPinned: Bool,
        page: NotionPageReference
    ) throws -> StoredPageSnapshot {
        let pageID = policy.canonicalID(page.pageID)
        let models = try modelContext.fetch(FetchDescriptor<PinnedPageModel>())
        let matching = models.filter { policy.canonicalID($0.stableID) == pageID }

        if isPinned {
            let currentPins = policy.pinnedPages(from: try validPinnedPages())
            guard policy.contains(currentPins, pageID: pageID)
                    || currentPins.count < policy.pinLimit else {
                throw PageRepositoryError.pinLimitReached(maximum: policy.pinLimit)
            }

            let now = clock.now()
            let model = matching.first
                ?? PinnedPageModel(
                    stableID: pageID,
                    canonicalURL: page.canonicalURL.absoluteString,
                    displayTitle: page.displayTitle,
                    pinnedAt: now
                )
            if model.modelContext == nil {
                modelContext.insert(model)
            }
            for duplicate in matching.dropFirst() {
                modelContext.delete(duplicate)
            }
            model.stableID = pageID
            model.canonicalURL = page.canonicalURL.absoluteString
            model.displayTitle = page.displayTitle
            model.pinnedAt = now
            _ = try upsertRecent(page, visitedAt: now, refreshTimestamp: false)
            try pruneRecentModels()
            try pruneRestorationsToCurrentUnion()
            try saveOrRollback()
            return try snapshot(model)
        }

        for model in matching {
            modelContext.delete(model)
        }
        _ = try upsertRecent(page, visitedAt: clock.now(), refreshTimestamp: false)
        try pruneRecentModels()
        try pruneRestorationsToCurrentUnion()
        try saveOrRollback()
        return StoredPageSnapshot(
            pageID: pageID,
            canonicalURL: page.canonicalURL,
            displayTitle: page.displayTitle,
            timestamp: clock.now()
        )
    }

    func setRole(_ rawRole: String?, pageID: String) throws -> StoredPageSnapshot {
        let canonicalPageID = policy.canonicalID(pageID)
        let models = try modelContext.fetch(FetchDescriptor<PinnedPageModel>())
        guard let model = models.first(where: {
            policy.canonicalID($0.stableID) == canonicalPageID
        }) else {
            throw PageRepositoryError.roleRequiresPinnedPage
        }
        let role = try PinnedPageRole.normalized(
            rawRole,
            for: canonicalPageID,
            among: try validPinnedPages()
        )
        model.role = role
        try saveOrRollback()
        return try snapshot(model)
    }

    func saveRestoration(
        _ restoration: DurablePageRestoration
    ) throws -> DurablePageRestoration {
        let pageID = policy.canonicalID(restoration.pageID)
        let models = try modelContext.fetch(FetchDescriptor<PageRestorationModel>())
        let matching = models.filter { policy.canonicalID($0.stableID) == pageID }
        let model = matching.first
            ?? PageRestorationModel(
                stableID: pageID,
                lastURL: restoration.lastURL.absoluteString,
                scrollX: restoration.scrollX,
                scrollY: restoration.scrollY,
                scrollProgress: restoration.scrollProgress,
                updatedAt: restoration.updatedAt
            )
        if model.modelContext == nil {
            modelContext.insert(model)
        }
        for duplicate in matching.dropFirst() {
            modelContext.delete(duplicate)
        }
        model.stableID = pageID
        model.lastURL = restoration.lastURL.absoluteString
        model.scrollX = restoration.scrollX
        model.scrollY = restoration.scrollY
        model.scrollProgress = restoration.scrollProgress
        model.updatedAt = restoration.updatedAt
        try saveOrRollback()
        return restoration
    }

    func pin(_ page: NotionPageReference) throws -> StoredPageSnapshot {
        try setPinned(true, page: page)
    }

    private func applyRecent(_ page: NotionPageReference) throws -> StoredPageSnapshot {
        let recent = try upsertRecent(page, visitedAt: clock.now(), refreshTimestamp: true)
        try pruneRecentModels()
        try pruneRestorationsToCurrentUnion()
        try saveOrRollback()
        return try snapshot(recent)
    }

    func pinnedPages() throws -> [StoredPageSnapshot] {
        policy.pinnedPages(from: try validPinnedPages())
    }

    func recentPages() throws -> [StoredPageSnapshot] {
        policy.recentPages(
            from: try validRecentPages(),
            pinnedPages: policy.pinnedPages(from: try validPinnedPages())
        )
    }

    func displayTitle(for pageID: String) -> String? {
        let canonicalPageID = policy.canonicalID(pageID)
        let candidates: [StoredPageSnapshot]
        do {
            let activePage = try validActivePage()
            let pinnedPages = policy.pinnedPages(from: try validPinnedPages())
            let recentPages = policy.recentPages(
                from: try validRecentPages(),
                pinnedPages: pinnedPages
            )
            candidates = [activePage].compactMap { $0 } + pinnedPages + recentPages
        } catch {
            // The failed read is already logged; a missing title only falls
            // back to the dropped link's own text.
            return nil
        }

        for candidate in candidates where policy.canonicalID(candidate.pageID) == canonicalPageID {
            guard let title = candidate.displayTitle?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !title.isEmpty else {
                continue
            }
            return title
        }
        return nil
    }

    private func bootstrapActivePageIfNeeded() throws {
        guard try fetch(ActivePageModel.self, scope: .activePage).isEmpty,
              let legacyPin = policy.pinnedPages(from: try validPinnedPages()).first
        else {
            return
        }
        modelContext.insert(
            ActivePageModel(
                pageID: legacyPin.pageID,
                canonicalURL: legacyPin.canonicalURL.absoluteString,
                displayTitle: legacyPin.displayTitle,
                updatedAt: legacyPin.timestamp
            )
        )
        try saveOrRollback()
    }

    /// Fetches every row of one page table. A failed fetch is logged and
    /// rethrown, never turned into an empty list: callers prune rows that look
    /// unreferenced, so an empty read would delete saved pages.
    private func fetch<Model: PersistentModel>(
        _ type: Model.Type,
        scope: PageRepositoryReadScope
    ) throws -> [Model] {
        do {
            try beforeRead(scope)
            return try modelContext.fetch(FetchDescriptor<Model>())
        } catch {
            let nsError = error as NSError
            logger.error(
                "Page read failed category=\(String(describing: scope), privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
            throw error
        }
    }

    private func validActivePage() throws -> StoredPageSnapshot? {
        guard let active = try fetch(ActivePageModel.self, scope: .activePage)
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .first
        else {
            return nil
        }
        guard let snapshot = snapshotIfValid(active) else {
            logger.error("Skipped page row category=invalid-active-page")
            return nil
        }
        return snapshot
    }

    private func validPinnedPages() throws -> [StoredPageSnapshot] {
        try fetch(PinnedPageModel.self, scope: .pinnedPages).compactMap { model in
            guard let value = snapshotIfValid(model) else {
                logger.error("Skipped page row category=invalid-pin")
                return nil
            }
            return value
        }
    }

    private func validRecentPages() throws -> [StoredPageSnapshot] {
        try fetch(RecentPageModel.self, scope: .recentPages).compactMap { model in
            guard let value = snapshotIfValid(model) else {
                logger.error("Skipped page row category=invalid-recent")
                return nil
            }
            return value
        }
    }

    private func upsertRecent(
        _ page: NotionPageReference,
        visitedAt: Date,
        refreshTimestamp: Bool
    ) throws -> RecentPageModel {
        let pageID = policy.canonicalID(page.pageID)
        let models = try modelContext.fetch(FetchDescriptor<RecentPageModel>())
        let matching = models.filter { policy.canonicalID($0.stableID) == pageID }
        let model = matching.first
            ?? RecentPageModel(
                stableID: pageID,
                canonicalURL: page.canonicalURL.absoluteString,
                displayTitle: page.displayTitle,
                visitedAt: visitedAt
            )
        if model.modelContext == nil {
            modelContext.insert(model)
        }
        for duplicate in matching.dropFirst() {
            modelContext.delete(duplicate)
        }
        model.stableID = pageID
        model.canonicalURL = page.canonicalURL.absoluteString
        model.displayTitle = page.displayTitle
        if refreshTimestamp || matching.isEmpty {
            model.visitedAt = visitedAt
        }
        return model
    }

    private func pruneRecentModels() throws {
        let models = try fetch(RecentPageModel.self, scope: .recentPages)
        let pins = policy.pinnedPages(from: try validPinnedPages())
        let pinnedIDs = policy.retainedRestorationIDs(pinnedPages: pins, recentPages: [])
        let sortedUnpinned = models
            .filter { !pinnedIDs.contains(policy.canonicalID($0.stableID)) }
            .sorted {
                if $0.visitedAt != $1.visitedAt { return $0.visitedAt > $1.visitedAt }
                return policy.canonicalID($0.stableID) < policy.canonicalID($1.stableID)
            }
        for model in sortedUnpinned.dropFirst(policy.recentLimit) {
            modelContext.delete(model)
        }
    }

    /// Deletes restorations outside the pinned and recent union. Every table is
    /// read before anything is deleted, so a read error prunes nothing.
    private func pruneRestorationsToCurrentUnion() throws {
        let pins = policy.pinnedPages(from: try validPinnedPages())
        let recents = policy.recentPages(from: try validRecentPages(), pinnedPages: pins)
        let retainedIDs = policy.retainedRestorationIDs(pinnedPages: pins, recentPages: recents)
        let models = try fetch(PageRestorationModel.self, scope: .restorations)
        var changed = false
        for model in models where !retainedIDs.contains(policy.canonicalID(model.stableID))
            || restorationIfValid(model) == nil {
            modelContext.delete(model)
            changed = true
        }
        if changed {
            try saveOrRollback()
        }
    }

    /// Reads restorations for the given pages without deleting anything.
    private func readRestorations(
        retaining pageIDs: Set<String>
    ) throws -> [DurablePageRestoration] {
        let models = try fetch(PageRestorationModel.self, scope: .restorations)
        let values = models.compactMap { model -> DurablePageRestoration? in
            guard pageIDs.contains(policy.canonicalID(model.stableID)) else {
                return nil
            }
            guard let value = restorationIfValid(model) else {
                logger.error("Skipped page row category=invalid-restoration")
                return nil
            }
            return value
        }
        return values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return policy.canonicalID($0.pageID) < policy.canonicalID($1.pageID)
        }
    }

    private func restorationIfValid(
        _ model: PageRestorationModel
    ) -> DurablePageRestoration? {
        guard let url = URL(string: model.lastURL) else { return nil }
        return try? DurablePageRestoration(
            pageID: model.stableID,
            validatingLastURL: url,
            scrollX: model.scrollX,
            scrollY: model.scrollY,
            scrollProgress: model.scrollProgress,
            updatedAt: model.updatedAt
        )
    }

    private func snapshot(_ model: PinnedPageModel) throws -> StoredPageSnapshot {
        guard let value = snapshotIfValid(model) else {
            throw PageRepositoryError.invalidStoredValue(model.canonicalURL)
        }
        return value
    }

    private func snapshot(_ model: RecentPageModel) throws -> StoredPageSnapshot {
        guard let value = snapshotIfValid(model) else {
            throw PageRepositoryError.invalidStoredValue(model.canonicalURL)
        }
        return value
    }

    private func snapshotIfValid(_ model: PinnedPageModel) -> StoredPageSnapshot? {
        validatedSnapshot(
            stableID: model.stableID,
            canonicalURL: model.canonicalURL,
            displayTitle: model.displayTitle,
            role: model.role,
            timestamp: model.pinnedAt
        )
    }

    private func snapshotIfValid(_ model: RecentPageModel) -> StoredPageSnapshot? {
        validatedSnapshot(
            stableID: model.stableID,
            canonicalURL: model.canonicalURL,
            displayTitle: model.displayTitle,
            role: nil,
            timestamp: model.visitedAt
        )
    }

    private func snapshotIfValid(_ model: ActivePageModel) -> StoredPageSnapshot? {
        validatedSnapshot(
            stableID: model.pageID,
            canonicalURL: model.canonicalURL,
            displayTitle: model.displayTitle,
            role: nil,
            timestamp: model.updatedAt
        )
    }

    private func validatedSnapshot(
        stableID: String,
        canonicalURL: String,
        displayTitle: String?,
        role: String?,
        timestamp: Date
    ) -> StoredPageSnapshot? {
        guard let url = URL(string: canonicalURL),
              let page = try? NotionPageReference(validating: url),
              policy.canonicalID(page.pageID) == policy.canonicalID(stableID)
        else {
            return nil
        }
        return StoredPageSnapshot(
            pageID: page.pageID,
            canonicalURL: page.canonicalURL,
            displayTitle: displayTitle,
            role: role,
            timestamp: timestamp
        )
    }

    /// Discards unsaved changes when a write fails part way, for example when
    /// a read fails after a row was inserted, so a later save can't commit a
    /// half-applied change.
    private func rollingBackOnFailure<Value>(
        _ body: () throws -> Value
    ) throws -> Value {
        do {
            return try body()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func saveOrRollback() throws {
        do {
            try beforeSave()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
