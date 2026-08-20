import Foundation
import XCTest
@testable import Perch

@MainActor
final class RuntimeActivationAndMenuBarTests: XCTestCase {
    func testEdgeHandleDropReplacesStashedPageThroughUnifiedActivationPath() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let currentPage = try makePage(id: firstPageID, title: "Roadmap")
        let droppedPage = try makePage(id: secondPageID, title: "Design System")
        runtime.activate(page: currentPage, source: .typedURL)
        try await repository.waitUntilSaveCount(1)
        panel.simulateStashedState()

        runtime.activate(page: droppedPage, source: .edgeHandleDrop)
        try await repository.waitUntilSaveCount(2)

        XCTAssertEqual(runtime.activePage, droppedPage)
        XCTAssertEqual(runtime.lastActivationSource, .edgeHandleDrop)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.currentPage, droppedPage)
        XCTAssertEqual(panel.shownPages, [currentPage])
        XCTAssertEqual(panel.replacedPages, [droppedPage])
    }

    func testRecentShelfSelectionUsesRestorationAndUnifiedActivationPath() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let page = try makePage(id: secondPageID, title: "Design-system")
        let restoration = try DurablePageRestoration(
            pageID: page.pageID,
            validatingLastURL: page.canonicalURL,
            scrollX: 0,
            scrollY: 620,
            scrollProgress: 0.62,
            updatedAt: Date(timeIntervalSince1970: 10_000)
        )

        runtime.activateRecentPage(
            .activate(page: page, restoration: restoration)
        )
        try await repository.waitUntilSaveCount(1)

        XCTAssertEqual(panel.currentPage, page)
        XCTAssertEqual(panel.lastRestoration, restoration)
        XCTAssertEqual(runtime.lastActivationSource, .pageSwitcher)
    }

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
        let runtime = makeRuntime(
            panel: panel,
            pasteboard: pasteboard,
            shortcutRegistrar: shortcut
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
    }

    func testGlobalShortcutRestoreRequestsContextBeforeRevealingPanel() throws {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let runtime = makeRuntime(panel: panel, shortcutRegistrar: shortcut)
        runtime.activate(
            page: try makePage(id: firstPageID, title: "Roadmap"),
            source: .typedURL
        )
        panel.simulateStashedState()
        var contextualRevealCount = 0
        runtime.bindContextualRevealHandler { fallback in
            XCTAssertNil(fallback)
            contextualRevealCount += 1
        }
        runtime.start()

        shortcut.handler?()

        XCTAssertEqual(contextualRevealCount, 1)
        XCTAssertEqual(panel.willRevealCount, 1)
        XCTAssertTrue(panel.isVisible)
    }

    func testShortcutStashesVisiblePinnedPanel() throws {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let pasteboard = RuntimePasteboard(value: nil)
        let runtime = makeRuntime(
            panel: panel,
            pasteboard: pasteboard,
            shortcutRegistrar: shortcut
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
    }

    func testShortcutCollapsesExpandedPiPBeforeStashingIt() throws {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let runtime = makeRuntime(panel: panel, shortcutRegistrar: shortcut)
        runtime.activate(
            page: try makePage(id: firstPageID, title: "Roadmap"),
            source: .typedURL
        )
        panel.simulateExpandedState()
        runtime.start()

        shortcut.handler?()

        XCTAssertEqual(panel.globalShortcutActionCount, 1)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isStashed)
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

    func testShortcutPresentsSettingsAndFocusesURLInputWhenNoPageIsAvailable() {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let pasteboard = RuntimePasteboard(value: nil)
        let settings = RuntimeSettingsWindowPresenter()
        let runtime = makeRuntime(
            panel: panel,
            pasteboard: pasteboard,
            shortcutRegistrar: shortcut
        )
        runtime.bind(settingsWindowPresenter: settings)
        runtime.start()

        shortcut.handler?()

        XCTAssertEqual(settings.showCount, 1)
        XCTAssertEqual(runtime.pageURLFocusRequest, 1)
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

    func testPersistentStoreRecoveryActionReopensRecoveryOptions() {
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            initialServiceHealth: ServiceHealthState(
                issues: [.persistentStoreUnavailable]
            )
        )
        var presentationCount = 0
        runtime.bindPersistentStoreRecoveryAction {
            presentationCount += 1
        }

        runtime.retryRecovery(for: .persistentStoreUnavailable)

        XCTAssertEqual(presentationCount, 1)
        XCTAssertEqual(runtime.serviceHealth.issues, [.persistentStoreUnavailable])
    }

    func testExternalRouteActivationUsesUnifiedRuntimePath() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let route = try XCTUnwrap(
            URL(
                string: """
                perch://pin?url=https%3A%2F%2Fwww.notion.so%2F\(firstPageID)\
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
        let runtime = AppRuntime(
            panelCoordinator: panel,
            pasteboard: RuntimePasteboard(value: nil),
            shortcutRegistrar: RuntimeShortcutRegistrar()
        )
        runtime.bind(settingsWindowPresenter: settings)

        runtime.performStatusMenuContextCommand(.openSettings)

        XCTAssertEqual(settings.showCount, 1)
        XCTAssertEqual(runtime.pageURLFocusRequest, 1)
        XCTAssertFalse(panel.isVisible)
    }

    func testMenuBarActivationWithoutCurrentPageShowsSettingsAndFocusesPageURL() {
        let panel = RuntimePanelCoordinator()
        let settings = RuntimeSettingsWindowPresenter()
        let runtime = AppRuntime(
            panelCoordinator: panel,
            pasteboard: RuntimePasteboard(value: nil),
            shortcutRegistrar: RuntimeShortcutRegistrar()
        )
        runtime.bind(settingsWindowPresenter: settings)

        runtime.handleMenuBarActivation()

        XCTAssertEqual(settings.showCount, 1)
        XCTAssertEqual(runtime.pageURLFocusRequest, 1)
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

    func testMenuBarShowRequestsContextBeforeRevealingPanel() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        runtime.activate(
            page: try makePage(id: firstPageID, title: "Roadmap"),
            source: .typedURL
        )
        panel.simulateStashedState()
        var contextualRevealCount = 0
        runtime.bindContextualRevealHandler { fallback in
            XCTAssertNil(fallback)
            contextualRevealCount += 1
        }

        runtime.performStatusMenuContextCommand(.show)

        XCTAssertEqual(contextualRevealCount, 1)
        XCTAssertEqual(panel.willRevealCount, 1)
        XCTAssertTrue(panel.isVisible)
    }

    func testEmptyShortcutActivatesDetectedPageThroughRuntimeInsteadOfOpeningSettings() throws {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let settings = RuntimeSettingsWindowPresenter()
        let runtime = makeRuntime(panel: panel, shortcutRegistrar: shortcut)
        runtime.bind(settingsWindowPresenter: settings)
        let monitor = RuntimeContextMonitor()
        let preferences = RuntimeContextPreferences(isEnabled: true)
        let controller = ContextSuggestionController(
            monitor: monitor,
            store: nil,
            preferenceStore: preferences,
            exactCaptureTimeout: .seconds(1),
            activePageID: { [weak runtime] in runtime?.activePage?.pageID },
            onActivate: { [weak runtime] page, restoration in
                runtime?.activate(
                    page: page,
                    source: .contextSuggestion,
                    restoration: restoration
                )
            }
        )
        runtime.bindContextualRevealHandler { [weak controller] fallback in
            guard let controller else {
                fallback?()
                return
            }
            controller.requestContextualReveal(emptyFallback: fallback)
        }
        controller.start()
        runtime.start()

        shortcut.handler?()
        XCTAssertEqual(settings.showCount, 0)

        let page = try makePage(id: secondPageID, title: "Detected")
        monitor.completeExactCapture(
            with: ContextSnapshot(
                source: ContextSourceIdentity(
                    processIdentifier: 42,
                    bundleIdentifier: "com.apple.Safari",
                    applicationName: "Safari"
                ),
                exactPage: page
            )
        )

        XCTAssertEqual(runtime.activePage, page)
        XCTAssertEqual(runtime.lastActivationSource, .contextSuggestion)
        XCTAssertEqual(panel.currentPage, page)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(settings.showCount, 0)
    }

    func testEmptyShortcutFallsBackToExistingSetupWhenNoExactContextExists() {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let settings = RuntimeSettingsWindowPresenter()
        let runtime = makeRuntime(panel: panel, shortcutRegistrar: shortcut)
        runtime.bind(settingsWindowPresenter: settings)
        let monitor = RuntimeContextMonitor()
        let controller = ContextSuggestionController(
            monitor: monitor,
            store: nil,
            preferenceStore: RuntimeContextPreferences(isEnabled: true),
            exactCaptureTimeout: .seconds(1),
            activePageID: { [weak runtime] in runtime?.activePage?.pageID },
            onActivate: { _, _ in XCTFail("No page should activate") }
        )
        runtime.bindContextualRevealHandler { [weak controller] fallback in
            controller?.requestContextualReveal(emptyFallback: fallback)
        }
        controller.start()
        runtime.start()

        shortcut.handler?()
        monitor.completeExactCapture(with: nil)

        XCTAssertEqual(settings.showCount, 1)
        XCTAssertEqual(runtime.pageURLFocusRequest, 1)
        XCTAssertNil(runtime.activePage)
    }

    func testExplicitRecentSelectionDoesNotRequestContextualReplacement() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        var contextualRevealCount = 0
        runtime.bindContextualRevealHandler { _ in
            contextualRevealCount += 1
        }
        let page = try makePage(id: secondPageID, title: "Recent")

        runtime.activateRecentPage(.activate(page: page, restoration: nil))

        XCTAssertEqual(contextualRevealCount, 0)
        XCTAssertEqual(runtime.activePage, page)
        XCTAssertEqual(runtime.lastActivationSource, .pageSwitcher)
    }

    func testExplicitPinnedSelectionDoesNotRequestContextualReplacement() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        var contextualRevealCount = 0
        runtime.bindContextualRevealHandler { _ in
            contextualRevealCount += 1
        }
        let page = try makePage(id: secondPageID, title: "Pinned")

        runtime.pin(page: page)

        XCTAssertEqual(contextualRevealCount, 0)
        XCTAssertEqual(runtime.activePage, page)
        XCTAssertEqual(runtime.lastActivationSource, .pagePicker)
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

@MainActor
private final class RuntimeContextMonitor: ContextMonitoring {
    var onSnapshot: (@MainActor (ContextSnapshot?) -> Void)?
    var onAuthorizationChange: (@MainActor (Bool) -> Void)?
    var isAuthorized = true
    private var completions: [(@MainActor (ContextSnapshot?) -> Void)] = []

    func requestAccess() -> Bool { isAuthorized }
    func start() {}
    func stop() {}

    func captureExactPage(
        completion: @escaping @MainActor (ContextSnapshot?) -> Void
    ) {
        completions.append(completion)
    }

    func completeExactCapture(with snapshot: ContextSnapshot?) {
        guard !completions.isEmpty else { return }
        completions.removeFirst()(snapshot)
    }
}

@MainActor
private final class RuntimeContextPreferences: ContextSuggestionPreferenceStoring {
    private var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func load() -> Bool { isEnabled }
    func save(_ enabled: Bool) { isEnabled = enabled }
}
