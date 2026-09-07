import AppKit
import Darwin
import Foundation

enum FlipInstanceLockError: Error, Equatable {
    case unableToOpenLockFile(Int32)
}

final class FlipInstanceLock {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        _ = Darwin.close(fileDescriptor)
    }

    static func acquire(at lockFileURL: URL) throws -> FlipInstanceLock? {
        try FileManager.default.createDirectory(
            at: lockFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let fileDescriptor = lockFileURL.path.withCString { path in
            Darwin.open(
                path,
                O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_EXLOCK | O_NONBLOCK,
                S_IRUSR | S_IWUSR
            )
        }
        guard fileDescriptor >= 0 else {
            let openError = errno
            if openError == EWOULDBLOCK {
                return nil
            }
            throw FlipInstanceLockError.unableToOpenLockFile(openError)
        }

        return FlipInstanceLock(fileDescriptor: fileDescriptor)
    }
}

@MainActor
struct RunningFlipApplicationReference {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    private let activation: @MainActor () -> Bool

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        activate: @escaping @MainActor () -> Bool
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        activation = activate
    }

    @discardableResult
    func activate() -> Bool {
        activation()
    }
}

@MainActor
final class FlipApplicationInstanceCoordinator {
    nonisolated static var defaultApplicationSupportDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(FlipIdentity.bundleIdentifier, isDirectory: true)
    }

    nonisolated static var defaultLockFileURL: URL {
        defaultApplicationSupportDirectoryURL.appendingPathComponent("instance.lock")
    }

    private let currentProcessIdentifier: pid_t
    private let lockFileURL: URL
    private let runningApplications: @MainActor () -> [RunningFlipApplicationReference]

    init(
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        lockFileURL: URL = FlipApplicationInstanceCoordinator.defaultLockFileURL,
        runningApplications: @escaping @MainActor () -> [RunningFlipApplicationReference] = {
            NSWorkspace.shared.runningApplications.map { application in
                RunningFlipApplicationReference(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: application.bundleIdentifier,
                    activate: {
                        application.activate(options: [.activateAllWindows])
                    }
                )
            }
        }
    ) {
        self.currentProcessIdentifier = currentProcessIdentifier
        self.lockFileURL = lockFileURL
        self.runningApplications = runningApplications
    }

    func claim() throws -> FlipInstanceLock? {
        if activateFirstMatching() {
            return nil
        }
        guard let instanceLock = try FlipInstanceLock.acquire(at: lockFileURL) else {
            _ = activateFirstMatching()
            return nil
        }
        return instanceLock
    }

    private func activateFirstMatching() -> Bool {
        runningApplications().contains { application in
            application.processIdentifier != currentProcessIdentifier
                && application.bundleIdentifier == FlipIdentity.bundleIdentifier
                && application.activate()
        }
    }
}

@MainActor
enum FlipApplicationLaunch {
    static func run<InstanceLease, PreparedApplication>(
        claimInstance: () throws -> InstanceLease?,
        prepareApplication: () -> PreparedApplication,
        runApplication: (PreparedApplication, InstanceLease) -> Void
    ) rethrows {
        guard let instanceLease = try claimInstance() else { return }
        let preparedApplication = prepareApplication()
        withExtendedLifetime((instanceLease, preparedApplication)) {
            runApplication(preparedApplication, instanceLease)
        }
    }
}
