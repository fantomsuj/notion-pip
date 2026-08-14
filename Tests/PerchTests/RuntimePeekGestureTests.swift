import XCTest
@testable import Perch

@MainActor
final class RuntimePeekGestureTests: XCTestCase {
    func testFirstPressRestoresStashedPanelBeforeDeadline() throws {
        let harness = try makeHarness()

        harness.shortcut.eventHandler?(.pressed)

        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertEqual(harness.panel.shortcutShowCount, 1)
        XCTAssertEqual(harness.scheduler.pendingCount, 1)
        XCTAssertEqual(harness.focus.beginCount, 1)
    }

    func testHoldBeyondDeadlineRestashesOnceOnRelease() throws {
        let harness = try makeHarness()
        harness.shortcut.eventHandler?(.pressed)

        harness.scheduler.fireNext()
        XCTAssertTrue(harness.panel.isVisible)
        harness.shortcut.eventHandler?(.released)

        XCTAssertTrue(harness.panel.isStashed)
        XCTAssertEqual(harness.panel.immediateStashCount, 1)
        XCTAssertEqual(harness.focus.finishCount, 1)
    }

    func testQuickReleaseKeepsPanelVisibleUntilDeadline() throws {
        let harness = try makeHarness()
        harness.shortcut.eventHandler?(.pressed)

        harness.shortcut.eventHandler?(.released)

        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertEqual(harness.panel.immediateStashCount, 0)
        harness.scheduler.fireNext()
        XCTAssertTrue(harness.panel.isStashed)
        XCTAssertEqual(harness.panel.immediateStashCount, 1)
    }

    func testSecondPressLatchesWithoutReloadAndSecondReleaseKeepsVisible() throws {
        let harness = try makeHarness()
        harness.shortcut.eventHandler?(.pressed)
        harness.shortcut.eventHandler?(.released)

        harness.shortcut.eventHandler?(.pressed)

        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertEqual(harness.panel.shortcutShowCount, 1)
        XCTAssertEqual(harness.panel.shownPages.count, 1)
        XCTAssertEqual(harness.announcer.messages, ["Perch will stay open"])
        XCTAssertEqual(harness.focus.cancelCount, 1)

        harness.shortcut.eventHandler?(.released)
        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertEqual(harness.panel.immediateStashCount, 0)
    }

    func testSecondPressAfterDeadlineStartsNewPeek() throws {
        let harness = try makeHarness()
        harness.shortcut.eventHandler?(.pressed)
        harness.shortcut.eventHandler?(.released)
        harness.scheduler.fireNext()

        harness.shortcut.eventHandler?(.pressed)

        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertEqual(harness.panel.shortcutShowCount, 2)
        XCTAssertTrue(harness.announcer.messages.isEmpty)
    }

    func testRepeatedPressWithoutReleaseDoesNotLatch() throws {
        let harness = try makeHarness()
        harness.shortcut.eventHandler?(.pressed)

        harness.shortcut.eventHandler?(.pressed)
        harness.shortcut.eventHandler?(.released)
        harness.scheduler.fireNext()

        XCTAssertTrue(harness.panel.isStashed)
        XCTAssertEqual(harness.panel.shortcutShowCount, 1)
        XCTAssertTrue(harness.announcer.messages.isEmpty)
    }

    func testPressWhileVisibleStashesOnceAndSuppressesRelease() throws {
        let harness = try makeHarness(stashed: false)

        harness.shortcut.eventHandler?(.pressed)
        harness.shortcut.eventHandler?(.released)

        XCTAssertTrue(harness.panel.isStashed)
        XCTAssertEqual(harness.panel.immediateStashCount, 0)
    }

    func testPreferenceChangeCancelsPeekAndRestashesTemporaryPanel() throws {
        let harness = try makeHarness()
        harness.shortcut.eventHandler?(.pressed)

        harness.runtime.setHoldToPeekEnabled(false)

        XCTAssertTrue(harness.panel.isStashed)
        XCTAssertEqual(harness.panel.immediateStashCount, 1)
        XCTAssertEqual(harness.scheduler.pendingCount, 0)
    }

    func testShortcutChangeCancelsPeekAndRestashesTemporaryPanel() throws {
        let harness = try makeHarness()
        harness.shortcut.eventHandler?(.pressed)

        XCTAssertTrue(
            harness.runtime.applyGlobalShortcut(
                GlobalShortcut(
                    keyCode: 0,
                    modifiers: GlobalShortcut.default.modifiers
                )
            )
        )

        XCTAssertTrue(harness.panel.isStashed)
        XCTAssertEqual(harness.panel.immediateStashCount, 1)
        XCTAssertEqual(harness.scheduler.pendingCount, 0)
    }

    func testExternalPersistentShowInvalidatesTimerWithoutBeingHidden() throws {
        let harness = try makeHarness()
        harness.shortcut.eventHandler?(.pressed)
        harness.shortcut.eventHandler?(.released)

        harness.panel.simulateExternalPersistentShow()
        harness.scheduler.fireNext()

        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertEqual(harness.panel.immediateStashCount, 0)
        XCTAssertEqual(harness.focus.cancelCount, 1)
    }

    private func makeHarness(stashed: Bool = true) throws -> Harness {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "RuntimePeekGestureTests.\(UUID().uuidString)")
        )
        let holdToPeekPreferenceStore = HoldToPeekPreferenceStore(defaults: defaults)
        holdToPeekPreferenceStore.save(true)
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let scheduler = RuntimeShortcutGestureScheduler()
        let focus = RuntimePeekFocusRestorer()
        let announcer = RuntimeAccessibilityAnnouncementPoster()
        let runtime = makeRuntime(
            panel: panel,
            shortcutRegistrar: shortcut,
            shortcutGestureScheduler: scheduler,
            accessibilityAnnouncementPoster: announcer,
            holdToPeekPreferenceStore: holdToPeekPreferenceStore,
            peekFocusRestorer: focus
        )
        runtime.activate(
            page: try makePage(id: firstPageID, title: "Peek"),
            source: .typedURL
        )
        if stashed {
            panel.simulateStashedState()
        }
        runtime.start()
        return Harness(
            runtime: runtime,
            panel: panel,
            shortcut: shortcut,
            scheduler: scheduler,
            focus: focus,
            announcer: announcer
        )
    }
}

@MainActor
private struct Harness {
    let runtime: AppRuntime
    let panel: RuntimePanelCoordinator
    let shortcut: RuntimeShortcutRegistrar
    let scheduler: RuntimeShortcutGestureScheduler
    let focus: RuntimePeekFocusRestorer
    let announcer: RuntimeAccessibilityAnnouncementPoster
}
