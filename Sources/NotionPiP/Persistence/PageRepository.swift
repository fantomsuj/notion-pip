import Foundation
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

    func replaceCurrent(with page: NotionPageReference) throws -> StoredPageSnapshot {
        let models = try modelContext.fetch(FetchDescriptor<PinnedPageModel>())
        let now = clock.now()
        let model = models.first { $0.stableID == page.pageID }
            ?? PinnedPageModel(
                stableID: page.pageID,
                canonicalURL: page.canonicalURL.absoluteString,
                displayTitle: page.displayTitle,
                pinnedAt: now
            )
        if model.modelContext == nil { modelContext.insert(model) }
        model.canonicalURL = page.canonicalURL.absoluteString
        model.displayTitle = page.displayTitle
        model.pinnedAt = now
        for otherModel in models where otherModel !== model {
            modelContext.delete(otherModel)
        }
        do {
            try beforeSave()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return try snapshot(model)
    }

    func currentPinnedPage() throws -> StoredPageSnapshot? {
        var descriptor = FetchDescriptor<PinnedPageModel>(
            sortBy: [SortDescriptor(\PinnedPageModel.pinnedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(snapshot)
    }

    func pin(_ page: NotionPageReference) throws -> StoredPageSnapshot {
        let models = try modelContext.fetch(FetchDescriptor<PinnedPageModel>())
        let now = clock.now()
        let model = models.first { $0.stableID == page.pageID }
            ?? PinnedPageModel(
                stableID: page.pageID,
                canonicalURL: page.canonicalURL.absoluteString,
                displayTitle: page.displayTitle,
                pinnedAt: now
            )
        if model.modelContext == nil { modelContext.insert(model) }
        model.canonicalURL = page.canonicalURL.absoluteString
        model.displayTitle = page.displayTitle
        model.pinnedAt = now
        do {
            try beforeSave()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return try snapshot(model)
    }

    func recordRecent(_ page: NotionPageReference) throws -> StoredPageSnapshot {
        let models = try modelContext.fetch(FetchDescriptor<RecentPageModel>())
        let now = clock.now()
        let model = models.first { $0.stableID == page.pageID }
            ?? RecentPageModel(
                stableID: page.pageID,
                canonicalURL: page.canonicalURL.absoluteString,
                displayTitle: page.displayTitle,
                visitedAt: now
            )
        if model.modelContext == nil { modelContext.insert(model) }
        model.canonicalURL = page.canonicalURL.absoluteString
        model.displayTitle = page.displayTitle
        model.visitedAt = now
        do {
            try beforeSave()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return try snapshot(model)
    }

    func pinnedPages() throws -> [StoredPageSnapshot] {
        try modelContext.fetch(FetchDescriptor<PinnedPageModel>())
            .map(snapshot)
            .sorted { $0.timestamp > $1.timestamp }
    }

    func recentPages() throws -> [StoredPageSnapshot] {
        try modelContext.fetch(FetchDescriptor<RecentPageModel>())
            .map(snapshot)
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func snapshot(_ model: PinnedPageModel) throws -> StoredPageSnapshot {
        guard let url = URL(string: model.canonicalURL),
              let page = try? NotionPageReference(validating: url),
              page.pageID == model.stableID
        else {
            throw CaptureRepositoryError.invalidStoredValue(model.canonicalURL)
        }
        return StoredPageSnapshot(
            pageID: model.stableID,
            canonicalURL: page.canonicalURL,
            displayTitle: model.displayTitle,
            timestamp: model.pinnedAt
        )
    }

    private func snapshot(_ model: RecentPageModel) throws -> StoredPageSnapshot {
        guard let url = URL(string: model.canonicalURL) else {
            throw CaptureRepositoryError.invalidStoredValue(model.canonicalURL)
        }
        return StoredPageSnapshot(
            pageID: model.stableID,
            canonicalURL: url,
            displayTitle: model.displayTitle,
            timestamp: model.visitedAt
        )
    }
}
