import Foundation

enum StorageRecoveryPhase: Equatable {
    case idle
    case confirmingArchive
    case archiving
    case failed(String)
    /// A retry opened the store. Perch must quit and reopen to use it, since
    /// this session already started without local storage.
    case storeAvailable
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

    /// Retries opening the store before anything is archived. A transient
    /// failure, such as a locked or briefly unavailable file, can clear up.
    func retryOpeningStore() {
        guard !isBusy, phase != .storeAvailable else { return }
        do {
            try context.retryOpenStore()
            phase = .storeAvailable
            accessibilityAnnouncementPoster.announce(
                StorageRecoveryPresentation.retrySucceededMessage
            )
        } catch {
            let message = Self.retryFailureMessage(for: error)
            phase = .failed(message)
            accessibilityAnnouncementPoster.announce(message)
        }
    }

    /// Quits after a successful retry so the next launch opens the store.
    func quitToReopen() {
        guard phase == .storeAvailable, !didRequestTermination else { return }
        didRequestTermination = true
        requestTermination()
    }

    /// The store-open error label, such as `NSCocoaErrorDomain 134110`.
    var openFailureLabel: String? {
        context.openFailure?.label
    }

    func requestArchiveConfirmation() {
        guard !isBusy, phase != .storeAvailable else { return }
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

    private static func retryFailureMessage(for error: Error) -> String {
        guard !(error is PersistentStoreRetryError) else {
            return "Perch can’t retry opening its local store from here. Quit and reopen Perch to try again."
        }
        let failure = PersistentStoreOpenFailure(error)
        return "Perch still can’t open its local store (\(failure.label)). Try again later, or use Reveal Store in Finder before archiving."
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
