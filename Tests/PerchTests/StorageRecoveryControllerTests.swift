import Foundation
import XCTest
@testable import Perch

@MainActor
final class StorageRecoveryControllerTests: XCTestCase {
    func testArchivePublishesBusyStateBeforeStartingFileOperations() async {
        var archiveStarted = false
        let context = PersistentStoreRecoveryContext(
            archiveStore: {
                archiveStarted = true
                return PersistentStoreArchiveReceipt(
                    destinationDirectory: URL(fileURLWithPath: "/tmp/recovery"),
                    artifactNames: ["Perch.store"]
                )
            },
            revealStore: {}
        )
        let controller = StorageRecoveryController(
            context: context,
            continueWithoutSaving: {},
            requestTermination: {},
            accessibilityAnnouncementPoster: StorageRecoveryAnnouncementSpy()
        )
        controller.requestArchiveConfirmation()

        controller.archiveStoreAndQuit()

        XCTAssertEqual(controller.phase, .archiving)
        XCTAssertFalse(archiveStarted)
        await waitUntilRuntimeCondition { archiveStarted }
    }

    func testArchiveFailureKeepsRecoveryOpenAndAnnouncesRollbackOutcome() async throws {
        var terminationCount = 0
        let announcer = StorageRecoveryAnnouncementSpy()
        let context = PersistentStoreRecoveryContext(
            archiveStore: {
                throw PersistentStoreArchiveError.moveFailed(
                    artifact: "Perch.store-shm",
                    rollbackFailures: ["Perch.store-wal"]
                )
            },
            revealStore: {}
        )
        let controller = StorageRecoveryController(
            context: context,
            continueWithoutSaving: {},
            requestTermination: { terminationCount += 1 },
            accessibilityAnnouncementPoster: announcer
        )

        controller.requestArchiveConfirmation()
        controller.archiveStoreAndQuit()

        await waitUntilRuntimeCondition {
            if case .failed = controller.phase { return true }
            return false
        }

        guard case let .failed(message) = controller.phase else {
            return XCTFail("Expected a recoverable archive failure")
        }
        XCTAssertTrue(message.contains("Perch.store-shm"))
        XCTAssertTrue(message.contains("Perch.store-wal"))
        XCTAssertTrue(message.contains("Reveal Store in Finder"))
        XCTAssertEqual(announcer.messages, [message])
        XCTAssertEqual(terminationCount, 0)
        XCTAssertFalse(controller.isBusy)
    }

    func testArchiveSuccessRequestsTerminationExactlyOnce() async {
        var controller: StorageRecoveryController!
        var phaseDuringArchive: StorageRecoveryPhase?
        var terminationCount = 0
        let receipt = PersistentStoreArchiveReceipt(
            destinationDirectory: URL(fileURLWithPath: "/tmp/recovery"),
            artifactNames: ["Perch.store"]
        )
        let context = PersistentStoreRecoveryContext(
            archiveStore: {
                phaseDuringArchive = controller.phase
                return receipt
            },
            revealStore: {}
        )
        controller = StorageRecoveryController(
            context: context,
            continueWithoutSaving: {},
            requestTermination: { terminationCount += 1 },
            accessibilityAnnouncementPoster: StorageRecoveryAnnouncementSpy()
        )

        controller.requestArchiveConfirmation()
        controller.archiveStoreAndQuit()
        controller.archiveStoreAndQuit()

        await waitUntilRuntimeCondition { terminationCount == 1 }

        XCTAssertEqual(phaseDuringArchive, .archiving)
        XCTAssertEqual(controller.phase, .archiving)
        XCTAssertEqual(terminationCount, 1)
    }
}

@MainActor
final class StorageRecoveryRetryTests: XCTestCase {
    func testSuccessfulRetryOffersQuitAndBlocksArchive() {
        var retryCount = 0
        var terminationCount = 0
        let announcer = StorageRecoveryRetryAnnouncementSpy()
        let controller = StorageRecoveryController(
            context: PersistentStoreRecoveryContext(
                archiveStore: {
                    XCTFail("A store that opens must not be archived")
                    throw PersistentStoreArchiveError.noRecoverableArtifacts
                },
                revealStore: {},
                retryOpenStore: { retryCount += 1 }
            ),
            continueWithoutSaving: {},
            requestTermination: { terminationCount += 1 },
            accessibilityAnnouncementPoster: announcer
        )

        controller.retryOpeningStore()
        controller.requestArchiveConfirmation()

        XCTAssertEqual(retryCount, 1)
        XCTAssertEqual(controller.phase, .storeAvailable)
        XCTAssertEqual(announcer.messages, [StorageRecoveryPresentation.retrySucceededMessage])
        XCTAssertEqual(terminationCount, 0)

        controller.quitToReopen()
        controller.quitToReopen()

        XCTAssertEqual(terminationCount, 1)
    }

    func testFailedRetryShowsErrorCodeAndKeepsArchiveAvailable() {
        let announcer = StorageRecoveryRetryAnnouncementSpy()
        var terminationCount = 0
        let controller = StorageRecoveryController(
            context: PersistentStoreRecoveryContext(
                archiveStore: {
                    PersistentStoreArchiveReceipt(
                        destinationDirectory: URL(fileURLWithPath: "/tmp/recovery"),
                        artifactNames: ["Perch.store"]
                    )
                },
                revealStore: {},
                retryOpenStore: {
                    throw NSError(domain: "PerchTestStoreDomain", code: 256)
                },
                openFailure: PersistentStoreOpenFailure(
                    domain: "PerchTestStoreDomain",
                    code: 256
                )
            ),
            continueWithoutSaving: {},
            requestTermination: { terminationCount += 1 },
            accessibilityAnnouncementPoster: announcer
        )

        controller.retryOpeningStore()

        guard case let .failed(message) = controller.phase else {
            return XCTFail("Expected the retry failure to be shown")
        }
        XCTAssertTrue(message.contains("PerchTestStoreDomain 256"))
        XCTAssertEqual(announcer.messages, [message])
        XCTAssertEqual(controller.openFailureLabel, "PerchTestStoreDomain 256")
        controller.quitToReopen()
        XCTAssertEqual(terminationCount, 0)

        controller.requestArchiveConfirmation()
        XCTAssertEqual(controller.phase, .confirmingArchive)
    }
}

@MainActor
private final class StorageRecoveryRetryAnnouncementSpy: AccessibilityAnnouncementPosting {
    private(set) var messages: [String] = []

    func announce(_ message: String) {
        messages.append(message)
    }
}

@MainActor
private final class StorageRecoveryAnnouncementSpy: AccessibilityAnnouncementPosting {
    private(set) var messages: [String] = []

    func announce(_ message: String) {
        messages.append(message)
    }
}
