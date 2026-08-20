import XCTest
@testable import Perch

@MainActor
final class RuntimeStatusItemAppearanceTests: XCTestCase {
    func testGlyphTracksPresentationAndPrefersSignInOverLoading() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)

        XCTAssertEqual(runtime.statusItemGlyph, .stashed)

        runtime.activate(
            page: try makePage(id: firstPageID, title: "Roadmap"),
            source: .typedURL
        )
        XCTAssertEqual(runtime.statusItemGlyph, .visible)

        panel.simulateStashedState()
        XCTAssertEqual(runtime.statusItemGlyph, .stashed)

        runtime.publishStatusItemSession(sessionState: .loading, loginState: .idle)
        XCTAssertEqual(runtime.statusItemGlyph, .loading)

        runtime.publishStatusItemSession(
            sessionState: .loading,
            loginState: .loginRequired
        )
        XCTAssertEqual(runtime.statusItemGlyph, .needsSignIn)
    }

    func testShortcutPressAcknowledgesSummonBeforeShowingThePanel() throws {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let runtime = makeRuntime(panel: panel, shortcutRegistrar: shortcut)
        runtime.activate(
            page: try makePage(id: firstPageID, title: "Roadmap"),
            source: .typedURL
        )
        panel.simulateStashedState()
        runtime.start()

        let generation = runtime.statusItemSummonGeneration
        shortcut.eventHandler?(.pressed)

        XCTAssertEqual(runtime.statusItemSummonGeneration, generation + 1)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(runtime.statusItemGlyph, .visible)
    }

    func testStatusItemPeekCommitsOnReleaseInsideAndCancelsOutside() throws {
        let harness = try makePeekHarness()

        XCTAssertTrue(harness.runtime.beginStatusItemPeek())
        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertEqual(harness.focus.beginCount, 1)
        XCTAssertNotEqual(harness.runtime.statusItemPeekState, .idle)

        harness.runtime.commitStatusItemPeek()
        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertEqual(harness.panel.immediateStashCount, 0)
        XCTAssertEqual(harness.focus.cancelCount, 1)
        XCTAssertEqual(harness.announcer.messages, ["Perch will stay open"])
        XCTAssertEqual(harness.runtime.statusItemPeekState, .idle)

        harness.panel.simulateStashedState()
        XCTAssertTrue(harness.runtime.beginStatusItemPeek())
        harness.runtime.cancelStatusItemPeek()
        XCTAssertTrue(harness.panel.isStashed)
        XCTAssertEqual(harness.panel.immediateStashCount, 1)
        XCTAssertEqual(harness.focus.finishCount, 1)
    }

    func testStatusItemPeekRequestsContextBeforeRevealingPanel() throws {
        let harness = try makePeekHarness()
        var contextualRevealCount = 0
        harness.runtime.bindContextualRevealHandler { fallback in
            XCTAssertNil(fallback)
            contextualRevealCount += 1
        }

        XCTAssertTrue(harness.runtime.beginStatusItemPeek())

        XCTAssertEqual(contextualRevealCount, 1)
        XCTAssertEqual(harness.panel.willRevealCount, 1)
        XCTAssertTrue(harness.panel.isVisible)
    }

    func testStatusItemPeekDoesNotRunWhenPanelIsVisibleOrUnavailable() throws {
        let visible = try makePeekHarness(stashed: false)
        XCTAssertFalse(visible.runtime.beginStatusItemPeek())
        XCTAssertEqual(visible.focus.beginCount, 0)

        let empty = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: empty)
        XCTAssertFalse(runtime.beginStatusItemPeek())
        XCTAssertEqual(runtime.statusItemPeekState, .idle)
    }

    func testShortcutPressCancelsStatusItemPeekWithoutRestashingFirst() throws {
        let harness = try makePeekHarness()
        XCTAssertTrue(harness.runtime.beginStatusItemPeek())

        harness.shortcut.eventHandler?(.pressed)

        XCTAssertTrue(harness.panel.isStashed)
        XCTAssertEqual(harness.runtime.statusItemPeekState, .idle)
        XCTAssertEqual(harness.runtime.statusItemSummonGeneration, 1)
    }

    private func makePeekHarness(stashed: Bool = true) throws -> AppearanceHarness {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let focus = RuntimePeekFocusRestorer()
        let announcer = RuntimeAccessibilityAnnouncementPoster()
        let runtime = makeRuntime(
            panel: panel,
            shortcutRegistrar: shortcut,
            accessibilityAnnouncementPoster: announcer,
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
        return AppearanceHarness(
            runtime: runtime,
            panel: panel,
            shortcut: shortcut,
            focus: focus,
            announcer: announcer
        )
    }
}

@MainActor
private struct AppearanceHarness {
    let runtime: AppRuntime
    let panel: RuntimePanelCoordinator
    let shortcut: RuntimeShortcutRegistrar
    let focus: RuntimePeekFocusRestorer
    let announcer: RuntimeAccessibilityAnnouncementPoster
}
