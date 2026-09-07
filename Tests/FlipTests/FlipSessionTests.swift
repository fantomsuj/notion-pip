import CoreGraphics
import XCTest
@testable import Flip

final class FlipSessionTests: XCTestCase {
    func testCaptureOccupancyAndRestoreClearPairing() {
        var session = FlipSession()
        let target = FlipTestSupport.target()
        session.beginCapture(target: target, parkStrategy: .hide)
        XCTAssertEqual(session.phase, .capturing)
        session.beginFlippingOut()
        session.beginOccupancy()
        session.updateOverlayFrame(CGRect(x: 10, y: 20, width: 500, height: 400))
        XCTAssertEqual(session.pairing?.restoreFrame, CGRect(x: 10, y: 20, width: 500, height: 400))
        session.beginFlippingIn()
        session.completeRestore()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.pairing)
    }

    func testShortcutIsIgnoredWhileAnimating() {
        var session = FlipSession()
        session.beginCapture(target: FlipTestSupport.target(), parkStrategy: .hide)
        XCTAssertFalse(session.canToggle)
        XCTAssertEqual(
            FlipTogglePolicy.decision(
                session: session,
                permissions: FlipPermissionStatus(
                    accessibilityTrusted: true,
                    screenRecordingAllowed: true
                ),
                frontmost: FlipTestSupport.target(),
                currentProcessIdentifier: 1
            ),
            .ignore
        )
    }

    func testToggleAsksForPermissionsThenOccupiesThenRestores() {
        var session = FlipSession()
        let permissionsMissing = FlipPermissionStatus(
            accessibilityTrusted: false,
            screenRecordingAllowed: false
        )
        XCTAssertEqual(
            FlipTogglePolicy.decision(
                session: session,
                permissions: permissionsMissing,
                frontmost: FlipTestSupport.target(),
                currentProcessIdentifier: 1
            ),
            .showPermissions
        )

        let ready = FlipPermissionStatus(
            accessibilityTrusted: true,
            screenRecordingAllowed: true
        )
        XCTAssertEqual(
            FlipTogglePolicy.decision(
                session: session,
                permissions: ready,
                frontmost: FlipTestSupport.target(),
                currentProcessIdentifier: 1
            ),
            .occupy(FlipTestSupport.target())
        )

        session.beginCapture(target: FlipTestSupport.target(), parkStrategy: .hide)
        session.beginFlippingOut()
        session.beginOccupancy()
        guard case let .restore(pairing) = FlipTogglePolicy.decision(
            session: session,
            permissions: ready,
            frontmost: FlipTestSupport.target(processIdentifier: 8),
            currentProcessIdentifier: 1
        ) else {
            return XCTFail("expected restore")
        }
        XCTAssertEqual(pairing.target.windowID, 7)
    }

    func testRejectDoesNotClearOccupyingSession() {
        var session = FlipSession()
        session.beginCapture(target: FlipTestSupport.target(), parkStrategy: .hide)
        session.beginOccupancy()
        session.reject(.alreadyOccupied)
        XCTAssertEqual(session.phase, .occupying)
        XCTAssertNotNil(session.pairing)
    }
}

final class FlipShortcutTests: XCTestCase {
    func testDefaultShortcutIsCommandShiftF() {
        XCTAssertTrue(FlipShortcut.default.isValid)
        XCTAssertEqual(FlipShortcut.default.tutorialDisplayString, "Cmd + Shift + F")
        XCTAssertFalse(FlipShortcut(keyCode: 3, modifiers: 0).isValid)
    }

    func testStoreFallsBackToDefaultWhenPersistedValueIsInvalid() throws {
        let suiteName = "FlipShortcutTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let store = FlipShortcutStore(defaults: defaults)
        defaults.set(
            try JSONEncoder().encode(FlipShortcut(keyCode: 3, modifiers: 0)),
            forKey: FlipShortcutStore.key
        )
        XCTAssertEqual(store.load(), .default)
    }
}

final class FlipPermissionCopyTests: XCTestCase {
    func testMissingPermissionsAndPrototypeCopy() {
        let status = FlipPermissionStatus(
            accessibilityTrusted: false,
            screenRecordingAllowed: true
        )
        XCTAssertEqual(status.missing, [.accessibility])
        XCTAssertFalse(status.isReady)
        XCTAssertTrue(FlipPermissionCopy.detail.contains("does not request Input Monitoring"))
        XCTAssertEqual(FlipPermissionCopy.title(for: .screenRecording), "Screen Recording")
    }
}

final class FlipMotionPolicyTests: XCTestCase {
    func testReducedMotionSkipsCardFlip() {
        XCTAssertTrue(FlipMotionPolicy.shouldUseCardFlip(reducesMotion: false))
        XCTAssertFalse(FlipMotionPolicy.shouldUseCardFlip(reducesMotion: true))
        XCTAssertEqual(FlipMotionPolicy.duration(reducesMotion: true), 0.12)
        XCTAssertEqual(FlipParkPolicy.preferredStrategies, [.hide, .minimize, .moveOffscreen])
    }
}

final class FlipDestinationTests: XCTestCase {
    func testNotionHomeIsHTTPSWithoutCredentials() {
        XCTAssertEqual(FlipDestination.notionHome.scheme, "https")
        XCTAssertEqual(FlipDestination.notionHome.host, "www.notion.so")
        XCTAssertNil(FlipDestination.notionHome.user)
        XCTAssertTrue(FlipNavigationPolicy.allows(FlipDestination.notionHome))
        XCTAssertFalse(FlipNavigationPolicy.allows(URL(string: "http://example.com")!))
        XCTAssertFalse(FlipNavigationPolicy.allows(URL(string: "file:///tmp")!))
        XCTAssertTrue(FlipNavigationPolicy.allows(URL(string: "about:blank")!))
    }
}
