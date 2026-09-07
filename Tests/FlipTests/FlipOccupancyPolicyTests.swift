import CoreGraphics
import XCTest
@testable import Flip

final class FlipGeometryTests: XCTestCase {
    func testQuartzAndCocoaFramesRoundTripOnPrimaryDisplay() {
        let quartz = CGRect(x: 40, y: 80, width: 400, height: 300)
        let cocoa = FlipGeometry.cocoaFrame(fromQuartzBounds: quartz, primaryScreenHeight: 1080)
        let restored = FlipGeometry.quartzBounds(fromCocoaFrame: cocoa, primaryScreenHeight: 1080)

        XCTAssertEqual(cocoa.origin.x, 40)
        XCTAssertEqual(cocoa.origin.y, 700)
        XCTAssertEqual(restored, quartz)
    }

    func testFullScreenDetectionUsesTolerance() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertTrue(
            FlipGeometry.isEffectivelyFullScreen(
                CGRect(x: 1, y: -1, width: 1440, height: 900),
                screenFrame: screen
            )
        )
        XCTAssertFalse(
            FlipGeometry.isEffectivelyFullScreen(
                CGRect(x: 100, y: 80, width: 800, height: 600),
                screenFrame: screen
            )
        )
    }

    func testMinimumOccupiableSizeRejectsTinyWindows() {
        XCTAssertFalse(
            FlipGeometry.isLargeEnoughToOccupy(CGRect(x: 0, y: 0, width: 120, height: 80))
        )
        XCTAssertTrue(
            FlipGeometry.isLargeEnoughToOccupy(CGRect(x: 0, y: 0, width: 320, height: 240))
        )
    }
}

final class FlipOccupancyPolicyTests: XCTestCase {
    private let currentPID: pid_t = 99

    func testAcceptsOrdinaryTitledWindow() {
        let result = FlipOccupancyPolicy.evaluate(
            target: FlipTestSupport.target(),
            session: FlipSession(),
            currentProcessIdentifier: currentPID
        )
        XCTAssertEqual(try result.get().windowID, 7)
    }

    func testRejectsMissingWindow() {
        XCTAssertEqual(
            occupancyError(target: nil),
            .missingWindow
        )
    }

    func testRejectsOwnProcessAndPerchBundles() {
        XCTAssertEqual(
            occupancyError(target: FlipTestSupport.target(processIdentifier: currentPID)),
            .ownProcess
        )
        XCTAssertEqual(
            occupancyError(
                target: FlipTestSupport.target(bundleIdentifier: FlipIdentity.perchBundleIdentifier)
            ),
            .excludedBundle
        )
        XCTAssertEqual(
            occupancyError(
                target: FlipTestSupport.target(bundleIdentifier: FlipIdentity.bundleIdentifier)
            ),
            .excludedBundle
        )
    }

    func testRejectsFullscreenMinimizedOffscreenTinyAndLayeredWindows() {
        XCTAssertEqual(
            occupancyError(target: FlipTestSupport.target(isFullScreen: true)),
            .fullScreen
        )
        XCTAssertEqual(
            occupancyError(target: FlipTestSupport.target(isStageManagerLocked: true)),
            .stageManagerLocked
        )
        XCTAssertEqual(
            occupancyError(target: FlipTestSupport.target(isMinimized: true)),
            .minimized
        )
        XCTAssertEqual(
            occupancyError(target: FlipTestSupport.target(isOnScreen: false)),
            .offscreen
        )
        XCTAssertEqual(
            occupancyError(target: FlipTestSupport.target(layer: 8)),
            .nonStandardLayer
        )
        XCTAssertEqual(
            occupancyError(
                target: FlipTestSupport.target(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
            ),
            .tooSmall
        )
        XCTAssertEqual(
            occupancyError(target: FlipTestSupport.target(windowID: kCGNullWindowID)),
            .missingWindowIdentity
        )
    }

    func testRejectsWhenAlreadyOccupiedOrAnimating() {
        var occupying = FlipSession()
        occupying.beginCapture(target: FlipTestSupport.target(), parkStrategy: .hide)
        occupying.beginFlippingOut()
        occupying.beginOccupancy()
        XCTAssertEqual(
            occupancyError(target: FlipTestSupport.target(), session: occupying),
            .alreadyOccupied
        )

        var animating = FlipSession()
        animating.beginCapture(target: FlipTestSupport.target(), parkStrategy: .hide)
        XCTAssertEqual(
            occupancyError(target: FlipTestSupport.target(), session: animating),
            .animationInFlight
        )
    }

    private func occupancyError(
        target: FlipTarget?,
        session: FlipSession = FlipSession()
    ) -> FlipOccupancyRejection {
        switch FlipOccupancyPolicy.evaluate(
            target: target,
            session: session,
            currentProcessIdentifier: currentPID
        ) {
        case let .failure(error):
            return error
        case .success:
            XCTFail("expected occupancy to fail")
            return .missingWindow
        }
    }
}
