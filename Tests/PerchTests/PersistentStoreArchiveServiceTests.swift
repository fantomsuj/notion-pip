import Foundation
import XCTest
@testable import Perch

final class PersistentStoreArchiveServiceTests: XCTestCase {
    func testArchiveReportsIncompleteRollbackAndPreservesEveryRemainingCopy() throws {
        let storeDirectory = try makeTemporaryDirectory()
        let artifactNames = [
            "Perch.store",
            "Perch.store-wal",
            "Perch.store-shm",
            "Perch.store-journal",
            "Perch.store_SUPPORT",
        ]
        for name in artifactNames {
            try createArtifact(named: name, in: storeDirectory)
        }
        let service = PersistentStoreArchiveService(
            storeDirectory: storeDirectory,
            clock: FixedArchiveDateProvider(Date(timeIntervalSince1970: 0)),
            moveItem: { source, destination in
                if source.deletingLastPathComponent() == storeDirectory,
                   source.lastPathComponent == "Perch.store-shm"
                {
                    throw ArchiveMoveTestError.injected
                }
                if source.path.contains("/Recovery/"),
                   source.lastPathComponent == "Perch.store-wal"
                {
                    throw ArchiveMoveTestError.injected
                }
                try FileManager.default.moveItem(at: source, to: destination)
            }
        )

        XCTAssertThrowsError(try service.archive()) { error in
            XCTAssertEqual(
                error as? PersistentStoreArchiveError,
                .moveFailed(
                    artifact: "Perch.store-shm",
                    rollbackFailures: ["Perch.store-wal"]
                )
            )
        }

        for name in artifactNames where name != "Perch.store-wal" {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: storeDirectory.appendingPathComponent(name).path
                ),
                "Expected \(name) to remain in the original store directory"
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: storeDirectory.appendingPathComponent("Perch.store-wal").path
            )
        )
        XCTAssertEqual(
            try archivedArtifactNames(
                in: storeDirectory.appendingPathComponent("Recovery")
            ),
            ["Perch.store-wal"]
        )
    }

    func testArchiveRollsBackAfterFirstMiddleAndFinalMoveFailures() throws {
        let artifactNames = [
            "Perch.store",
            "Perch.store-wal",
            "Perch.store-shm",
            "Perch.store-journal",
            "Perch.store_SUPPORT",
        ]

        for failedName in [artifactNames[0], artifactNames[2], artifactNames[4]] {
            let storeDirectory = try makeTemporaryDirectory()
            for name in artifactNames {
                try createArtifact(named: name, in: storeDirectory)
            }
            let service = PersistentStoreArchiveService(
                storeDirectory: storeDirectory,
                clock: FixedArchiveDateProvider(Date(timeIntervalSince1970: 0)),
                moveItem: { source, destination in
                    if source.deletingLastPathComponent() == storeDirectory,
                       source.lastPathComponent == failedName
                    {
                        throw ArchiveMoveTestError.injected
                    }
                    try FileManager.default.moveItem(at: source, to: destination)
                }
            )

            XCTAssertThrowsError(try service.archive()) { error in
                XCTAssertEqual(
                    error as? PersistentStoreArchiveError,
                    .moveFailed(artifact: failedName, rollbackFailures: [])
                )
            }
            for name in artifactNames {
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath: storeDirectory.appendingPathComponent(name).path
                    ),
                    "Expected \(name) to remain at its original location after \(failedName) failed"
                )
            }
            let recoveryDirectory = storeDirectory.appendingPathComponent("Recovery")
            let archivedFiles = try archivedArtifactNames(in: recoveryDirectory)
            XCTAssertTrue(archivedFiles.isEmpty)
        }
    }

    func testArchiveRefusesWhenNoRecoverableArtifactExists() throws {
        let storeDirectory = try makeTemporaryDirectory()
        try createArtifact(named: "instance.lock", in: storeDirectory)
        let service = PersistentStoreArchiveService(storeDirectory: storeDirectory)

        XCTAssertThrowsError(try service.archive()) { error in
            XCTAssertEqual(
                error as? PersistentStoreArchiveError,
                .noRecoverableArtifacts
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: storeDirectory.appendingPathComponent("Recovery").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: storeDirectory.appendingPathComponent("instance.lock").path
            )
        )
    }

    func testArchiveChoosesNextAvailableDestinationWithoutOverwriting() throws {
        let storeDirectory = try makeTemporaryDirectory()
        try createArtifact(named: "Perch.store", in: storeDirectory)
        let recoveryDirectory = storeDirectory.appendingPathComponent(
            "Recovery",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: recoveryDirectory.appendingPathComponent(
                "Perch-store-19700101-000000",
                isDirectory: true
            ),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: recoveryDirectory.appendingPathComponent(
                "Perch-store-19700101-000000-2",
                isDirectory: true
            ),
            withIntermediateDirectories: false
        )
        let service = PersistentStoreArchiveService(
            storeDirectory: storeDirectory,
            clock: FixedArchiveDateProvider(Date(timeIntervalSince1970: 0))
        )

        let receipt = try service.archive()

        XCTAssertEqual(
            receipt.destinationDirectory.lastPathComponent,
            "Perch-store-19700101-000000-3"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: recoveryDirectory
                    .appendingPathComponent("Perch-store-19700101-000000")
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: recoveryDirectory
                    .appendingPathComponent("Perch-store-19700101-000000-2")
                    .path
            )
        )
    }

    func testArchiveMovesEveryArtifactIntoTimestampedRecoveryDirectory() throws {
        let storeDirectory = try makeTemporaryDirectory()
        let expectedNames = [
            "Perch.store",
            "Perch.store-wal",
            "Perch.store-shm",
            "Perch.store-journal",
            "Perch.store_SUPPORT",
        ]
        for name in expectedNames {
            try createArtifact(named: name, in: storeDirectory)
        }
        let service = PersistentStoreArchiveService(
            storeDirectory: storeDirectory,
            clock: FixedArchiveDateProvider(
                Date(timeIntervalSince1970: 0)
            )
        )

        let receipt = try service.archive()

        XCTAssertEqual(
            receipt.destinationDirectory.lastPathComponent,
            "Perch-store-19700101-000000"
        )
        XCTAssertEqual(receipt.artifactNames, expectedNames)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                atPath: receipt.destinationDirectory.path
            ).sorted(),
            expectedNames.sorted()
        )
        for name in expectedNames {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: storeDirectory.appendingPathComponent(name).path
                )
            )
        }
    }

    func testDiscoveryIncludesOnlyNamedStoreArtifacts() throws {
        let storeDirectory = try makeTemporaryDirectory()
        let expectedNames = [
            "Perch.store",
            "Perch.store-wal",
            "Perch.store-shm",
            "Perch.store-journal",
            "Perch.store_SUPPORT",
        ]
        for name in expectedNames {
            try createArtifact(named: name, in: storeDirectory)
        }
        try createArtifact(named: "instance.lock", in: storeDirectory)
        try createArtifact(named: "Perch.store-backup", in: storeDirectory)
        try createArtifact(named: "WebsiteData", in: storeDirectory)
        try FileManager.default.createDirectory(
            at: storeDirectory.appendingPathComponent("Recovery", isDirectory: true),
            withIntermediateDirectories: false
        )

        let service = PersistentStoreArchiveService(storeDirectory: storeDirectory)

        XCTAssertEqual(
            service.recoverableArtifacts().map(\.lastPathComponent),
            expectedNames
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func createArtifact(named name: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(name)
        if name.hasSuffix("_SUPPORT") || name == "WebsiteData" {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } else {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data(name.utf8)))
        }
    }

    private func archivedArtifactNames(in recoveryDirectory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: recoveryDirectory.path) else {
            return []
        }
        let destinations = try FileManager.default.contentsOfDirectory(
            at: recoveryDirectory,
            includingPropertiesForKeys: nil
        )
        return try destinations.flatMap { destination in
            try FileManager.default.contentsOfDirectory(atPath: destination.path)
        }
    }
}

private struct FixedArchiveDateProvider: DateProviding {
    let date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date { date }
}

private enum ArchiveMoveTestError: Error {
    case injected
}
