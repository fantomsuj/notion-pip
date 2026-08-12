import AppKit
import Darwin
import Foundation

@MainActor
struct RunningApplicationReference {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
    private let activation: @MainActor () -> Bool

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        localizedName: String?,
        activate: @escaping @MainActor () -> Bool
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        activation = activate
    }

    @discardableResult
    func activate() -> Bool {
        activation()
    }
}

@MainActor
final class ApplicationInstanceCoordinator {
    static let currentBundleIdentifier = "com.fantomsuj.Perch"
    static let legacyBundleIdentifier = "com.fantomsuj.NotionPiP"

    // This explicit user-home path is shared by signed and ad-hoc builds from
    // every worktree, unlike a bundle-identity-specific sandbox container.
    static var defaultLockFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(currentBundleIdentifier, isDirectory: true)
            .appendingPathComponent("instance.lock")
    }

    private let currentProcessIdentifier: pid_t
    private let lockFileURL: URL
    private let runningApplications: @MainActor () -> [RunningApplicationReference]

    init(
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        lockFileURL: URL = ApplicationInstanceCoordinator.defaultLockFileURL,
        runningApplications: @escaping @MainActor () -> [RunningApplicationReference] = {
            NSWorkspace.shared.runningApplications.map { application in
                RunningApplicationReference(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: application.bundleIdentifier,
                    localizedName: application.localizedName,
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

    func claim() throws -> ApplicationInstanceLock? {
        if activateFirstApplication(where: Self.isCurrentOrLegacyApplication) {
            return nil
        }

        guard let instanceLock = try ApplicationInstanceLock.acquire(at: lockFileURL) else {
            _ = activateFirstApplication(where: Self.isCurrentOrLegacyApplication)
            return nil
        }
        return instanceLock
    }

    private func activateFirstApplication(
        where predicate: (RunningApplicationReference) -> Bool
    ) -> Bool {
        guard let application = runningApplications().first(where: {
            $0.processIdentifier != currentProcessIdentifier && predicate($0)
        }) else {
            return false
        }
        _ = application.activate()
        return true
    }

    private static func isCurrentOrLegacyApplication(
        _ application: RunningApplicationReference
    ) -> Bool {
        if let bundleIdentifier = application.bundleIdentifier {
            return bundleIdentifier == currentBundleIdentifier
                || bundleIdentifier == legacyBundleIdentifier
        }
        return application.localizedName == "Perch"
            || application.localizedName == "NotionPiP"
    }
}
