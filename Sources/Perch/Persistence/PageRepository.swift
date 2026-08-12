import Foundation
import OSLog
import SwiftData

typealias PageRepositorySaveCheck = @Sendable () throws -> Void

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
actor PageRepository {
    private let logger = Logger(
        subsystem: "com.fantomsuj.Perch",
        category: "page-working-set"
    )
    private var clock: any DateProviding = SystemDateProvider()
    private var beforeSave: PageRepositorySaveCheck = {}
    private let policy = PageWorkingSetPolicy.standard

    init(
        container: ModelContainer,
        clock: any DateProviding = SystemDateProvider(),
        beforeSave: @escaping PageRepositorySaveCheck = {}
    ) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        modelContainer = container
        self.clock = clock
        self.beforeSave = beforeSave
    }

    func workingSet() throws -> PageWorkingSetSnapshot {
        try bootstrapActivePageIfNeeded()
        let pins = policy.pinnedPages(from: validPinnedPages())
        let recents = policy.recentPages(from: validRecentPages(), pinnedPages: pins)
        let workingSetIDs = policy.retainedRestorationIDs(
            pinnedPages: pins,
            recentPages: recents
        )
        let restorations = try pruneAndReadRestorations(retaining: workingSetIDs)

        return PageWorkingSetSnapshot(
            activePage: validActivePage(),
            pinnedPages: pins,
            recentPages: recents,
            restorations: restorations
        )
    }

    func recentPiPPages(limit: Int) throws -> PiPRecentPagesSnapshot {
        let workingSet = try workingSet()
        return PiPRecentPagesSnapshot.assemble(
            activePage: workingSet.activePage,
            recentHistory: validRecentPages(),
            restorations: workingSet.restorations,
            limit: limit,
            policy: policy
        )
    }

    func recordVisit(_ page: NotionPageReference) throws -> StoredPageSnapshot {
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

    func setPinned(_ isPinned: Bool, page: NotionPageReference) throws -> StoredPageSnapshot {
        let pageID = policy.canonicalID(page.pageID)
        let models = try modelContext.fetch(FetchDescriptor<PinnedPageModel>())
        let matching = models.filter { policy.canonicalID($0.stableID) == pageID }

        if isPinned {
            let currentPins = policy.pinnedPages(from: validPinnedPages())
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
            among: validPinnedPages()
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

    func recordRecent(_ page: NotionPageReference) throws -> StoredPageSnapshot {
        let recent = try upsertRecent(page, visitedAt: clock.now(), refreshTimestamp: true)
        try pruneRecentModels()
        try pruneRestorationsToCurrentUnion()
        try saveOrRollback()
        return try snapshot(recent)
    }

    func pinnedPages() throws -> [StoredPageSnapshot] {
        policy.pinnedPages(from: validPinnedPages())
    }

    func recentPages() throws -> [StoredPageSnapshot] {
        policy.recentPages(
            from: validRecentPages(),
            pinnedPages: policy.pinnedPages(from: validPinnedPages())
        )
    }

    private func bootstrapActivePageIfNeeded() throws {
        guard try modelContext.fetch(FetchDescriptor<ActivePageModel>()).isEmpty,
              let legacyPin = policy.pinnedPages(from: validPinnedPages()).first
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

    private func validActivePage() -> StoredPageSnapshot? {
        guard let active = try? modelContext.fetch(FetchDescriptor<ActivePageModel>())
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

    private func validPinnedPages() -> [StoredPageSnapshot] {
        guard let models = try? modelContext.fetch(FetchDescriptor<PinnedPageModel>()) else {
            logger.error("Page read failed category=pins-fetch")
            return []
        }
        return models.compactMap { model in
            guard let value = snapshotIfValid(model) else {
                logger.error("Skipped page row category=invalid-pin")
                return nil
            }
            return value
        }
    }

    private func validRecentPages() -> [StoredPageSnapshot] {
        guard let models = try? modelContext.fetch(FetchDescriptor<RecentPageModel>()) else {
            logger.error("Page read failed category=recents-fetch")
            return []
        }
        return models.compactMap { model in
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
        let models = try modelContext.fetch(FetchDescriptor<RecentPageModel>())
        let pins = policy.pinnedPages(from: validPinnedPages())
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

    private func pruneRestorationsToCurrentUnion() throws {
        let pins = policy.pinnedPages(from: validPinnedPages())
        let recents = policy.recentPages(from: validRecentPages(), pinnedPages: pins)
        _ = try pruneAndReadRestorations(
            retaining: policy.retainedRestorationIDs(pinnedPages: pins, recentPages: recents)
        )
    }

    private func pruneAndReadRestorations(
        retaining pageIDs: Set<String>
    ) throws -> [DurablePageRestoration] {
        let models = try modelContext.fetch(FetchDescriptor<PageRestorationModel>())
        var values: [DurablePageRestoration] = []
        var changed = false
        for model in models {
            let pageID = policy.canonicalID(model.stableID)
            guard pageIDs.contains(pageID) else {
                modelContext.delete(model)
                changed = true
                continue
            }
            guard let value = restorationIfValid(model) else {
                logger.error("Skipped page row category=invalid-restoration")
                modelContext.delete(model)
                changed = true
                continue
            }
            values.append(value)
        }
        if changed {
            try saveOrRollback()
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
