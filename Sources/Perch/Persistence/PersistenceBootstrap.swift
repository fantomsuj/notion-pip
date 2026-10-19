import Foundation
import OSLog

/// The domain and code of a store-open error, safe to log and show. It never
/// carries the error's description, which can include private file paths.
struct PersistentStoreOpenFailure: Equatable, Sendable {
    let domain: String
    let code: Int

    init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }

    init(_ error: any Error) {
        let nsError = error as NSError
        self.init(domain: nsError.domain, code: nsError.code)
    }

    /// A short label such as `NSCocoaErrorDomain 134110`.
    var label: String {
        "\(domain) \(code)"
    }
}

enum PersistentStoreRetryError: Error, Equatable {
    case unavailable
}

struct PersistentStoreRecoveryContext {
    private let archiveStoreAction: () throws -> PersistentStoreArchiveReceipt
    private let revealStoreAction: () -> Void
    private let retryOpenStoreAction: () throws -> Void
    /// Why the store failed to open, when the bootstrapper caught an error.
    private(set) var openFailure: PersistentStoreOpenFailure?

    init(
        archiveStore: @escaping () throws -> PersistentStoreArchiveReceipt,
        revealStore: @escaping () -> Void,
        retryOpenStore: @escaping () throws -> Void = {
            throw PersistentStoreRetryError.unavailable
        },
        openFailure: PersistentStoreOpenFailure? = nil
    ) {
        archiveStoreAction = archiveStore
        revealStoreAction = revealStore
        retryOpenStoreAction = retryOpenStore
        self.openFailure = openFailure
    }

    func archiveStore() throws -> PersistentStoreArchiveReceipt {
        try archiveStoreAction()
    }

    /// Tries to open the store again without changing any files. It throws
    /// the new open error when the store still can't be opened.
    func retryOpenStore() throws {
        try retryOpenStoreAction()
    }

    func recordingOpenFailure(
        _ failure: PersistentStoreOpenFailure
    ) -> PersistentStoreRecoveryContext {
        var context = self
        context.openFailure = failure
        return context
    }

    func revealStore() {
        revealStoreAction()
    }
}

enum PersistenceBootstrapResult {
    case available(PageRepository)
    case recoveryRequired(PersistentStoreRecoveryContext)

    var pageRepository: PageRepository? {
        guard case let .available(repository) = self else { return nil }
        return repository
    }

    var recoveryContext: PersistentStoreRecoveryContext? {
        guard case let .recoveryRequired(context) = self else { return nil }
        return context
    }

    var initialServiceHealth: ServiceHealthState {
        switch self {
        case .available:
            .healthy
        case .recoveryRequired:
            ServiceHealthState(issues: [.persistentStoreUnavailable])
        }
    }
}

struct PersistenceBootstrapper {
    private let openRepository: () throws -> PageRepository
    private let recoveryContext: PersistentStoreRecoveryContext

    init(
        openRepository: @escaping () throws -> PageRepository,
        recoveryContext: PersistentStoreRecoveryContext
    ) {
        self.openRepository = openRepository
        self.recoveryContext = recoveryContext
    }

    static func live(
        applicationSupportDirectory: URL? = nil
    ) -> PersistenceBootstrapper {
        let storeDirectory = PerchPersistence.storeDirectory(
            applicationSupportDirectory: applicationSupportDirectory
        )
        let archiveService = PersistentStoreArchiveService(
            storeDirectory: storeDirectory
        )
        let revealer = PersistentStoreRevealer(storeDirectory: storeDirectory)
        return PersistenceBootstrapper(
            openRepository: {
                let container = try PerchPersistence.makeContainer(
                    applicationSupportDirectory: applicationSupportDirectory
                )
                return PageRepository(container: container)
            },
            recoveryContext: PersistentStoreRecoveryContext(
                archiveStore: archiveService.archive,
                revealStore: revealer.revealStore,
                retryOpenStore: {
                    do {
                        // Opening is the whole check. The container closes
                        // as soon as this returns; the user then reopens Perch.
                        _ = try PerchPersistence.makeContainer(
                            applicationSupportDirectory: applicationSupportDirectory
                        )
                    } catch {
                        Self.logOpenFailure(PersistentStoreOpenFailure(error), attempt: "retry")
                        throw error
                    }
                }
            )
        )
    }

    func bootstrap() -> PersistenceBootstrapResult {
        do {
            return .available(try openRepository())
        } catch {
            let failure = PersistentStoreOpenFailure(error)
            Self.logOpenFailure(failure, attempt: "launch")
            return .recoveryRequired(recoveryContext.recordingOpenFailure(failure))
        }
    }

    private static func logOpenFailure(
        _ failure: PersistentStoreOpenFailure,
        attempt: String
    ) {
        Logger(subsystem: "com.fantomsuj.Perch", category: "persistence").error(
            "Persistent store open failed attempt=\(attempt, privacy: .public) domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)"
        )
    }
}
