import XCTest
@testable import NotionPiP

@MainActor
final class PiPChromeViewTests: XCTestCase {
    func testQuickCopyButtonUsesFixedBottomLeftSizingAndAccessibleCopy() {
        XCTAssertEqual(QuickCopyButton.controlSize, 30)
        XCTAssertEqual(QuickCopyButton.edgeInset, 8)
        XCTAssertEqual(
            QuickCopyButton.accessibilityLabel,
            "Turn Quick Copy on or off"
        )
        XCTAssertEqual(
            QuickCopyButton.helpText,
            "Insert selected text from other apps at the saved Notion cursor"
        )
    }

    func testQuickCopyPresentationDistinguishesEverySessionState() {
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .off),
            QuickCopyButtonPresentation(
                systemImage: "text.append",
                statusMessage: nil,
                appearance: .off,
                showsProgress: false
            )
        )
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .armed).statusMessage,
            "Quick Copy on"
        )
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .inserting).showsProgress,
            true
        )
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .permissionNeeded).appearance,
            .permissionNeeded
        )
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .warning("Unsupported")).appearance,
            .warning
        )
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .failed("Stale")).appearance,
            .failed
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

    func testTopControlsAppearOnlyAfterPointerRemainsAtTopEdge() {
        let scheduler = TestTopControlsHoverScheduler()
        let controller = TopControlsHoverController(
            revealDelay: .milliseconds(250),
            scheduler: scheduler.schedule
        )

        controller.setHovering(true)

        XCTAssertFalse(controller.isHovering)
        scheduler.advance(by: .milliseconds(249))
        XCTAssertFalse(controller.isHovering)
        scheduler.advance(by: .milliseconds(1))
        XCTAssertTrue(controller.isHovering)
    }

    func testTopControlsHoverSurfaceExtendsBeyondVisibleToolbar() {
        XCTAssertEqual(PiPChromeView.topControlsHoverOutset, 12)
        XCTAssertEqual(PiPChromeView.topControlsRevealHeight, 8)
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
            revealDelay: .milliseconds(250),
            dismissalDelay: .milliseconds(500),
            scheduler: scheduler.schedule
        )

        controller.setHovering(true)
        scheduler.advance(by: .milliseconds(250))
        controller.setHovering(false)

        scheduler.advance(by: .milliseconds(499))
        XCTAssertTrue(controller.isHovering)
        scheduler.advance(by: .milliseconds(1))
        XCTAssertFalse(controller.isHovering)
    }

    func testTopControlsStayVisibleWhenPointerReentersBeforeDismissal() {
        let scheduler = TestTopControlsHoverScheduler()
        let controller = TopControlsHoverController(
            revealDelay: .milliseconds(250),
            dismissalDelay: .milliseconds(500),
            scheduler: scheduler.schedule
        )

        controller.setHovering(true)
        scheduler.advance(by: .milliseconds(250))
        controller.setHovering(false)
        scheduler.advance(by: .milliseconds(499))
        controller.setHovering(true)
        scheduler.advance(by: .milliseconds(1))

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
