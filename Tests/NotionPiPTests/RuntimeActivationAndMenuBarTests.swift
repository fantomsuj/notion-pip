import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class RuntimeActivationAndMenuBarTests: XCTestCase {
    func testPageSwitcherActivationUsesUnifiedRuntimePathAndSource() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let page = try makePage(id: firstPageID, title: "Switcher")

        runtime.activate(page: page, source: .pageSwitcher)
        try await repository.waitUntilSaveCount(1)

        XCTAssertEqual(panel.currentPage, page)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(runtime.activePage, page)
        XCTAssertEqual(runtime.lastActivationSource, .pageSwitcher)
        let savedPageIDs = await repository.savedPageIDs()
        XCTAssertEqual(savedPageIDs, [page.pageID])
    }

    func testTypedURLActivationUsesUnifiedRuntimePath() {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)

        runtime.pageURLText = "https://www.notion.so/Roadmap-\(firstPageID)"
        runtime.validatePageURL()

        XCTAssertEqual(runtime.activePage?.pageID, firstPageID)
        XCTAssertEqual(runtime.lastActivationSource, .typedURL)
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
    }

    func testShortcutRestoresStashedPinnedPanelWithoutRepinningOrReadingPasteboard() throws {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let pasteboard = RuntimePasteboard(
            value: "https://www.notion.so/Notes-\(secondPageID)"
        )
        let presenter = RuntimePageURLInputPresenter()
        let runtime = makeRuntime(
            panel: panel,
            pasteboard: pasteboard,
            shortcutRegistrar: shortcut,
            pageURLInputPresenter: presenter
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)
        panel.simulateStashedState()
        runtime.start()

        shortcut.handler?()

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.currentPage, page)
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
        XCTAssertEqual(pasteboard.readCount, 0)
        XCTAssertEqual(presenter.presentAndFocusCount, 0)
    }

    func testShortcutStashesVisiblePinnedPanel() throws {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let pasteboard = RuntimePasteboard(value: nil)
        let presenter = RuntimePageURLInputPresenter()
        let runtime = makeRuntime(
            panel: panel,
            pasteboard: pasteboard,
            shortcutRegistrar: shortcut,
            pageURLInputPresenter: presenter
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)
        runtime.start()

        shortcut.handler?()

        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(panel.isStashed)
        XCTAssertEqual(panel.currentPage, page)
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
        XCTAssertEqual(pasteboard.readCount, 0)
        XCTAssertEqual(presenter.presentAndFocusCount, 0)
    }

    func testShortcutRestoresStashedPinnedPanelWithoutRepinning() throws {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let runtime = makeRuntime(panel: panel, shortcutRegistrar: shortcut)
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)
        runtime.start()
        shortcut.handler?()

        shortcut.handler?()

        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isStashed)
        XCTAssertEqual(panel.currentPage, page)
        XCTAssertEqual(panel.shownPages, [page])
    }

    func testShortcutPresentsAndFocusesURLInputWhenNoPageIsPinned() {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let pasteboard = RuntimePasteboard(value: nil)
        let presenter = RuntimePageURLInputPresenter()
        let runtime = makeRuntime(
            panel: panel,
            pasteboard: pasteboard,
            shortcutRegistrar: shortcut,
            pageURLInputPresenter: presenter
        )
        runtime.start()

        shortcut.handler?()

        XCTAssertEqual(presenter.presentAndFocusCount, 1)
        XCTAssertEqual(pasteboard.readCount, 0)
        XCTAssertNil(panel.currentPage)
        XCTAssertFalse(panel.isVisible)
    }

    func testShortcutRegistrationFailurePublishesHealthAndRetryClearsIt() {
        let shortcut = RuntimeShortcutRegistrar(failuresRemaining: 1)
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            shortcutRegistrar: shortcut
        )

        runtime.start()

        XCTAssertTrue(runtime.serviceHealth.issues.contains(.globalShortcutUnavailable))

        runtime.retryRecovery(for: .globalShortcutUnavailable)

        XCTAssertFalse(runtime.serviceHealth.issues.contains(.globalShortcutUnavailable))
        XCTAssertNotNil(shortcut.handler)
    }

    func testShortcutFailureForcesHiddenMenuBarIconWithoutChangingSavedPreference() throws {
        let suiteName = "RuntimeMenuBarPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let preferenceStore = MenuBarIconPreferenceStore(defaults: defaults)
        preferenceStore.save(false)
        let shortcut = RuntimeShortcutRegistrar(failuresRemaining: 1)
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            shortcutRegistrar: shortcut,
            menuBarIconPreferenceStore: preferenceStore
        )

        runtime.start()

        XCTAssertFalse(runtime.savedMenuBarIconVisibility)
        XCTAssertTrue(runtime.effectiveMenuBarIconVisibility)
        XCTAssertTrue(runtime.isMenuBarIconVisibilityForced)
        XCTAssertFalse(preferenceStore.load())

        runtime.retryRecovery(for: .globalShortcutUnavailable)

        XCTAssertFalse(runtime.savedMenuBarIconVisibility)
        XCTAssertFalse(runtime.effectiveMenuBarIconVisibility)
        XCTAssertFalse(runtime.isMenuBarIconVisibilityForced)
        XCTAssertFalse(preferenceStore.load())
    }

    func testInitialPersistentStoreFailureIsPublished() {
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            initialServiceHealth: ServiceHealthState(
                issues: [.persistentStoreUnavailable]
            )
        )

        XCTAssertEqual(runtime.serviceHealth.issues, [.persistentStoreUnavailable])
        XCTAssertFalse(runtime.serviceHealth.isHealthy)
    }

    func testExternalRouteActivationUsesUnifiedRuntimePath() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let route = try XCTUnwrap(
            URL(
                string: """
                notion-pip://pin?url=https%3A%2F%2Fwww.notion.so%2F\(firstPageID)\
                &source=chrome-extension
                """
            )
        )

        runtime.handleOpenURLs([route])

        XCTAssertEqual(runtime.activePage?.pageID, firstPageID)
        XCTAssertEqual(
            runtime.lastActivationSource,
            .externalRoute(.chromeExtension)
        )
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
    }

    func testSearchResultActivationUsesUnifiedRuntimePath() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let page = try makePage(id: firstPageID, title: "Search result")

        runtime.activate(page: page, source: .notionSearch)

        XCTAssertEqual(runtime.activePage, page)
        XCTAssertEqual(runtime.lastActivationSource, .notionSearch)
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
    }

    func testEmbeddedWebSessionPageUsesUnifiedRuntimePath() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let first = try makePage(id: firstPageID, title: "Roadmap")
        let created = try makePage(id: secondPageID, title: "New Page")
        runtime.activate(page: first, source: .typedURL)

        runtime.activate(page: created, source: .notionWebSession)

        XCTAssertEqual(runtime.activePage, created)
        XCTAssertEqual(runtime.lastActivationSource, .notionWebSession)
        XCTAssertEqual(panel.replacedPages, [created])
    }

    func testStatusMenuContextActionWithoutCurrentPageShowsSettings() {
        let panel = RuntimePanelCoordinator()
        let settings = RuntimeSettingsWindowPresenter()
        let runtime = makeRuntime(panel: panel)
        runtime.bind(settingsWindowPresenter: settings)

        runtime.performStatusMenuContextCommand(.openSettings)

        XCTAssertEqual(settings.showCount, 1)
        XCTAssertFalse(panel.isVisible)
    }

    func testStatusMenuContextActionRestoresStashedPanelWithoutRepinning() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)
        panel.simulateStashedState()

        runtime.performStatusMenuContextCommand(.show)

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
    }

    func testStatusMenuContextActionStashesVisibleCurrentPanel() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)

        runtime.performStatusMenuContextCommand(.stash)

        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(panel.isStashed)
        XCTAssertEqual(panel.currentPage, page)
    }

    func testCapturedOpenSettingsCommandStillOpensSettingsAfterPageActivation() throws {
        let panel = RuntimePanelCoordinator()
        let settings = RuntimeSettingsWindowPresenter()
        let runtime = makeRuntime(panel: panel)
        runtime.bind(settingsWindowPresenter: settings)
        runtime.activate(
            page: try makePage(id: firstPageID, title: "Roadmap"),
            source: .typedURL
        )

        runtime.performStatusMenuContextCommand(.openSettings)

        XCTAssertEqual(settings.showCount, 1)
        XCTAssertTrue(panel.isVisible)
    }

    func testCapturedStashCommandDoesNotRestorePanelIfStateChangedWhileMenuWasOpen() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        runtime.activate(
            page: try makePage(id: firstPageID, title: "Roadmap"),
            source: .typedURL
        )
        panel.simulateStashedState()

        runtime.performStatusMenuContextCommand(.stash)

        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(panel.isStashed)
    }
}
