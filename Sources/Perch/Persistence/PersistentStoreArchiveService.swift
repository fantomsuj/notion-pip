import Foundation

struct PersistentStoreArchiveService {
    static let artifactNames = [
        "Perch.store",
        "Perch.store-wal",
        "Perch.store-shm",
        "Perch.store-journal",
        "Perch.store_SUPPORT",
    ]

    private let storeDirectory: URL
    private let fileManager: FileManager
    private let clock: any DateProviding
    private let moveItem: (URL, URL) throws -> Void

    init(
        storeDirectory: URL,
        fileManager: FileManager = .default,
        clock: any DateProviding = SystemDateProvider(),
        moveItem: ((URL, URL) throws -> Void)? = nil
    ) {
        self.storeDirectory = storeDirectory
        self.fileManager = fileManager
        self.clock = clock
        self.moveItem = moveItem ?? { source, destination in
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    func recoverableArtifacts() -> [URL] {
        Self.artifactNames.compactMap { name in
            let url = storeDirectory.appendingPathComponent(name)
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }
    }

    func archive() throws -> PersistentStoreArchiveReceipt {
        let artifacts = recoverableArtifacts()
        guard !artifacts.isEmpty else {
            throw PersistentStoreArchiveError.noRecoverableArtifacts
        }
        let recoveryDirectory = storeDirectory.appendingPathComponent(
            "Recovery",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: recoveryDirectory,
            withIntermediateDirectories: true
        )
        let destinationDirectory = nextDestinationDirectory(in: recoveryDirectory)
        try fileManager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: false
        )
        var movedArtifacts: [(source: URL, destination: URL)] = []
        for artifact in artifacts {
            let destination = destinationDirectory.appendingPathComponent(
                artifact.lastPathComponent
            )
            do {
                try moveItem(artifact, destination)
                movedArtifacts.append((source: artifact, destination: destination))
            } catch {
                var rollbackFailures: [String] = []
                for movedArtifact in movedArtifacts.reversed() {
                    do {
                        try moveItem(movedArtifact.destination, movedArtifact.source)
                    } catch {
                        rollbackFailures.append(movedArtifact.source.lastPathComponent)
                    }
                }
                throw PersistentStoreArchiveError.moveFailed(
                    artifact: artifact.lastPathComponent,
                    rollbackFailures: rollbackFailures
                )
            }
        }
        return PersistentStoreArchiveReceipt(
            destinationDirectory: destinationDirectory,
            artifactNames: artifacts.map(\.lastPathComponent)
        )
    }

    private func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func nextDestinationDirectory(in recoveryDirectory: URL) -> URL {
        let baseName = "Perch-store-\(timestamp(for: clock.now()))"
        var candidate = recoveryDirectory.appendingPathComponent(
            baseName,
            isDirectory: true
        )
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = recoveryDirectory.appendingPathComponent(
                "\(baseName)-\(suffix)",
                isDirectory: true
            )
            suffix += 1
        }
        return candidate
    }
}

struct PersistentStoreArchiveReceipt: Equatable {
    let destinationDirectory: URL
    let artifactNames: [String]
}

enum PersistentStoreArchiveError: Error, Equatable {
    case noRecoverableArtifacts
    case moveFailed(artifact: String, rollbackFailures: [String])
}
