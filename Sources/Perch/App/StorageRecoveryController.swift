import Foundation

enum StorageRecoveryPhase: Equatable {
    case idle
    case confirmingArchive
    case archiving
    case failed(String)
}

@MainActor
final class StorageRecoveryController: ObservableObject {
    @Published private(set) var phase = StorageRecoveryPhase.idle

    private let context: PersistentStoreRecoveryContext
    private let continueWithoutSavingAction: @MainActor () -> Void
    private let requestTermination: @MainActor () -> Void
    private let accessibilityAnnouncementPoster: any AccessibilityAnnouncementPosting
    private var didRequestTermination = false

    init(
        context: PersistentStoreRecoveryContext,
        continueWithoutSaving: @escaping @MainActor () -> Void,
        requestTermination: @escaping @MainActor () -> Void,
        accessibilityAnnouncementPoster: any AccessibilityAnnouncementPosting =
            AppAccessibilityAnnouncementPoster()
    ) {
        self.context = context
        continueWithoutSavingAction = continueWithoutSaving
        self.requestTermination = requestTermination
        self.accessibilityAnnouncementPoster = accessibilityAnnouncementPoster
    }

    var isBusy: Bool {
        phase == .archiving
    }

    func revealStore() {
        guard !isBusy else { return }
        context.revealStore()
    }

    func continueWithoutSaving() {
        guard !isBusy else { return }
        continueWithoutSavingAction()
    }

    func requestArchiveConfirmation() {
        guard !isBusy else { return }
        phase = .confirmingArchive
    }

    func cancelArchiveConfirmation() {
        guard phase == .confirmingArchive else { return }
        phase = .idle
    }

    func archiveStoreAndQuit() {
        guard phase == .confirmingArchive, !didRequestTermination else { return }
        phase = .archiving
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.performArchiveAndRequestTermination()
        }
    }

    private func performArchiveAndRequestTermination() {
        guard phase == .archiving, !didRequestTermination else { return }
        do {
            _ = try context.archiveStore()
            didRequestTermination = true
            requestTermination()
        } catch {
            let message = Self.failureMessage(for: error)
            phase = .failed(message)
            accessibilityAnnouncementPoster.announce(message)
        }
    }

    private static func failureMessage(for error: Error) -> String {
        guard let archiveError = error as? PersistentStoreArchiveError else {
            return "Perch could not archive its local store. Use Reveal Store in Finder and try again."
        }
        switch archiveError {
        case .noRecoverableArtifacts:
            return "Perch could not find a local store artifact to archive. Use Reveal Store in Finder to inspect the storage folder."
        case let .moveFailed(artifact, rollbackFailures) where rollbackFailures.isEmpty:
            return "Perch could not move \(artifact). All previously moved store files were returned to their original locations. Use Reveal Store in Finder and try again."
        case let .moveFailed(artifact, rollbackFailures):
            let failedNames = rollbackFailures.joined(separator: ", ")
            return "Perch could not move \(artifact), and these files could not be returned: \(failedNames). No files were deleted. Use Reveal Store in Finder before trying again."
        }
    }
}
