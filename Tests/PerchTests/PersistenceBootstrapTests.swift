import XCTest
@testable import Perch

final class PersistenceBootstrapTests: XCTestCase {
    func testTemporaryDirectoryStoreOpenFailureEntersRecoveryWithoutTouchingRealStore() throws {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let blockedStoreDirectory = supportDirectory.appendingPathComponent(
            "com.fantomsuj.Perch"
        )
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: blockedStoreDirectory.path,
                contents: Data("not a directory".utf8)
            )
        )

        let result = PersistenceBootstrapper.live(
            applicationSupportDirectory: supportDirectory
        ).bootstrap()

        guard case .recoveryRequired = result else {
            return XCTFail("Expected the invalid temporary store path to require recovery")
        }
        XCTAssertNil(result.pageRepository)
        XCTAssertEqual(
            result.initialServiceHealth,
            ServiceHealthState(issues: [.persistentStoreUnavailable])
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: blockedStoreDirectory.path))
    }

    func testLiveBootstrapUsesProvidedApplicationSupportDirectory() throws {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        let result = PersistenceBootstrapper.live(
            applicationSupportDirectory: supportDirectory
        ).bootstrap()

        guard case .available = result else {
            return XCTFail("Expected live bootstrap to open a new store")
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: supportDirectory
                    .appendingPathComponent("com.fantomsuj.Perch")
                    .appendingPathComponent("Perch.store")
                    .path
            )
        )
    }

    func testOpenFailureReturnsOnlyRecoveryContextAndDegradedHealth() throws {
        var archiveCount = 0
        var revealCount = 0
        let expectedReceipt = PersistentStoreArchiveReceipt(
            destinationDirectory: URL(fileURLWithPath: "/private/recovery"),
            artifactNames: ["Perch.store"]
        )
        let bootstrapper = PersistenceBootstrapper(
            openRepository: {
                throw PersistenceBootstrapTestError.privateStoreFailure(
                    path: "/Users/someone/Library/Application Support/private"
                )
            },
            recoveryContext: PersistentStoreRecoveryContext(
                archiveStore: {
                    archiveCount += 1
                    return expectedReceipt
                },
                revealStore: { revealCount += 1 }
            )
        )

        let result = bootstrapper.bootstrap()

        guard case let .recoveryRequired(context) = result else {
            return XCTFail("Expected recovery context")
        }
        XCTAssertNil(result.pageRepository)
        XCTAssertEqual(
            result.initialServiceHealth,
            ServiceHealthState(issues: [.persistentStoreUnavailable])
        )
        context.revealStore()
        XCTAssertEqual(try context.archiveStore(), expectedReceipt)
        XCTAssertEqual(revealCount, 1)
        XCTAssertEqual(archiveCount, 1)
    }

    func testSuccessfulOpenReturnsUsableRepositoryAndHealthyState() throws {
        let container = try PerchPersistence.makeContainer(inMemory: true)
        let repository = PageRepository(container: container)
        let bootstrapper = PersistenceBootstrapper(
            openRepository: { repository },
            recoveryContext: PersistentStoreRecoveryContext(
                archiveStore: { throw PersistenceBootstrapTestError.unexpectedArchive },
                revealStore: {}
            )
        )

        let result = bootstrapper.bootstrap()

        guard case let .available(openedRepository) = result else {
            return XCTFail("Expected an available repository")
        }
        XCTAssertTrue(openedRepository === repository)
        XCTAssertEqual(result.initialServiceHealth, .healthy)
        XCTAssertNil(result.recoveryContext)
    }
}

private enum PersistenceBootstrapTestError: Error {
    case unexpectedArchive
    case privateStoreFailure(path: String)
}
