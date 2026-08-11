import CoreGraphics
import XCTest

@testable import Perch

final class PanelPullRevealPolicyTests: XCTestCase {
    func testInwardDistanceRespectsStashedEdge() {
        XCTAssertEqual(
            PanelPullRevealPolicy.inwardDistance(forHorizontalDelta: 80, side: .left),
            80
        )
        XCTAssertEqual(
            PanelPullRevealPolicy.inwardDistance(forHorizontalDelta: -80, side: .right),
            80
        )
        XCTAssertEqual(
            PanelPullRevealPolicy.inwardDistance(forHorizontalDelta: -80, side: .left),
            0
        )
    }

    func testProgressClampsAndThresholdRequiresIntentionalPull() {
        XCTAssertEqual(
            PanelPullRevealPolicy.progress(forInwardDistance: -10, panelWidth: 480),
            0
        )
        XCTAssertFalse(PanelPullRevealPolicy.shouldRestore(progress: 0.41))
        XCTAssertTrue(PanelPullRevealPolicy.shouldRestore(progress: 0.42))
        XCTAssertEqual(
            PanelPullRevealPolicy.progress(forInwardDistance: 500, panelWidth: 480),
            1
        )
    }

    func testHiddenAndInterpolatedFramesRevealFromEitherDisplayEdge() {
        let display = CGRect(x: 100, y: 20, width: 1_000, height: 780)
        let visible = CGRect(x: 624, y: 120, width: 452, height: 640)
        let leftHidden = PanelPullRevealPolicy.hiddenFrame(
            for: visible,
            beyond: .left,
            displayFrame: display
        )
        let rightHidden = PanelPullRevealPolicy.hiddenFrame(
            for: visible,
            beyond: .right,
            displayFrame: display
        )

        XCTAssertEqual(leftHidden.maxX, display.minX)
        XCTAssertEqual(rightHidden.minX, display.maxX)
        XCTAssertEqual(
            PanelPullRevealPolicy.interpolatedFrame(
                from: leftHidden,
                to: visible,
                progress: 0.5
            ).midX,
            (leftHidden.midX + visible.midX) / 2
        )
    }
}
