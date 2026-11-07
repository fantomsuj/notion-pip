import CoreGraphics
import XCTest
@testable import Perch

final class CursorShakeDetectorTests: XCTestCase {
    func testQuickBackAndForthShakeIsDetectedOnce() {
        var detector = CursorShakeDetector()
        let xs: [CGFloat] = [0, 60, 0, 60, 0, 60, 0]
        var shakes = 0
        for (index, x) in xs.enumerated() {
            if detector.record(CGPoint(x: x, y: 100), at: Double(index) * 0.08) {
                shakes += 1
            }
        }
        XCTAssertEqual(shakes, 1)
    }

    func testVerticalShakeCounts() {
        var detector = CursorShakeDetector()
        let ys: [CGFloat] = [0, 50, 0, 50, 0, 50]
        let detected = ys.enumerated().contains { index, y in
            detector.record(CGPoint(x: 10, y: y), at: Double(index) * 0.1)
        }
        XCTAssertTrue(detected)
    }

    func testSmallJitterIsNotAShake() {
        var detector = CursorShakeDetector()
        for index in 0 ..< 40 {
            let x: CGFloat = index.isMultiple(of: 2) ? 0 : 12
            XCTAssertFalse(detector.record(CGPoint(x: x, y: 0), at: Double(index) * 0.03))
        }
    }

    func testSlowBackAndForthIsNotAShake() {
        var detector = CursorShakeDetector()
        let xs: [CGFloat] = [0, 80, 0, 80, 0, 80, 0]
        for (index, x) in xs.enumerated() {
            XCTAssertFalse(detector.record(CGPoint(x: x, y: 0), at: Double(index) * 0.5))
        }
    }

    func testOrdinaryPointingAcrossTheScreenIsNotAShake() {
        var detector = CursorShakeDetector()
        for index in 0 ..< 60 {
            let point = CGPoint(x: CGFloat(index) * 20, y: CGFloat(index) * 5)
            XCTAssertFalse(detector.record(point, at: Double(index) * 0.016))
        }
    }

    func testResetForgetsEarlierReversals() {
        var detector = CursorShakeDetector()
        let xs: [CGFloat] = [0, 60, 0, 60]
        for (index, x) in xs.enumerated() {
            XCTAssertFalse(detector.record(CGPoint(x: x, y: 0), at: Double(index) * 0.08))
        }
        detector.reset()
        XCTAssertFalse(detector.record(CGPoint(x: 0, y: 0), at: 0.4))
        XCTAssertFalse(detector.record(CGPoint(x: 60, y: 0), at: 0.48))
    }
}
