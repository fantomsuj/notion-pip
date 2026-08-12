import Foundation
import XCTest
@testable import Perch

@MainActor
final class ApplicationInstanceTests: XCTestCase {
    func testDuplicateLaunchDoesNotConstructApplicationComposition() {
        var didConstructComposition = false
        var didRunApplication = false

        ApplicationLaunch.run(
            claimInstance: { nil as NSObject? },
            prepareApplication: {
                didConstructComposition = true
                return NSObject()
            },
            runApplication: { _, _ in
                didRunApplication = true
            }
        )

        XCTAssertFalse(didConstructComposition)
        XCTAssertFalse(didRunApplication)
    }

    func testInstanceLockRejectsSecondClaimUntilOriginalLeaseIsReleased() throws {
        let lockFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("instance.lock")
        defer {
            try? FileManager.default.removeItem(
                at: lockFileURL.deletingLastPathComponent()
            )
        }

        var originalLease: ApplicationInstanceLock? = try XCTUnwrap(
            ApplicationInstanceLock.acquire(at: lockFileURL)
        )
        XCTAssertNotNil(originalLease)

        XCTAssertNil(try ApplicationInstanceLock.acquire(at: lockFileURL))

        originalLease = nil
        XCTAssertNotNil(try ApplicationInstanceLock.acquire(at: lockFileURL))
    }

    func testDuplicateClaimActivatesRunningPerchApplication() throws {
        let lockFileURL = makeLockFileURL()
        defer { removeLockDirectory(containing: lockFileURL) }
        let originalLease = try XCTUnwrap(
            ApplicationInstanceLock.acquire(at: lockFileURL)
        )
        var activationCount = 0
        let coordinator = ApplicationInstanceCoordinator(
            currentProcessIdentifier: 200,
            lockFileURL: lockFileURL,
            runningApplications: {
                [
                    RunningApplicationReference(
                        processIdentifier: 100,
                        bundleIdentifier: "com.fantomsuj.Perch",
                        localizedName: "Perch",
                        activate: {
                            activationCount += 1
                            return true
                        }
                    ),
                ]
            }
        )

        XCTAssertNil(try coordinator.claim())
        XCTAssertEqual(activationCount, 1)
        withExtendedLifetime(originalLease) {}
    }

    func testRunningPreLockPerchApplicationPreventsUpgradeLaunch() throws {
        let lockFileURL = makeLockFileURL()
        defer { removeLockDirectory(containing: lockFileURL) }
        var activationCount = 0
        let coordinator = ApplicationInstanceCoordinator(
            currentProcessIdentifier: 200,
            lockFileURL: lockFileURL,
            runningApplications: {
                [
                    RunningApplicationReference(
                        processIdentifier: 100,
                        bundleIdentifier: "com.fantomsuj.Perch",
                        localizedName: "Perch",
                        activate: {
                            activationCount += 1
                            return true
                        }
                    ),
                ]
            }
        )

        XCTAssertNil(try coordinator.claim())
        XCTAssertEqual(activationCount, 1)
        XCTAssertNotNil(try ApplicationInstanceLock.acquire(at: lockFileURL))
    }

    func testLegacyApplicationIsActivatedBeforeTakingPerchLock() throws {
        let lockFileURL = makeLockFileURL()
        defer { removeLockDirectory(containing: lockFileURL) }
        var activationCount = 0
        let coordinator = ApplicationInstanceCoordinator(
            currentProcessIdentifier: 200,
            lockFileURL: lockFileURL,
            runningApplications: {
                [
                    RunningApplicationReference(
                        processIdentifier: 100,
                        bundleIdentifier: "com.fantomsuj.NotionPiP",
                        localizedName: "NotionPiP",
                        activate: {
                            activationCount += 1
                            return true
                        }
                    ),
                ]
            }
        )

        XCTAssertNil(try coordinator.claim())
        XCTAssertEqual(activationCount, 1)
        XCTAssertNotNil(try ApplicationInstanceLock.acquire(at: lockFileURL))
    }

    private func makeLockFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("instance.lock")
    }

    private func removeLockDirectory(containing lockFileURL: URL) {
        try? FileManager.default.removeItem(
            at: lockFileURL.deletingLastPathComponent()
        )
    }
}
