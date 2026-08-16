import XCTest
@testable import Perch

final class InteractionPolicyTests: XCTestCase {
    func testPressFeedbackUsesANamedScaleInTheCheatSheetRange() {
        XCTAssertGreaterThanOrEqual(InteractionPolicy.pressedScale, 0.95)
        XCTAssertLessThanOrEqual(InteractionPolicy.pressedScale, 0.98)
        XCTAssertEqual(InteractionPolicy.pressDuration, 0.2)
        XCTAssertEqual(
            InteractionPolicy.pressScale(isPressed: true, reducesMotion: false),
            InteractionPolicy.pressedScale
        )
        XCTAssertEqual(
            InteractionPolicy.pressScale(isPressed: true, reducesMotion: true),
            1
        )
        XCTAssertEqual(
            InteractionPolicy.pressScale(isPressed: false, reducesMotion: false),
            1
        )
    }

    func testIconCrossfadeEntersFromASmallBlurredTransparentState() {
        let hidden = InteractionPolicy.iconCrossfadeFrame(
            isVisible: false,
            reducesMotion: false
        )
        let visible = InteractionPolicy.iconCrossfadeFrame(
            isVisible: true,
            reducesMotion: false
        )
        let reduced = InteractionPolicy.iconCrossfadeFrame(
            isVisible: false,
            reducesMotion: true
        )

        XCTAssertEqual(hidden.scale, 0.25)
        XCTAssertEqual(hidden.opacity, 0)
        XCTAssertEqual(hidden.blurRadius, 4)
        XCTAssertEqual(visible, InteractionPolicy.iconCrossfadeIdentity)
        XCTAssertEqual(reduced.scale, 1)
        XCTAssertEqual(reduced.opacity, 0)
        XCTAssertEqual(reduced.blurRadius, 0)
        XCTAssertEqual(InteractionPolicy.iconCrossfadeDuration, 0.2)
    }

    func testHitTargetsStayAtLeastTwentyFourPointsAndPreferDesktopSize() {
        XCTAssertEqual(InteractionPolicy.minimumHitTarget, 24)
        XCTAssertEqual(InteractionPolicy.preferredHitTarget, 40)
        XCTAssertGreaterThanOrEqual(
            InteractionPolicy.compactHitTarget,
            InteractionPolicy.minimumHitTarget
        )
        XCTAssertEqual(
            PanelCornerControls.minimumHitTarget,
            InteractionPolicy.compactHitTarget
        )
        XCTAssertGreaterThanOrEqual(
            QuickCopyButton.controlSize,
            InteractionPolicy.minimumHitTarget
        )
    }

    func testNestedRadiiStayConcentricWithTheirOuterContainer() {
        XCTAssertEqual(
            InteractionPolicy.concentricRadius(outer: 8, inset: 4),
            4
        )
        XCTAssertEqual(
            InteractionPolicy.concentricRadius(outer: 8, inset: 16),
            0
        )
        XCTAssertEqual(
            PanelCornerControls.selectedBackgroundRadius,
            4
        )
    }

    func testGroupSpacingIsAtLeastTwiceTheInnerSpacing() {
        XCTAssertEqual(InteractionPolicy.groupSpacing(innerSpacing: 8), 16)
        XCTAssertEqual(
            InteractionPolicy.groupSpacing(innerSpacing: DesignTokens.Spacing.control),
            DesignTokens.Spacing.container
        )
    }

    func testStagedEntranceStaggersByOneHundredMillisecondsAndCollapsesForReducedMotion() {
        XCTAssertEqual(InteractionPolicy.staggerInterval, 0.1)
        XCTAssertEqual(
            InteractionPolicy.entranceDelay(for: 2, reducesMotion: false),
            0.2
        )
        XCTAssertEqual(
            InteractionPolicy.entranceDelay(for: 2, reducesMotion: true),
            0
        )
        XCTAssertEqual(
            InteractionPolicy.entranceOffset(hasAppeared: false, reducesMotion: false),
            8
        )
        XCTAssertEqual(
            InteractionPolicy.entranceOffset(hasAppeared: false, reducesMotion: true),
            0
        )
        XCTAssertEqual(
            InteractionPolicy.entranceOpacity(hasAppeared: false, reducesMotion: false),
            0
        )
        XCTAssertEqual(
            InteractionPolicy.entranceOpacity(hasAppeared: true, reducesMotion: false),
            1
        )
    }

    func testHighFrequencyHoverAndThemeChangesDoNotAnimate() {
        XCTAssertFalse(InteractionPolicy.animationForListHoverColor())
        XCTAssertFalse(InteractionPolicy.animationForColorSchemeChange())
    }
}

final class EmptyStateCopyTests: XCTestCase {
    func testPageSwitcherEmptyStateOffersAClearSearchActionForFailedQueries() {
        XCTAssertEqual(
            PageSwitcherEmptyState(query: ""),
            PageSwitcherEmptyState(
                title: "No pages yet",
                systemImage: "doc.text.magnifyingglass",
                description: "Open a Notion page in Perch to see it here.",
                actionTitle: nil
            )
        )
        XCTAssertEqual(
            PageSwitcherEmptyState(query: "  roadmap  ").actionTitle,
            "Clear search"
        )
        XCTAssertNil(PageSwitcherEmptyState(query: "   ").actionTitle)
        XCTAssertEqual(
            PageSwitcherEmptyState(query: "roadmap").title,
            "No matching pages"
        )
    }

    func testMissingPageChromeOffersOpenSettingsAsTheNextAction() {
        XCTAssertEqual(
            EmptyPageChromePresentation.missingPage.actionTitle,
            "Open Settings"
        )
        XCTAssertEqual(
            EmptyPageChromePresentation.missingPage.title,
            "No Notion page is open"
        )
        XCTAssertTrue(
            EmptyPageChromePresentation.missingPage.description.contains("your")
        )
    }
}
