import XCTest
@testable import Perch

final class SpaceTransitionMotionPolicyTests: XCTestCase {
    func testDurationsStayShortAndHintValidityCoversATypicalSpaceSlide() {
        XCTAssertEqual(SpaceTransitionMotionPolicy.departureDuration, 0.14)
        XCTAssertEqual(SpaceTransitionMotionPolicy.arrivalDuration, 0.22)
        XCTAssertEqual(SpaceTransitionMotionPolicy.hintValidity, 0.75)
        XCTAssertEqual(SpaceTransitionMotionPolicy.hintTimeout, 0.8)
        XCTAssertEqual(SpaceTransitionMotionPolicy.travelDistance, 28)
        XCTAssertLessThan(
            SpaceTransitionMotionPolicy.departureDuration,
            SpaceTransitionMotionPolicy.arrivalDuration
        )
    }

    func testArrowKeysAndSwipeDeltasResolveToTheDestinationSpace() {
        XCTAssertEqual(
            SpaceTransitionMotionPolicy.direction(forKeyCode: 123),
            .toLeading
        )
        XCTAssertEqual(
            SpaceTransitionMotionPolicy.direction(forKeyCode: 124),
            .toTrailing
        )
        XCTAssertNil(SpaceTransitionMotionPolicy.direction(forKeyCode: 126))
        XCTAssertEqual(
            SpaceTransitionMotionPolicy.direction(forSwipeDeltaX: 1),
            .toLeading
        )
        XCTAssertEqual(
            SpaceTransitionMotionPolicy.direction(forSwipeDeltaX: -1),
            .toTrailing
        )
        XCTAssertNil(SpaceTransitionMotionPolicy.direction(forSwipeDeltaX: 0))
    }

    func testHintDirectionExpiresAfterTheValidityWindow() {
        let hint = (direction: SpaceTransitionDirection.toTrailing, recordedAt: 1.0)
        XCTAssertEqual(
            SpaceTransitionMotionPolicy.resolvedDirection(hint: hint, now: 1.7),
            .toTrailing
        )
        XCTAssertNil(
            SpaceTransitionMotionPolicy.resolvedDirection(hint: hint, now: 1.76)
        )
        XCTAssertNil(
            SpaceTransitionMotionPolicy.resolvedDirection(hint: nil, now: 1.0)
        )
    }

    func testDepartureTravelsWithTheLeavingSpaceAndArrivalComesFromTheDestination() {
        let trailingOut = SpaceTransitionMotionPolicy.departureFrame(direction: .toTrailing)
        let trailingIn = SpaceTransitionMotionPolicy.arrivalStartFrame(direction: .toTrailing)
        let leadingOut = SpaceTransitionMotionPolicy.departureFrame(direction: .toLeading)
        let dissolve = SpaceTransitionMotionPolicy.departureFrame(direction: nil)

        XCTAssertEqual(trailingOut.opacity, 0)
        XCTAssertEqual(trailingOut.translationX, -28)
        XCTAssertEqual(trailingIn.opacity, 0)
        XCTAssertEqual(trailingIn.translationX, 28)
        XCTAssertEqual(leadingOut.translationX, 28)
        XCTAssertEqual(dissolve.translationX, 0)
        XCTAssertEqual(dissolve.opacity, 0)
        XCTAssertEqual(SpaceTransitionMotionPolicy.restFrame.opacity, 1)
        XCTAssertEqual(SpaceTransitionMotionPolicy.restFrame.translationX, 0)
    }

    func testReduceMotionKeepsTheOverlayFullyVisible() {
        XCTAssertEqual(
            SpaceTransitionMotionPolicy.departureFrame(
                direction: .toTrailing,
                reducesMotion: true
            ),
            SpaceTransitionMotionPolicy.restFrame
        )
        XCTAssertEqual(
            SpaceTransitionMotionPolicy.arrivalStartFrame(
                direction: .toLeading,
                reducesMotion: true
            ),
            SpaceTransitionMotionPolicy.restFrame
        )
    }

    func testGestureHintHidesEarlyAndALaterSpaceChangeShowsAgain() {
        let context = SpaceTransitionContext(
            reducesMotion: false,
            isBusy: false,
            hasVisibleOverlay: true
        )

        let afterHint = SpaceTransitionMotionPolicy.reduce(
            state: .idle,
            signal: .gestureHint(.toTrailing),
            context: context
        )
        XCTAssertEqual(afterHint.state.phase, .hiding)
        XCTAssertEqual(afterHint.command, .hide(.toTrailing))

        let afterSpaceChange = SpaceTransitionMotionPolicy.reduce(
            state: afterHint.state,
            signal: .activeSpaceDidChange(.toTrailing),
            context: context
        )
        XCTAssertTrue(afterSpaceChange.state.spaceDidChange)
        XCTAssertNil(afterSpaceChange.command)

        let afterHide = SpaceTransitionMotionPolicy.reduce(
            state: afterSpaceChange.state,
            signal: .hideCompleted,
            context: context
        )
        XCTAssertEqual(afterHide.state, .idle)
        XCTAssertEqual(afterHide.command, .show(.toTrailing))
    }

    func testSpaceChangeWithoutAHintPlaysACombinedDisappearAndAppear() {
        let result = SpaceTransitionMotionPolicy.reduce(
            state: .idle,
            signal: .activeSpaceDidChange(nil),
            context: SpaceTransitionContext(
                reducesMotion: false,
                isBusy: false,
                hasVisibleOverlay: true
            )
        )

        XCTAssertEqual(result.state, .idle)
        XCTAssertEqual(result.command, .hideThenShow(nil))
    }

    func testFalseAlarmHintRestoresTheOverlayAfterTimeout() {
        let context = SpaceTransitionContext(
            reducesMotion: false,
            isBusy: false,
            hasVisibleOverlay: true
        )
        let hiding = SpaceTransitionState(phase: .hiding, direction: .toLeading)
        let afterTimeout = SpaceTransitionMotionPolicy.reduce(
            state: hiding,
            signal: .hintTimedOut,
            context: context
        )
        XCTAssertTrue(afterTimeout.state.hintDidTimeOut)

        let afterHide = SpaceTransitionMotionPolicy.reduce(
            state: afterTimeout.state,
            signal: .hideCompleted,
            context: context
        )
        XCTAssertEqual(afterHide.command, .show(.toLeading))
        XCTAssertEqual(afterHide.state, .idle)
    }

    func testBusyOrReducedMotionSkipsIdleTransitionsAndCancelsInFlightMotion() {
        let busy = SpaceTransitionContext(
            reducesMotion: false,
            isBusy: true,
            hasVisibleOverlay: true
        )
        let reduced = SpaceTransitionContext(
            reducesMotion: true,
            isBusy: false,
            hasVisibleOverlay: true
        )
        let hidden = SpaceTransitionContext(
            reducesMotion: false,
            isBusy: false,
            hasVisibleOverlay: false
        )

        XCTAssertNil(
            SpaceTransitionMotionPolicy.reduce(
                state: .idle,
                signal: .activeSpaceDidChange(.toTrailing),
                context: busy
            ).command
        )
        XCTAssertNil(
            SpaceTransitionMotionPolicy.reduce(
                state: .idle,
                signal: .gestureHint(.toLeading),
                context: reduced
            ).command
        )
        XCTAssertNil(
            SpaceTransitionMotionPolicy.reduce(
                state: .idle,
                signal: .activeSpaceDidChange(nil),
                context: hidden
            ).command
        )

        let cancelled = SpaceTransitionMotionPolicy.reduce(
            state: SpaceTransitionState(phase: .hidden, direction: .toTrailing),
            signal: .cancelled,
            context: busy
        )
        XCTAssertEqual(cancelled.state, .idle)
        XCTAssertEqual(cancelled.command, .cancel)
    }

    func testHideWithoutASpaceChangeWaitsHiddenUntilTheSpaceChanges() {
        let context = SpaceTransitionContext(
            reducesMotion: false,
            isBusy: false,
            hasVisibleOverlay: true
        )
        let afterHide = SpaceTransitionMotionPolicy.reduce(
            state: SpaceTransitionState(phase: .hiding, direction: .toTrailing),
            signal: .hideCompleted,
            context: context
        )

        XCTAssertEqual(afterHide.state.phase, .hidden)
        XCTAssertNil(afterHide.command)

        let afterChange = SpaceTransitionMotionPolicy.reduce(
            state: afterHide.state,
            signal: .activeSpaceDidChange(.toTrailing),
            context: context
        )
        XCTAssertEqual(afterChange.state, .idle)
        XCTAssertEqual(afterChange.command, .show(.toTrailing))
    }
}
