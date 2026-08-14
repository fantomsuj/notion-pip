import XCTest
@testable import Perch

final class PiPMotionPolicyTests: XCTestCase {
    func testMotionTokensMatchTransitionsDevScale() {
        XCTAssertEqual(MotionTokens.Duration.stagger, 0.040)
        XCTAssertEqual(MotionTokens.Duration.micro, 0.080)
        XCTAssertEqual(MotionTokens.Duration.quick, 0.150)
        XCTAssertEqual(MotionTokens.Duration.fast, 0.250)
        XCTAssertEqual(MotionTokens.Duration.medium, 0.350)
        XCTAssertEqual(MotionTokens.Duration.slow, 0.400)
        XCTAssertEqual(MotionTokens.Duration.verySlow, 0.500)

        XCTAssertEqual(MotionTokens.Distance.micro, 4)
        XCTAssertEqual(MotionTokens.Distance.small, 6)
        XCTAssertEqual(MotionTokens.Distance.base, 8)
        XCTAssertEqual(MotionTokens.Distance.medium, 12)

        XCTAssertEqual(MotionTokens.Scale.medium, 0.97)
        XCTAssertEqual(MotionTokens.Scale.small, 0.98)
        XCTAssertEqual(MotionTokens.Scale.tiny, 0.99)
        XCTAssertEqual(MotionTokens.Scale.iconSwapStart, 0.25)

        XCTAssertEqual(MotionTokens.Blur.small, 2)
        XCTAssertEqual(MotionTokens.Blur.medium, 3)

        XCTAssertEqual(MotionTokens.smoothOutControlPoints.x1, 0.22)
        XCTAssertEqual(MotionTokens.smoothOutControlPoints.y1, 1)
        XCTAssertEqual(MotionTokens.smoothOutControlPoints.x2, 0.36)
        XCTAssertEqual(MotionTokens.smoothOutControlPoints.y2, 1)
    }

    func testReduceMotionDisablesAllTokenAnimations() {
        XCTAssertNil(
            MotionTokens.animation(duration: 0.25, curve: .smoothOut, reducesMotion: true)
        )
        XCTAssertNil(PiPChromeRevealMotion.animation(isAppearing: true, reducesMotion: true))
        XCTAssertNil(StatusBannerMotion.animation(isAppearing: true, reducesMotion: true))
        XCTAssertNil(PageSwitcherDropdownMotion.animation(isAppearing: true, reducesMotion: true))
        XCTAssertNil(IconSwapMotion.animation(reducesMotion: true))
        XCTAssertNil(CornerSelectionMotion.animation(reducesMotion: true))
        XCTAssertNil(ToolbarHoverMotion.animation(isHovering: true, reducesMotion: true))
        XCTAssertNil(TextsRevealMotion.appearAnimation(line: 1, reducesMotion: true))
    }

    func testChromeRevealUsesCompactPanelTravelAndAsymmetricTiming() {
        XCTAssertEqual(PiPChromeRevealMotion.translateY, -MotionTokens.Distance.base)
        XCTAssertEqual(PiPChromeRevealMotion.blurRadius, MotionTokens.Blur.small)
        XCTAssertEqual(PiPChromeRevealMotion.scale, MotionTokens.Scale.small)
        XCTAssertEqual(PiPChromeRevealMotion.appearDuration, MotionTokens.Duration.fast)
        XCTAssertEqual(PiPChromeRevealMotion.dismissDuration, MotionTokens.Duration.quick)
        XCTAssertGreaterThan(
            PiPChromeRevealMotion.appearDuration,
            PiPChromeRevealMotion.dismissDuration
        )
        XCTAssertNotNil(PiPChromeRevealMotion.animation(isAppearing: true, reducesMotion: false))
    }

    func testStatusBannerToastIsAsymmetricAndDropsFromAbove() {
        XCTAssertEqual(StatusBannerMotion.translateY, -MotionTokens.Distance.medium)
        XCTAssertEqual(StatusBannerMotion.scale, MotionTokens.Scale.medium)
        XCTAssertGreaterThan(
            StatusBannerMotion.appearDuration,
            StatusBannerMotion.dismissDuration
        )
    }

    func testDropdownScaleGrowsFromRestAndClosesToTiny() {
        XCTAssertEqual(
            PageSwitcherDropdownMotion.scale(isOpen: false, isClosing: false),
            MotionTokens.Scale.medium
        )
        XCTAssertEqual(
            PageSwitcherDropdownMotion.scale(isOpen: true, isClosing: false),
            1
        )
        XCTAssertEqual(
            PageSwitcherDropdownMotion.scale(isOpen: false, isClosing: true),
            MotionTokens.Scale.tiny
        )
    }

    func testIconSwapHidesInactiveGlyphWithBlurAndScale() {
        XCTAssertEqual(IconSwapMotion.opacity(isActive: true), 1)
        XCTAssertEqual(IconSwapMotion.opacity(isActive: false), 0)
        XCTAssertEqual(
            IconSwapMotion.blurRadius(isActive: false, reducesMotion: false),
            MotionTokens.Blur.small
        )
        XCTAssertEqual(
            IconSwapMotion.scale(isActive: false, reducesMotion: false),
            MotionTokens.Scale.iconSwapStart
        )
        XCTAssertEqual(IconSwapMotion.blurRadius(isActive: false, reducesMotion: true), 0)
        XCTAssertEqual(IconSwapMotion.scale(isActive: false, reducesMotion: true), 1)
        XCTAssertEqual(IconSwapMotion.blurRadius(isActive: true, reducesMotion: false), 0)
        XCTAssertEqual(IconSwapMotion.scale(isActive: true, reducesMotion: false), 1)
    }

    func testReloadGlyphMapsLoadingSuccessAndIdle() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(
            ReloadIconSwapPolicy.glyph(
                sessionState: .loading,
                successHoldExpiresAt: now.addingTimeInterval(1),
                now: now
            ),
            .loading
        )
        XCTAssertEqual(
            ReloadIconSwapPolicy.glyph(
                sessionState: .active,
                successHoldExpiresAt: now.addingTimeInterval(0.4),
                now: now
            ),
            .success
        )
        XCTAssertEqual(
            ReloadIconSwapPolicy.glyph(
                sessionState: .active,
                successHoldExpiresAt: now.addingTimeInterval(-0.01),
                now: now
            ),
            .idle
        )
        XCTAssertEqual(
            ReloadIconSwapPolicy.glyph(
                sessionState: .failed("offline"),
                successHoldExpiresAt: nil,
                now: now
            ),
            .idle
        )
    }

    func testReloadSuccessHoldOnlyStartsAfterPendingLoadCompletes() {
        let now = Date(timeIntervalSince1970: 50)
        XCTAssertEqual(
            ReloadIconSwapPolicy.successHoldExpiresAt(
                isPending: true,
                previousState: .loading,
                currentState: .active,
                reducesMotion: false,
                now: now
            ),
            now.addingTimeInterval(MotionTokens.Duration.verySlow)
        )
        XCTAssertNil(
            ReloadIconSwapPolicy.successHoldExpiresAt(
                isPending: true,
                previousState: .loading,
                currentState: .active,
                reducesMotion: true,
                now: now
            )
        )
        XCTAssertNil(
            ReloadIconSwapPolicy.successHoldExpiresAt(
                isPending: false,
                previousState: .loading,
                currentState: .active,
                reducesMotion: false,
                now: now
            )
        )
    }

    func testErrorShakeFollowsTransitionsDevKeyframeLegs() {
        XCTAssertEqual(ErrorShakeMotion.totalDuration, 0.280, accuracy: 0.0001)
        XCTAssertEqual(ErrorShakeMotion.offset(at: 0, reducesMotion: false), 0)
        XCTAssertEqual(
            ErrorShakeMotion.offset(at: ErrorShakeMotion.segmentA, reducesMotion: false),
            MotionTokens.Distance.small
        )
        XCTAssertEqual(
            ErrorShakeMotion.offset(at: ErrorShakeMotion.segmentA * 2, reducesMotion: false),
            -MotionTokens.Distance.small
        )
        XCTAssertEqual(
            ErrorShakeMotion.offset(
                at: ErrorShakeMotion.segmentA * 2 + ErrorShakeMotion.segmentB,
                reducesMotion: false
            ),
            MotionTokens.Distance.micro
        )
        XCTAssertEqual(
            ErrorShakeMotion.offset(at: ErrorShakeMotion.totalDuration, reducesMotion: false),
            0
        )
        XCTAssertEqual(
            ErrorShakeMotion.offset(at: ErrorShakeMotion.segmentA / 2, reducesMotion: false),
            MotionTokens.Distance.small / 2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ErrorShakeMotion.offset(at: ErrorShakeMotion.segmentA, reducesMotion: true),
            0
        )
    }

    func testTextsRevealStaggersLaterLines() {
        XCTAssertEqual(TextsRevealMotion.appearDelay(forLine: 0), 0)
        XCTAssertEqual(TextsRevealMotion.appearDelay(forLine: 1), MotionTokens.Duration.stagger)
        XCTAssertEqual(TextsRevealMotion.appearDelay(forLine: 2), MotionTokens.Duration.stagger * 2)
    }

    func testHoverReturnUsesBounceWhilePressUsesEaseOut() {
        XCTAssertNotNil(ToolbarHoverMotion.animation(isHovering: true, reducesMotion: false))
        XCTAssertNotNil(ToolbarHoverMotion.animation(isHovering: false, reducesMotion: false))
        XCTAssertEqual(ToolbarHoverMotion.duration, MotionTokens.Duration.quick)
        XCTAssertEqual(ToolbarIconMotionPolicy.hoverDuration, MotionTokens.Duration.quick)
        XCTAssertEqual(ToolbarIconMotionPolicy.reloadDuration, MotionTokens.Duration.fast)
    }

    func testStatusBannerKindPrefersBrowserLoginThenOfflineThenFailedLoad() throws {
        let login = try XCTUnwrap(NotionBrowserLoginPresentation(state: .loginRequired))
        XCTAssertEqual(
            PiPStatusBannerKind(sessionState: .failed("x"), browserLogin: login),
            .browserLogin(login)
        )
        XCTAssertEqual(
            PiPStatusBannerKind(sessionState: .offline, browserLogin: nil),
            .offline
        )
        XCTAssertEqual(
            PiPStatusBannerKind(sessionState: .failed("x"), browserLogin: nil),
            .failedLoad
        )
        XCTAssertNil(PiPStatusBannerKind(sessionState: .active, browserLogin: nil))
        XCTAssertNil(PiPStatusBannerKind(sessionState: .loading, browserLogin: nil))
    }

    func testExistingPanelMotionNowReadsFromMotionTokens() {
        XCTAssertEqual(PanelStashTransition.duration, MotionTokens.Duration.fast)
        XCTAssertEqual(PanelStashTransition.handleSettleDuration, MotionTokens.Duration.quick)
        XCTAssertEqual(StatusItemMotionPolicy.morphDuration, MotionTokens.Duration.micro)
        XCTAssertEqual(CornerSelectionMotion.duration, MotionTokens.Duration.fast)
    }
}
