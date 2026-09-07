import AppKit
import XCTest
@testable import Flip

@MainActor
final class FlipOverlayPolicyTests: XCTestCase {
    func testOccupancyWindowStaysOnTheTargetSpaceAndDoesNotJoinAllSpaces() {
        let frame = CGRect(x: 80, y: 60, width: 640, height: 480)
        let window = FlipOverlayPolicy.makeWindow(frame: frame)

        XCTAssertTrue(type(of: window) == FlipOccupancyWindow.self)
        XCTAssertEqual(window.styleMask, [.borderless, .resizable])
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(window.frame, frame)
        XCTAssertFalse(window.isVisible)
    }
}

@MainActor
final class FlipWindowListMatchingTests: XCTestCase {
    func testMatchesOnScreenLayerZeroWindowByPIDAndQuartzFrame() {
        let cocoa = CGRect(x: 100, y: 200, width: 400, height: 300)
        let quartz = FlipGeometry.quartzBounds(fromCocoaFrame: cocoa, primaryScreenHeight: 1000)
        let entries = [
            FlipWindowListEntry(
                windowID: 11,
                processIdentifier: 5,
                title: "Notes",
                quartzBounds: quartz,
                layer: 0,
                isOnScreen: true
            ),
            FlipWindowListEntry(
                windowID: 12,
                processIdentifier: 5,
                title: "Overlay",
                quartzBounds: quartz,
                layer: 8,
                isOnScreen: true
            ),
        ]

        let match = FlipWindowListMatching.match(
            processIdentifier: 5,
            cocoaFrame: cocoa,
            primaryScreenHeight: 1000,
            entries: entries
        )
        XCTAssertEqual(match?.windowID, 11)
    }
}

@MainActor
final class FlipApplicationLaunchTests: XCTestCase {
    func testDuplicateLaunchDoesNotConstructComposition() {
        var didConstruct = false
        var didRun = false
        FlipApplicationLaunch.run(
            claimInstance: { nil as NSObject? },
            prepareApplication: {
                didConstruct = true
                return NSObject()
            },
            runApplication: { _, _ in
                didRun = true
            }
        )
        XCTAssertFalse(didConstruct)
        XCTAssertFalse(didRun)
    }

    func testInstanceLockRejectsSecondClaimUntilReleased() throws {
        let lockFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("instance.lock")
        defer {
            try? FileManager.default.removeItem(at: lockFileURL.deletingLastPathComponent())
        }

        var original: FlipInstanceLock? = try XCTUnwrap(FlipInstanceLock.acquire(at: lockFileURL))
        XCTAssertNil(try FlipInstanceLock.acquire(at: lockFileURL))
        original = nil
        XCTAssertNotNil(try FlipInstanceLock.acquire(at: lockFileURL))
    }
}
