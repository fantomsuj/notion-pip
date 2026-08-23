import Foundation

struct PersistentStoreRecoveryContext {
    private let archiveStoreAction: () throws -> PersistentStoreArchiveReceipt
    private let revealStoreAction: () -> Void

    init(
        archiveStore: @escaping () throws -> PersistentStoreArchiveReceipt,
        revealStore: @escaping () -> Void
    ) {
        archiveStoreAction = archiveStore
        revealStoreAction = revealStore
    }

    func archiveStore() throws -> PersistentStoreArchiveReceipt {
        try archiveStoreAction()
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
                revealStore: revealer.revealStore
            )
        )
    }

    func bootstrap() -> PersistenceBootstrapResult {
        do {
            return .available(try openRepository())
        } catch {
            return .recoveryRequired(recoveryContext)
        }
    }
}
