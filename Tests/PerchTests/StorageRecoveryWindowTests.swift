import AppKit
import Foundation
import XCTest
@testable import Perch

@MainActor
final class StorageRecoveryWindowTests: XCTestCase {
    func testClosingRecoveryWindowContinuesWithoutSaving() throws {
        _ = NSApplication.shared
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        var continueCount = 0
        let context = PersistentStoreRecoveryContext(
            archiveStore: {
                PersistentStoreArchiveReceipt(
                    destinationDirectory: URL(fileURLWithPath: "/tmp/recovery"),
                    artifactNames: ["Perch.store"]
                )
            },
            revealStore: {}
        )
        let controller = StorageRecoveryController(
            context: context,
            continueWithoutSaving: { continueCount += 1 },
            requestTermination: {},
            accessibilityAnnouncementPoster: StorageRecoveryWindowAnnouncementSpy()
        )
        let presenter = AppWindowFactory.makeStorageRecovery(
            controller: controller,
            closeRequestHandler: controller.continueWithoutSaving
        )
        presenter.show()
        let window = try XCTUnwrap(
            NSApp.windows.first {
                !existingWindows.contains(ObjectIdentifier($0))
                    && $0.title == StorageRecoveryPresentation.title
            }
        )

        window.close()

        XCTAssertEqual(continueCount, 1)
        XCTAssertFalse(window.isVisible)
    }
}

@MainActor
private final class StorageRecoveryWindowAnnouncementSpy: AccessibilityAnnouncementPosting {
    func announce(_ message: String) {}
}
