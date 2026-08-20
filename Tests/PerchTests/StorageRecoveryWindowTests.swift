import Foundation
import XCTest
@testable import Perch

@MainActor
final class StorageRecoveryWindowTests: XCTestCase {
    func testClosingRecoveryWindowContinuesWithoutSaving() {
        var continueCount = 0
        let window = HeadlessRecoveryWindow()
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
            closeRequestHandler: controller.continueWithoutSaving,
            windowFactory: { window }
        )
        presenter.show()

        window.requestClose()

        XCTAssertEqual(continueCount, 1)
        XCTAssertFalse(window.isVisible)
    }
}

@MainActor
private final class StorageRecoveryWindowAnnouncementSpy: AccessibilityAnnouncementPosting {
    func announce(_ message: String) {}
}

@MainActor
private final class HeadlessRecoveryWindow: AppWindow {
    private(set) var isVisible = false
    private var closeRequestHandler: (@MainActor () -> Void)?

    func presentAsKey() {
        isVisible = true
    }

    func orderOut() {
        isVisible = false
    }

    func installCloseRequestHandler(_ handler: @escaping @MainActor () -> Void) {
        closeRequestHandler = handler
    }

    func requestClose() {
        closeRequestHandler?()
    }
}
