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

    func testInteractiveProgressResistsNearThresholdThenSnapsAcrossIt() {
        let beforeResistance = PanelPullRevealPolicy.interactiveProgress(
            forRawProgress: 0.30,
            reducesMotion: false
        )
        let justBelowThreshold = PanelPullRevealPolicy.interactiveProgress(
            forRawProgress: 0.41,
            reducesMotion: false
        )
        let atThreshold = PanelPullRevealPolicy.interactiveProgress(
            forRawProgress: 0.42,
            reducesMotion: false
        )

        XCTAssertEqual(beforeResistance, 0.30, accuracy: 0.0001)
        XCTAssertLessThan(justBelowThreshold, 0.41)
        XCTAssertGreaterThan(atThreshold, justBelowThreshold + 0.04)
        XCTAssertEqual(
            PanelPullRevealPolicy.interactiveProgress(
                forRawProgress: 1,
                reducesMotion: false
            ),
            1,
            accuracy: 0.0001
        )
    }

    func testInteractiveProgressUsesDirectTrackingWhenMotionIsReduced() {
        for rawProgress: CGFloat in [0, 0.3, 0.41, 0.42, 0.8, 1] {
            XCTAssertEqual(
                PanelPullRevealPolicy.interactiveProgress(
                    forRawProgress: rawProgress,
                    reducesMotion: true
                ),
                rawProgress,
                accuracy: 0.0001
            )
        }
    }

    func testThresholdCrossingTriggersFeedbackOnlyWhenMovingInward() {
        XCTAssertTrue(
            PanelPullRevealPolicy.crossedRestoreThreshold(
                from: 0.41,
                to: 0.42
            )
        )
        XCTAssertFalse(
            PanelPullRevealPolicy.crossedRestoreThreshold(
                from: 0.42,
                to: 0.43
            )
        )
        XCTAssertFalse(
            PanelPullRevealPolicy.crossedRestoreThreshold(
                from: 0.43,
                to: 0.41
            )
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
