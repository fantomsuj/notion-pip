import XCTest
@testable import Perch

final class StatusItemMotionPolicyTests: XCTestCase {
    func testMotionUsesOneBeatAndBecomesAStaticSwapWhenReduced() {
        XCTAssertTrue(StatusItemMotionPolicy.shouldAnimate(reducesMotion: false))
        XCTAssertFalse(StatusItemMotionPolicy.shouldAnimate(reducesMotion: true))
        XCTAssertEqual(StatusItemMotionPolicy.nodOffset(reducesMotion: false), 2)
        XCTAssertEqual(StatusItemMotionPolicy.nodOffset(reducesMotion: true), 0)
        XCTAssertLessThanOrEqual(StatusItemMotionPolicy.morphDuration, 0.12)
        XCTAssertLessThanOrEqual(StatusItemMotionPolicy.nodDuration, 0.02)
    }
}
