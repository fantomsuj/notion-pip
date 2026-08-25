import XCTest
@testable import Perch

@MainActor
final class PiPChromeViewTests: XCTestCase {
    func testCornerControlsExposeStableOneClickDestinations() {
        XCTAssertEqual(
            PanelCorner.allCases,
            [.topLeft, .topRight, .bottomLeft, .bottomRight]
        )
        XCTAssertEqual(
            PanelCorner.allCases.map(\.symbolName),
            [
                "arrow.up.left",
                "arrow.up.right",
                "arrow.down.left",
                "arrow.down.right",
            ]
        )
        XCTAssertEqual(
            PanelCorner.allCases.map(\.accessibilityLabel),
            [
                "Move Perch to top left",
                "Move Perch to top right",
                "Move Perch to bottom left",
                "Move Perch to bottom right",
            ]
        )
        XCTAssertEqual(PanelCornerControls.minimumHitTarget, 28)
        XCTAssertEqual(
            PanelCornerControls.minimumHitTarget,
            InteractionPolicy.compactHitTarget
        )
        XCTAssertEqual(PanelCornerControls.selectedBackgroundRadius, 4)
    }

    func testTopToolbarRevealsCornerControlsWithEveryOtherAction() {
        XCTAssertEqual(
            PiPChromeView.topToolbarPresentation(
                showsTopControls: false
            ),
            .hidden
        )
        XCTAssertEqual(
            PiPChromeView.topToolbarPresentation(
                showsTopControls: true
            ),
            .expanded
        )
    }

    func testTopToolbarUsesExpandedSizing() {
        XCTAssertEqual(
            PiPChromeView.topControlsHeight,
            TopEdgeTrackpadMoveController.activeHeight
        )
        XCTAssertEqual(PiPChromeView.topControlsSpacing, 4)
        XCTAssertEqual(PanelCornerControls.minimumHitTarget, 28)
    }

    func testToolbarHoverMotionIsLocalDirectionalAndReducedMotionSafe() {
        let resting = ToolbarIconMotionPolicy.transform(
            for: .corner(.topLeft),
            isHovering: false,
            reducesMotion: false
        )
        let topLeft = ToolbarIconMotionPolicy.transform(
            for: .corner(.topLeft),
            isHovering: true,
            reducesMotion: false
        )
        let stash = ToolbarIconMotionPolicy.transform(
            for: .stash,
            isHovering: true,
            reducesMotion: false
        )
        let external = ToolbarIconMotionPolicy.transform(
            for: .external,
            isHovering: true,
            reducesMotion: false
        )
        let reduced = ToolbarIconMotionPolicy.transform(
            for: .stash,
            isHovering: true,
            reducesMotion: true
        )

        XCTAssertEqual(resting, .identity)
        XCTAssertLessThan(topLeft.offset.width, 0)
        XCTAssertLessThan(topLeft.offset.height, 0)
        XCTAssertLessThan(stash.scale, 1)
        XCTAssertGreaterThan(external.offset.width, 0)
        XCTAssertLessThan(external.offset.height, 0)
        XCTAssertEqual(reduced, .identity)
    }

    func testPerchMarkSeparatesOnlyForInteractionWithMotionEnabled() {
        XCTAssertEqual(
            PerchMarkMotionPolicy.separation(isActive: false, reducesMotion: false),
            0
        )
        XCTAssertEqual(
            PerchMarkMotionPolicy.separation(isActive: true, reducesMotion: false),
            1.5
        )
        XCTAssertEqual(
            PerchMarkMotionPolicy.separation(isActive: true, reducesMotion: true),
            0
        )
        XCTAssertEqual(PerchMarkMotionPolicy.duration, 0.12)
    }

    func testReloadMotionRunsOnceOnlyAfterSuccessfulLoadCompletion() {
        XCTAssertTrue(
            ReloadCompletionMotionPolicy.shouldAnimate(
                isPending: true,
                previousState: .loading,
                currentState: .active,
                reducesMotion: false
            )
        )
        XCTAssertFalse(
            ReloadCompletionMotionPolicy.shouldAnimate(
                isPending: false,
                previousState: .loading,
                currentState: .active,
                reducesMotion: false
            )
        )
        XCTAssertFalse(
            ReloadCompletionMotionPolicy.shouldAnimate(
                isPending: true,
                previousState: .loading,
                currentState: .loading,
                reducesMotion: false
            )
        )
        XCTAssertFalse(
            ReloadCompletionMotionPolicy.shouldAnimate(
                isPending: true,
                previousState: .loading,
                currentState: .failed("Network"),
                reducesMotion: false
            )
        )
        XCTAssertFalse(
            ReloadCompletionMotionPolicy.shouldAnimate(
                isPending: true,
                previousState: .loading,
                currentState: .active,
                reducesMotion: true
            )
        )
    }

    func testFailedLoadBannerExposesMessageAndRetryAsSeparateAccessibilityChildren() {
        XCTAssertEqual(
            FailedLoadBannerAccessibilityPresentation.failedLoad.childBehavior,
            .contain
        )
        XCTAssertEqual(
            FailedLoadBannerAccessibilityPresentation.failedLoad.children,
            [
                .message("Notion couldn't load this page."),
                .retryButton("Retry loading Notion page"),
            ]
        )
        XCTAssertEqual(
            FailedLoadBannerAccessibilityPresentation.customPinnedFailedLoad.children,
            [
                .message("This page couldn't load."),
                .retryButton("Retry loading this page"),
            ]
        )
    }

    func testMissingPageChromeExposesANextActionInsteadOfABareEmptyLabel() {
        XCTAssertEqual(
            EmptyPageChromePresentation.missingPage,
            EmptyPageChromePresentation(
                title: "No Notion page is open",
                description: "Open a page from Settings to keep it beside your other work.",
                actionTitle: "Open Settings",
                actionAccessibilityLabel: "Open Settings to choose a Notion page"
            )
        )
    }

    func testContextualPageActionPresentsSlimOpenAndDismissControls() throws {
        let page = try NotionPageReference(
            validating: XCTUnwrap(
                URL(string: "https://www.notion.com/Roadmap-0123456789abcdef0123456789abcdef")
            )
        )

        XCTAssertEqual(
            ContextualPageActionPresentation(
                action: ContextualPageAction(
                    page: page,
                    sourceApplicationName: "Safari"
                )
            ),
            ContextualPageActionPresentation(
                message: "Notion page found in Safari",
                actionTitle: "Open Here",
                actionAccessibilityLabel: "Open the Notion page from Safari in Perch",
                dismissAccessibilityLabel: "Dismiss Open Here"
            )
        )
    }

    func testOpenInNotionAndStashOpensActivePageBeforeStashing() throws {
        let page = try NotionPageReference(
            validating: XCTUnwrap(
                URL(string: "https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef")
            )
        )
        var openedURLs: [URL] = []
        var stashCount = 0
        let session = NotionWebSession(openURL: { openedURLs.append($0) })
        session.activate(page: page)
        let chrome = PiPChromeView(
            webSession: session,
            onStash: {
                XCTAssertEqual(openedURLs, [page.canonicalURL])
                stashCount += 1
            }
        )

        chrome.openInNotionAndStash()

        XCTAssertEqual(stashCount, 1)
    }

    func testTopControlsAppearImmediatelyWhenPointerEntersTopEdge() {
        let controller = TopControlsHoverController()

        controller.setHovering(true)

        XCTAssertTrue(controller.isHovering)
    }

    func testTopControlsHoverSurfaceExtendsBeyondVisibleToolbar() {
        XCTAssertEqual(PiPChromeView.topControlsHoverOutset, 12)
        XCTAssertEqual(PiPChromeView.topControlsRevealHeight, 16)
    }

    func testTopControlsDoNotAppearWhenPointerLeavesBeforeRevealDelay() {
        let scheduler = TestTopControlsHoverScheduler()
        let controller = TopControlsHoverController(
            revealDelay: .milliseconds(250),
            scheduler: scheduler.schedule
        )

        controller.setHovering(true)
        scheduler.advance(by: .milliseconds(249))
        controller.setHovering(false)
        scheduler.advance(by: .milliseconds(1))

        XCTAssertFalse(controller.isHovering)
    }

    func testTopControlsDismissShortlyAfterPointerLeaves() {
        let scheduler = TestTopControlsHoverScheduler()
        let controller = TopControlsHoverController(
            dismissalDelay: .milliseconds(500),
            scheduler: scheduler.schedule
        )

        controller.setHovering(true)
        XCTAssertTrue(controller.isHovering)
        controller.setHovering(false)

        scheduler.advance(by: .milliseconds(499))
        XCTAssertTrue(controller.isHovering)
        scheduler.advance(by: .milliseconds(1))
        XCTAssertFalse(controller.isHovering)
    }

    func testTopControlsStayVisibleWhenPointerReentersBeforeDismissal() {
        let scheduler = TestTopControlsHoverScheduler()
        let controller = TopControlsHoverController(
            dismissalDelay: .milliseconds(500),
            scheduler: scheduler.schedule
        )

        controller.setHovering(true)
        XCTAssertTrue(controller.isHovering)
        controller.setHovering(false)
        scheduler.advance(by: .milliseconds(499))
        controller.setHovering(true)

        XCTAssertTrue(controller.isHovering)
    }

    func testRepinActionInvokesProvidedRecoveryHandler() {
        var invocationCount = 0
        let chrome = PiPChromeView(
            webSession: NotionWebSession(),
            onReloadSavedPin: { invocationCount += 1 }
        )

        chrome.repinCurrentPage()

        XCTAssertEqual(invocationCount, 1)
    }

}

@MainActor
private final class TestTopControlsHoverScheduler {
    private final class CancellationState {
        var isCancelled = false
    }

    private struct ScheduledOperation {
        let deadline: Duration
        let cancellationState: CancellationState
        let operation: @MainActor () -> Void
    }

    private var elapsed: Duration = .zero
    private var scheduledOperations: [ScheduledOperation] = []

    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor () -> Void
    ) -> TopControlsHoverCancellation {
        let cancellationState = CancellationState()
        scheduledOperations.append(
            ScheduledOperation(
                deadline: elapsed + delay,
                cancellationState: cancellationState,
                operation: operation
            )
        )
        return { cancellationState.isCancelled = true }
    }

    func advance(by duration: Duration) {
        elapsed += duration
        let ready = scheduledOperations
            .filter { $0.deadline <= elapsed }
            .sorted { $0.deadline < $1.deadline }
        scheduledOperations.removeAll { $0.deadline <= elapsed }

        for scheduled in ready where !scheduled.cancellationState.isCancelled {
            scheduled.operation()
        }
    }
}
