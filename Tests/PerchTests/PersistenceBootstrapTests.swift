import XCTest
@testable import Perch

final class PersistenceBootstrapTests: XCTestCase {
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
