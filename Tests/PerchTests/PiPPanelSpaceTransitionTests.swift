import XCTest
@testable import Perch

@MainActor
final class PiPPanelSpaceTransitionTests: XCTestCase {
    func testVisiblePanelReappearsWhenTheActiveSpaceChanges() throws {
        let harness = try makeVisibleHarness()

        harness.observer.emit(.activeSpaceDidChange(.toTrailing))

        XCTAssertEqual(
            harness.panel.spaceTransitions,
            [.hideThenShow(.toTrailing)]
        )
        XCTAssertTrue(harness.handle.spaceTransitions.isEmpty)
        XCTAssertTrue(harness.panel.isVisible)
    }

    func testStashedHandleReappearsInsteadOfTheOrderedOutPanel() throws {
        let harness = try makeVisibleHarness()
        XCTAssertTrue(
            harness.coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )
        harness.resetRecordedTransitions()

        harness.observer.emit(.activeSpaceDidChange(.toLeading))

        XCTAssertEqual(
            harness.handle.spaceTransitions,
            [.hideThenShow(.toLeading)]
        )
        XCTAssertTrue(harness.panel.spaceTransitions.isEmpty)
    }

    func testControlArrowHintHidesBeforeTheSpaceChangeThenShows() throws {
        let harness = try makeVisibleHarness(defersSpaceTransition: true)

        harness.observer.emit(.gestureHint(.toTrailing))
        XCTAssertEqual(harness.panel.spaceTransitions, [.hide(.toTrailing)])
        XCTAssertEqual(harness.panel.pendingSpaceTransitionCount, 1)

        harness.observer.emit(.activeSpaceDidChange(.toTrailing))
        XCTAssertEqual(harness.panel.spaceTransitions, [.hide(.toTrailing)])

        harness.panel.completeSpaceTransition()
        XCTAssertEqual(
            harness.panel.spaceTransitions,
            [.hide(.toTrailing), .show(.toTrailing)]
        )
    }

    func testReduceMotionDoesNotAnimateTheVisiblePanel() throws {
        let harness = try makeVisibleHarness(reducesMotion: true)

        harness.observer.emit(.activeSpaceDidChange(.toTrailing))

        XCTAssertTrue(harness.panel.spaceTransitions.isEmpty)
        XCTAssertTrue(harness.handle.spaceTransitions.isEmpty)
    }

    func testTrackpadMoveAndStashDismissalSkipSpaceMotion() throws {
        let moving = try makeVisibleHarness()
        moving.panel.isTrackpadMoveActive = true
        moving.observer.emit(.activeSpaceDidChange(nil))
        XCTAssertTrue(moving.panel.spaceTransitions.isEmpty)

        let stashing = try makeVisibleHarness(defersStashDismissal: true)
        XCTAssertTrue(
            stashing.coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )
        stashing.resetRecordedTransitions()
        stashing.observer.emit(.activeSpaceDidChange(.toLeading))
        XCTAssertTrue(stashing.panel.spaceTransitions.isEmpty)
        XCTAssertTrue(stashing.handle.spaceTransitions.isEmpty)
    }

    func testUnavailableOverlayDoesNotAnimate() {
        let panel = SpaceTransitionPanelWindow()
        let observer = FakeSpaceTransitionObserver()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: SpaceTransitionPageLoader(),
            reducesMotion: { false },
            spaceTransitionObserver: observer
        )

        observer.emit(.activeSpaceDidChange(.toTrailing))

        XCTAssertTrue(panel.spaceTransitions.isEmpty)
        XCTAssertNil(coordinator.currentPage)
    }

    func testStashCancelsAnInFlightSpaceTransition() throws {
        let harness = try makeVisibleHarness(defersSpaceTransition: true)
        harness.observer.emit(.activeSpaceDidChange(nil))
        XCTAssertEqual(harness.panel.spaceTransitions, [.hideThenShow(nil)])
        XCTAssertEqual(harness.panel.pendingSpaceTransitionCount, 1)

        XCTAssertTrue(
            harness.coordinator.stash(
                visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
            )
        )

        XCTAssertEqual(harness.panel.pendingSpaceTransitionCount, 0)
        XCTAssertGreaterThanOrEqual(harness.panel.spaceTransitionCancelCount, 1)
    }

    private func makeVisibleHarness(
        reducesMotion: Bool = false,
        defersSpaceTransition: Bool = false,
        defersStashDismissal: Bool = false
    ) throws -> SpaceTransitionPanelHarness {
        let page = try NotionPageReference(
            validating: XCTUnwrap(
                URL(
                    string: "https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef"
                )
            )
        )
        let panel = SpaceTransitionPanelWindow(
            frame: CGRect(x: 620, y: 100, width: 300, height: 400),
            defersSpaceTransition: defersSpaceTransition,
            defersStashDismissal: defersStashDismissal
        )
        let handle = SpaceTransitionStashHandle()
        let observer = FakeSpaceTransitionObserver()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: SpaceTransitionPageLoader(),
            stashHandle: handle,
            reducesMotion: { reducesMotion },
            spaceTransitionObserver: observer
        )
        coordinator.show(page: page)
        panel.resetRecordedTransitions()
        handle.resetRecordedTransitions()
        return SpaceTransitionPanelHarness(
            coordinator: coordinator,
            panel: panel,
            handle: handle,
            observer: observer
        )
    }
}

@MainActor
private struct SpaceTransitionPanelHarness {
    let coordinator: PiPPanelCoordinator
    let panel: SpaceTransitionPanelWindow
    let handle: SpaceTransitionStashHandle
    let observer: FakeSpaceTransitionObserver

    func resetRecordedTransitions() {
        panel.resetRecordedTransitions()
        handle.resetRecordedTransitions()
    }
}

@MainActor
private final class FakeSpaceTransitionObserver: SpaceTransitionObserving {
    private var handler: (@MainActor (SpaceTransitionEvent) -> Void)?

    func start(_ handler: @escaping @MainActor (SpaceTransitionEvent) -> Void) {
        self.handler = handler
    }

    func stop() {
        handler = nil
    }

    func emit(_ event: SpaceTransitionEvent) {
        handler?(event)
    }
}

@MainActor
private final class SpaceTransitionPanelWindow: PiPPanelWindow {
    private(set) var frame: CGRect
    private(set) var isVisible = false
    var isExpanded = false
    var isTrackpadMoveActive = false
    var onClose: (@MainActor () -> Void)?
    private(set) var spaceTransitions: [SpaceTransitionAnimation] = []
    var spaceTransitionCancelCount = 0
    private(set) var pendingSpaceTransitionCount = 0
    private let defersSpaceTransition: Bool
    private let defersStashDismissal: Bool
    private var pendingSpaceTransitionCompletion: (@MainActor () -> Void)?
    private var pendingStashCompletion: (@MainActor () -> Void)?

    init(
        frame: CGRect = .zero,
        defersSpaceTransition: Bool = false,
        defersStashDismissal: Bool = false
    ) {
        self.frame = frame
        self.defersSpaceTransition = defersSpaceTransition
        self.defersStashDismissal = defersStashDismissal
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

    func playSpaceTransition(
        _ animation: SpaceTransitionAnimation,
        completion: @escaping @MainActor () -> Void
    ) {
        spaceTransitions.append(animation)
        guard defersSpaceTransition else {
            completion()
            return
        }
        pendingSpaceTransitionCount += 1
        pendingSpaceTransitionCompletion = completion
    }

    func cancelSpaceTransition() {
        spaceTransitionCancelCount += 1
        pendingSpaceTransitionCompletion = nil
        pendingSpaceTransitionCount = 0
    }

    func completeSpaceTransition() {
        let completion = pendingSpaceTransitionCompletion
        pendingSpaceTransitionCompletion = nil
        pendingSpaceTransitionCount = 0
        completion?()
    }

    func resetRecordedTransitions() {
        spaceTransitions.removeAll()
        spaceTransitionCancelCount = 0
        pendingSpaceTransitionCount = 0
        pendingSpaceTransitionCompletion = nil
    }

    func dismissForStash(
        toward placement: PanelStashPlacement,
        restoring restoreFrame: CGRect,
        completion: @escaping @MainActor () -> Void
    ) {
        guard defersStashDismissal else {
            setFrame(restoreFrame, display: false)
            orderOut()
            completion()
            return
        }
        pendingStashCompletion = completion
    }
}

@MainActor
private final class SpaceTransitionStashHandle: PiPStashHandle {
    private(set) var isVisible = false
    private(set) var spaceTransitions: [SpaceTransitionAnimation] = []
    var spaceTransitionCancelCount = 0

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

    func playSpaceTransition(
        _ animation: SpaceTransitionAnimation,
        completion: @escaping @MainActor () -> Void
    ) {
        spaceTransitions.append(animation)
        completion()
    }

    func cancelSpaceTransition() {
        spaceTransitionCancelCount += 1
    }

    func resetRecordedTransitions() {
        spaceTransitions.removeAll()
        spaceTransitionCancelCount = 0
    }
}

@MainActor
private final class SpaceTransitionPageLoader: NotionPageLoading {
    func activate(page: NotionPageReference) {}

    func reloadPinnedPage(_ page: NotionPageReference) {}

    func panelDidShow() {}

    func panelDidHide() {}
}
