import Foundation
import OSLog
import SwiftData

typealias PageRepositorySaveCheck = @Sendable () throws -> Void

struct StoredPageSnapshot: Equatable, Sendable {
    let pageID: String
    let canonicalURL: URL
    let displayTitle: String?
    let timestamp: Date
}

protocol PinnedPagePersisting: Sendable {
    func currentPinnedPage() async throws -> StoredPageSnapshot?
    func replaceCurrent(with page: NotionPageReference) async throws -> StoredPageSnapshot
}

@ModelActor
actor PageRepository: PinnedPagePersisting {
    private static let maximumPins = 7
    private static let maximumRecents = 7

    private let logger = Logger(
        subsystem: "com.fantomsuj.NotionPiP",
        category: "page-working-set"
    )
    private var clock: any CaptureClock = SystemCaptureClock()
    private var beforeSave: PageRepositorySaveCheck = {}

    init(
        container: ModelContainer,
        clock: any CaptureClock = SystemCaptureClock(),
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
        let pins = validPinnedPages()
        let pinnedIDs = Set(pins.map { Self.canonicalID($0.pageID) })
        let recents = validRecentPages()
            .filter { !pinnedIDs.contains(Self.canonicalID($0.pageID)) }
            .prefix(Self.maximumRecents)
        let workingSetIDs = pinnedIDs.union(recents.map { Self.canonicalID($0.pageID) })
        let restorations = try pruneAndReadRestorations(retaining: workingSetIDs)

        return PageWorkingSetSnapshot(
            activePage: validActivePage(),
            pinnedPages: pins,
            recentPages: Array(recents),
            restorations: restorations
        )
    }

    func recordVisit(_ page: NotionPageReference) throws -> StoredPageSnapshot {
        let now = clock.now()
        let pageID = Self.canonicalID(page.pageID)
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
        let pageID = Self.canonicalID(page.pageID)
        let models = try modelContext.fetch(FetchDescriptor<PinnedPageModel>())
        let matching = models.filter { Self.canonicalID($0.stableID) == pageID }

        if isPinned {
            let distinctOtherIDs = Set(
                models.lazy
                    .filter { Self.canonicalID($0.stableID) != pageID }
                    .map { Self.canonicalID($0.stableID) }
            )
            guard distinctOtherIDs.count < Self.maximumPins else {
                throw PageRepositoryError.pinLimitReached(maximum: Self.maximumPins)
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

    func saveRestoration(
        _ restoration: DurablePageRestoration
    ) throws -> DurablePageRestoration {
        let pageID = Self.canonicalID(restoration.pageID)
        let models = try modelContext.fetch(FetchDescriptor<PageRestorationModel>())
        let matching = models.filter { Self.canonicalID($0.stableID) == pageID }
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

    // Compatibility for the existing runtime while it moves to the working-set API.
    func replaceCurrent(with page: NotionPageReference) throws -> StoredPageSnapshot {
        try recordVisit(page)
    }

    func currentPinnedPage() throws -> StoredPageSnapshot? {
        try bootstrapActivePageIfNeeded()
        return validActivePage()
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
        validPinnedPages()
    }

    func recentPages() throws -> [StoredPageSnapshot] {
        let pinnedIDs = Set(validPinnedPages().map { Self.canonicalID($0.pageID) })
        return Array(
            validRecentPages()
                .filter { !pinnedIDs.contains(Self.canonicalID($0.pageID)) }
                .prefix(Self.maximumRecents)
        )
    }

    private func bootstrapActivePageIfNeeded() throws {
        guard try modelContext.fetch(FetchDescriptor<ActivePageModel>()).isEmpty,
              let legacyPin = validPinnedPages().first
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
        return deduplicated(
            models.compactMap { model in
                guard let value = snapshotIfValid(model) else {
                    logger.error("Skipped page row category=invalid-pin")
                    return nil
                }
                return value
            }
        )
    }

    private func validRecentPages() -> [StoredPageSnapshot] {
        guard let models = try? modelContext.fetch(FetchDescriptor<RecentPageModel>()) else {
            logger.error("Page read failed category=recents-fetch")
            return []
        }
        return deduplicated(
            models.compactMap { model in
                guard let value = snapshotIfValid(model) else {
                    logger.error("Skipped page row category=invalid-recent")
                    return nil
                }
                return value
            }
        )
    }

    private func deduplicated(_ values: [StoredPageSnapshot]) -> [StoredPageSnapshot] {
        var seen: Set<String> = []
        return values
            .sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
                return Self.canonicalID($0.pageID) < Self.canonicalID($1.pageID)
            }
            .filter { seen.insert(Self.canonicalID($0.pageID)).inserted }
    }

    private func upsertRecent(
        _ page: NotionPageReference,
        visitedAt: Date,
        refreshTimestamp: Bool
    ) throws -> RecentPageModel {
        let pageID = Self.canonicalID(page.pageID)
        let models = try modelContext.fetch(FetchDescriptor<RecentPageModel>())
        let matching = models.filter { Self.canonicalID($0.stableID) == pageID }
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
        let pinnedIDs = Set(validPinnedPages().map { Self.canonicalID($0.pageID) })
        let sortedUnpinned = models
            .filter { !pinnedIDs.contains(Self.canonicalID($0.stableID)) }
            .sorted {
                if $0.visitedAt != $1.visitedAt { return $0.visitedAt > $1.visitedAt }
                return Self.canonicalID($0.stableID) < Self.canonicalID($1.stableID)
            }
        for model in sortedUnpinned.dropFirst(Self.maximumRecents) {
            modelContext.delete(model)
        }
    }

    private func pruneRestorationsToCurrentUnion() throws {
        let pins = Set(validPinnedPages().map { Self.canonicalID($0.pageID) })
        let recents = validRecentPages()
            .filter { !pins.contains(Self.canonicalID($0.pageID)) }
            .prefix(Self.maximumRecents)
        _ = try pruneAndReadRestorations(
            retaining: pins.union(recents.map { Self.canonicalID($0.pageID) })
        )
    }

    private func pruneAndReadRestorations(
        retaining pageIDs: Set<String>
    ) throws -> [DurablePageRestoration] {
        let models = try modelContext.fetch(FetchDescriptor<PageRestorationModel>())
        var values: [DurablePageRestoration] = []
        var changed = false
        for model in models {
            let pageID = Self.canonicalID(model.stableID)
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
            return Self.canonicalID($0.pageID) < Self.canonicalID($1.pageID)
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
            throw CaptureRepositoryError.invalidStoredValue(model.canonicalURL)
        }
        return value
    }

    private func snapshot(_ model: RecentPageModel) throws -> StoredPageSnapshot {
        guard let value = snapshotIfValid(model) else {
            throw CaptureRepositoryError.invalidStoredValue(model.canonicalURL)
        }
        return value
    }

    private func snapshotIfValid(_ model: PinnedPageModel) -> StoredPageSnapshot? {
        validatedSnapshot(
            stableID: model.stableID,
            canonicalURL: model.canonicalURL,
            displayTitle: model.displayTitle,
            timestamp: model.pinnedAt
        )
    }

    private func snapshotIfValid(_ model: RecentPageModel) -> StoredPageSnapshot? {
        validatedSnapshot(
            stableID: model.stableID,
            canonicalURL: model.canonicalURL,
            displayTitle: model.displayTitle,
            timestamp: model.visitedAt
        )
    }

    private func snapshotIfValid(_ model: ActivePageModel) -> StoredPageSnapshot? {
        validatedSnapshot(
            stableID: model.pageID,
            canonicalURL: model.canonicalURL,
            displayTitle: model.displayTitle,
            timestamp: model.updatedAt
        )
    }

    private func validatedSnapshot(
        stableID: String,
        canonicalURL: String,
        displayTitle: String?,
        timestamp: Date
    ) -> StoredPageSnapshot? {
        guard let url = URL(string: canonicalURL),
              let page = try? NotionPageReference(validating: url),
              Self.canonicalID(page.pageID) == Self.canonicalID(stableID)
        else {
            return nil
        }
        return StoredPageSnapshot(
            pageID: page.pageID,
            canonicalURL: page.canonicalURL,
            displayTitle: displayTitle,
            timestamp: timestamp
        )
    }

    private static func canonicalID(_ pageID: String) -> String {
        pageID.lowercased()
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
