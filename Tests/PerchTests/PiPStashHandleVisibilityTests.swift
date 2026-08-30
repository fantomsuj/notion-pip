import XCTest
@testable import Perch

@MainActor
final class PiPStashHandleVisibilityTests: XCTestCase {
    func testHiddenSettingSuppressesStashHandlePresentation() throws {
        let harness = try makeVisibleHarness()

        harness.coordinator.setStashHandleHidden(true)
        XCTAssertTrue(
            harness.coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )

        XCTAssertFalse(harness.handle.isVisible)
        XCTAssertFalse(harness.panel.isVisible)
    }

    func testHidingAnAlreadyPresentedHandleOrdersItOut() throws {
        let harness = try makeVisibleHarness()
        XCTAssertTrue(
            harness.coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )
        XCTAssertTrue(harness.handle.isVisible)

        harness.coordinator.setStashHandleHidden(true)

        XCTAssertFalse(harness.handle.isVisible)
    }

    func testUnhidingWhileStashedRepresentsTheHandle() throws {
        let harness = try makeVisibleHarness()
        harness.coordinator.setStashHandleHidden(true)
        XCTAssertTrue(
            harness.coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )
        XCTAssertFalse(harness.handle.isVisible)

        harness.coordinator.setStashHandleHidden(false)

        XCTAssertTrue(harness.handle.isVisible)
    }

    private func makeVisibleHarness() throws -> StashVisibilityHarness {
        let page = try NotionPageReference(
            validating: XCTUnwrap(
                URL(
                    string: "https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef"
                )
            )
        )
        let panel = StashVisibilityPanelWindow(
            frame: CGRect(x: 620, y: 100, width: 300, height: 400)
        )
        let handle = StashVisibilityStashHandle()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: StashVisibilityPageLoader(),
            stashHandle: handle,
            reducesMotion: { false }
        )
        coordinator.show(page: page)
        return StashVisibilityHarness(coordinator: coordinator, panel: panel, handle: handle)
    }
}

@MainActor
private struct StashVisibilityHarness {
    let coordinator: PiPPanelCoordinator
    let panel: StashVisibilityPanelWindow
    let handle: StashVisibilityStashHandle
}

private final class StashVisibilityPageLoader: NotionPageLoading {
    func activate(page: NotionPageReference) {}

    func reloadPinnedPage(_ page: NotionPageReference) {}
}

@MainActor
private final class StashVisibilityPanelWindow: PiPPanelWindow {
    private(set) var frame: CGRect
    private(set) var isVisible = false
    var isExpanded = false
    var isTrackpadMoveActive = false
    var onClose: (@MainActor () -> Void)?

    init(frame: CGRect = .zero) {
        self.frame = frame
    }

    func present() {
        isVisible = true
    }

    func orderOut() {
        isVisible = false
    }

    func restoreFromExpandedState() {}

    func setFrame(_ frame: CGRect, display: Bool) {
        self.frame = frame
    }

    func dismissForStash(
        toward placement: PanelStashPlacement,
        restoring restoreFrame: CGRect,
        completion: @escaping @MainActor () -> Void
    ) {
        setFrame(restoreFrame, display: false)
        orderOut()
        completion()
    }
}

@MainActor
private final class StashVisibilityStashHandle: PiPStashHandle {
    private(set) var isVisible = false

    func present(
        placement: PanelStashPlacement,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void,
        onPullRevealChange: @escaping @MainActor (CGFloat) -> Void,
        onPullRevealEnd: @escaping @MainActor (CGFloat) -> Bool
    ) {
        isVisible = true
    }

    func orderOut() {
        isVisible = false
    }
}
