import Foundation
import SwiftData

protocol QuickCaptureDestinationPersisting: Sendable {
    func defaultDestination() async throws -> QuickCaptureDestination?
    func replaceDefault(with destination: QuickCaptureDestination) async throws
    func clearDefault() async throws
}

@ModelActor
actor QuickCaptureDestinationRepository: QuickCaptureDestinationPersisting {
    init(container: ModelContainer) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        modelContainer = container
    }

    func defaultDestination() throws -> QuickCaptureDestination? {
        var descriptor = FetchDescriptor<QuickCaptureSettingsModel>()
        descriptor.fetchLimit = 1
        guard let model = try modelContext.fetch(descriptor).first else {
            return nil
        }
        guard let destination = QuickCaptureDestination(
            rawKind: model.destinationKind,
            identifier: model.destinationID,
            title: model.displayTitle
        ) else {
            throw CaptureRepositoryError.invalidStoredValue(
                "\(model.destinationKind)/\(model.destinationID)"
            )
        }
        return destination
    }

    func replaceDefault(with destination: QuickCaptureDestination) throws {
        let models = try modelContext.fetch(FetchDescriptor<QuickCaptureSettingsModel>())
        let model = models.first ?? QuickCaptureSettingsModel(
            destinationKind: destination.rawKind,
            destinationID: destination.identifier,
            displayTitle: destination.title,
            updatedAt: Date()
        )
        if model.modelContext == nil {
            modelContext.insert(model)
        }
        model.destinationKind = destination.rawKind
        model.destinationID = destination.identifier
        model.displayTitle = destination.title
        model.updatedAt = Date()
        for extra in models.dropFirst() {
            modelContext.delete(extra)
        }
        try saveOrRollback()
    }

    func clearDefault() throws {
        for model in try modelContext.fetch(FetchDescriptor<QuickCaptureSettingsModel>()) {
            modelContext.delete(model)
        }
        try saveOrRollback()
    }

    private func saveOrRollback() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
