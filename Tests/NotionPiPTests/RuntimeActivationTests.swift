import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class RuntimeActivationTests: XCTestCase {
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

    private let firstPageID = "0123456789abcdef0123456789abcdef"
    private let secondPageID = "fedcba9876543210fedcba9876543210"

    func testTypedURLActivationUsesUnifiedRuntimePath() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)

        runtime.pageURLText = "https://www.notion.so/Roadmap-\(firstPageID)"
        runtime.validatePageURL()

        XCTAssertEqual(runtime.activePage?.pageID, firstPageID)
        XCTAssertEqual(runtime.lastActivationSource, .typedURL)
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
    }

    func testReloadSavedPinReusesActivePageWithoutPersistingItAgain() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)
        try await repository.waitUntilSaveCount(1)

        runtime.reloadSavedPin()
        for _ in 0 ..< 3 { await Task.yield() }
        let savedPages = await repository.savedPages()

        XCTAssertEqual(panel.reloadedPages, [page])
        XCTAssertEqual(runtime.activePage, page)
        XCTAssertEqual(savedPages, [page])
    }

    func testShortcutShowsHiddenPinnedPanelWithoutRepinningOrReadingPasteboard() throws {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let pasteboard = RuntimePasteboard(value: "https://www.notion.so/Notes-\(secondPageID)")
        let presenter = RuntimePageURLInputPresenter()
        let runtime = makeRuntime(
            panel: panel,
            pasteboard: pasteboard,
            shortcutRegistrar: shortcut,
            pageURLInputPresenter: presenter
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)
        panel.hide()
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

    func testInitialPersistentStoreFailureIsPublished() {
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            initialServiceHealth: ServiceHealthState(issues: [.persistentStoreUnavailable])
        )

        XCTAssertEqual(runtime.serviceHealth.issues, [.persistentStoreUnavailable])
        XCTAssertFalse(runtime.serviceHealth.isHealthy)
    }

    func testExternalRouteActivationUsesUnifiedRuntimePath() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let route = try XCTUnwrap(URL(string: "notion-pip://pin?url=https%3A%2F%2Fwww.notion.so%2F\(firstPageID)&source=chrome-extension"))

        runtime.handleOpenURLs([route])

        XCTAssertEqual(runtime.activePage?.pageID, firstPageID)
        XCTAssertEqual(runtime.lastActivationSource, .externalRoute(.chromeExtension))
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

    func testMenuBarActivationWithoutCurrentPageShowsSettings() {
        let panel = RuntimePanelCoordinator()
        let settings = RuntimeSettingsWindowPresenter()
        let runtime = makeRuntime(panel: panel)
        runtime.bind(settingsWindowPresenter: settings)

        runtime.handleMenuBarActivation()

        XCTAssertEqual(settings.showCount, 1)
        XCTAssertFalse(panel.isVisible)
    }

    func testMenuBarActivationShowsHiddenCurrentPanelWithoutRepinning() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)
        panel.hide()

        runtime.handleMenuBarActivation()

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
    }

    func testMenuBarActivationHidesVisibleCurrentPanel() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let page = try makePage(id: firstPageID, title: "Roadmap")
        runtime.activate(page: page, source: .typedURL)

        runtime.handleMenuBarActivation()

        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.currentPage, page)
    }

    func testMenuBarActivationFallsBackToSettingsWhenRuntimeAndPanelDisagree() throws {
        let panel = RuntimePanelCoordinator()
        let settings = RuntimeSettingsWindowPresenter()
        let runtime = makeRuntime(panel: panel)
        runtime.bind(settingsWindowPresenter: settings)
        runtime.activate(
            page: try makePage(id: firstPageID, title: "Roadmap"),
            source: .typedURL
        )
        panel.loseCurrentPage()

        runtime.handleMenuBarActivation()

        XCTAssertEqual(settings.showCount, 1)
        XCTAssertFalse(panel.isVisible)
    }

    func testDisconnectAndReconnectPreventsLateSearchFromReplacingClearedResults() async throws {
        let client = DelayedSearchClient()
        let runtime = makeRuntime(panel: RuntimePanelCoordinator(), client: client)

        await runtime.bootstrapPersonalTokenConnection()
        let search = Task { await runtime.searchNotionPages(query: "Roadmap") }
        await client.waitUntilSearchStarts()

        runtime.disconnectPersonalToken()
        await runtime.connectPersonalToken("ntn_1234567890abcdef")
        await client.finishSearch()
        await search.value

        XCTAssertEqual(runtime.connectionState, .connected(workspaceName: "Workspace"))
        XCTAssertTrue(runtime.searchResults.isEmpty)
        XCTAssertNil(runtime.searchError)
    }

    func testDisconnectAndReconnectPreventsLateSearchErrorFromReplacingClearedState() async throws {
        let client = DelayedSearchClient(failing: true)
        let runtime = makeRuntime(panel: RuntimePanelCoordinator(), client: client)

        await runtime.bootstrapPersonalTokenConnection()
        let search = Task { await runtime.searchNotionPages(query: "Roadmap") }
        await client.waitUntilSearchStarts()

        runtime.disconnectPersonalToken()
        await runtime.connectPersonalToken("ntn_1234567890abcdef")
        await client.finishSearch()
        await search.value

        XCTAssertEqual(runtime.connectionState, .connected(workspaceName: "Workspace"))
        XCTAssertTrue(runtime.searchResults.isEmpty)
        XCTAssertNil(runtime.searchError)
    }

    func testDestinationSearchRejectsShortOrWhitespaceOnlyQueriesAndClearsResults() async throws {
        let client = RuntimeDestinationSearchClient(pages: [
            destinationPage(ids: ["one"], nextCursor: nil),
        ])
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            client: client,
            destinationSearchDebounceDuration: .zero
        )
        await runtime.bootstrapPersonalTokenConnection()

        await runtime.searchQuickCaptureDestinations(query: "notes")
        await runtime.searchQuickCaptureDestinations(query: " a ")
        await runtime.searchQuickCaptureDestinations(query: "   ")

        XCTAssertTrue(runtime.destinationSearchResults.isEmpty)
        XCTAssertNil(runtime.destinationSearchError)
        XCTAssertFalse(runtime.canLoadMoreDestinations)
        XCTAssertFalse(runtime.isSearchingDestinations)
        let requests = await client.requests()
        XCTAssertEqual(requests, [RuntimeDestinationSearchRequest(query: "notes", startCursor: nil)])
    }

    func testDestinationSearchDebouncesAutomaticQueriesAndImmediateSearchBypassesDelay() async throws {
        let client = RuntimeDestinationSearchClient(pages: [
            destinationPage(ids: ["immediate"], nextCursor: nil),
        ])
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            client: client,
            destinationSearchDebounceDuration: .seconds(60)
        )
        await runtime.bootstrapPersonalTokenConnection()

        runtime.scheduleQuickCaptureDestinationSearch(query: "delayed")
        await Task.yield()
        let delayedRequests = await client.requests()
        XCTAssertTrue(delayedRequests.isEmpty)

        await runtime.searchQuickCaptureDestinations(query: "immediate")

        let requests = await client.requests()
        XCTAssertEqual(requests, [RuntimeDestinationSearchRequest(query: "immediate", startCursor: nil)])
        XCTAssertEqual(runtime.destinationSearchResults.map(\.destination.title), ["immediate"])
    }

    func testDestinationSearchLoadMoreAppendsUniqueResultsUsingPreviousCursor() async throws {
        let client = RuntimeDestinationSearchClient(pages: [
            destinationPage(ids: ["one", "two"], nextCursor: "cursor-2"),
            destinationPage(ids: ["two", "three"], nextCursor: nil),
        ])
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            client: client,
            destinationSearchDebounceDuration: .zero
        )
        await runtime.bootstrapPersonalTokenConnection()

        await runtime.searchQuickCaptureDestinations(query: "notes")
        await runtime.loadMoreQuickCaptureDestinations()

        XCTAssertEqual(runtime.destinationSearchResults.map(\.destination.title), ["one", "two", "three"])
        let requests = await client.requests()
        XCTAssertEqual(requests, [
            RuntimeDestinationSearchRequest(query: "notes", startCursor: nil),
            RuntimeDestinationSearchRequest(query: "notes", startCursor: "cursor-2"),
        ])
        XCTAssertFalse(runtime.canLoadMoreDestinations)
    }

    func testDestinationSearchIgnoresOlderQueryCompletion() async throws {
        let client = DelayedDestinationSearchClient()
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            client: client,
            destinationSearchDebounceDuration: .zero
        )
        await runtime.bootstrapPersonalTokenConnection()

        let firstSearch = Task { await runtime.searchQuickCaptureDestinations(query: "first") }
        await client.waitUntilStarted(query: "first")
        let secondSearch = Task { await runtime.searchQuickCaptureDestinations(query: "second") }
        await client.waitUntilStarted(query: "second")
        await client.finish(
            query: "second",
            with: destinationPage(ids: ["current"], nextCursor: nil)
        )
        await secondSearch.value
        await client.finish(
            query: "first",
            with: destinationPage(ids: ["stale"], nextCursor: nil)
        )
        await firstSearch.value

        XCTAssertEqual(runtime.destinationSearchResults.map(\.destination.title), ["current"])
        XCTAssertNil(runtime.destinationSearchError)
    }

    func testDestinationSearchStopsOnRepeatedCursorWithoutDiscardingResults() async throws {
        let client = RuntimeDestinationSearchClient(pages: [
            destinationPage(ids: ["one"], nextCursor: "cursor-2"),
            destinationPage(ids: ["two"], nextCursor: "cursor-2"),
        ])
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            client: client,
            destinationSearchDebounceDuration: .zero
        )
        await runtime.bootstrapPersonalTokenConnection()

        await runtime.searchQuickCaptureDestinations(query: "notes")
        await runtime.loadMoreQuickCaptureDestinations()

        XCTAssertEqual(runtime.destinationSearchResults.map(\.destination.title), ["one", "two"])
        XCTAssertEqual(runtime.destinationSearchError, "Could not search Notion destinations.")
        XCTAssertFalse(runtime.canLoadMoreDestinations)
    }

    func testDestinationSearchCapsContinuationAfterFourPages() async throws {
        let client = RuntimeDestinationSearchClient(pages: [
            destinationPage(ids: ["one"], nextCursor: "cursor-2"),
            destinationPage(ids: ["two"], nextCursor: "cursor-3"),
            destinationPage(ids: ["three"], nextCursor: "cursor-4"),
            destinationPage(ids: ["four"], nextCursor: "cursor-5"),
        ])
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            client: client,
            destinationSearchDebounceDuration: .zero
        )
        await runtime.bootstrapPersonalTokenConnection()

        await runtime.searchQuickCaptureDestinations(query: "notes")
        await runtime.loadMoreQuickCaptureDestinations()
        await runtime.loadMoreQuickCaptureDestinations()
        await runtime.loadMoreQuickCaptureDestinations()

        XCTAssertEqual(runtime.destinationSearchResults.map(\.destination.title), ["one", "two", "three", "four"])
        XCTAssertTrue(runtime.isDestinationSearchCapped)
        XCTAssertFalse(runtime.canLoadMoreDestinations)
    }

    func testDestinationSearchCapsContinuationAtOneHundredDisplayedResults() async throws {
        let client = RuntimeDestinationSearchClient(pages: [
            destinationPage(ids: (0 ..< 100).map { "destination-\($0)" }, nextCursor: "cursor-2"),
        ])
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            client: client,
            destinationSearchDebounceDuration: .zero
        )
        await runtime.bootstrapPersonalTokenConnection()

        await runtime.searchQuickCaptureDestinations(query: "notes")

        XCTAssertEqual(runtime.destinationSearchResults.count, 100)
        XCTAssertTrue(runtime.isDestinationSearchCapped)
        XCTAssertFalse(runtime.canLoadMoreDestinations)
    }

    func testStartRestoresSavedPageIntoVisiblePanel() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let storedPage = try makeStoredPage(id: firstPageID, title: "Roadmap")

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: storedPage)
        await waitUntil { runtime.activePage?.pageID == self.firstPageID }

        XCTAssertEqual(runtime.lastActivationSource, .restored)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.currentPage?.pageID, firstPageID)
    }

    func testShortcutTogglesRestoredPageWithoutReloadingIt() async throws {
        let panel = RuntimePanelCoordinator()
        let shortcut = RuntimeShortcutRegistrar()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(
            panel: panel,
            shortcutRegistrar: shortcut,
            pageRepository: repository
        )
        let storedPage = try makeStoredPage(id: firstPageID, title: "Restored")

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: storedPage)
        await waitUntil { runtime.activePage?.pageID == self.firstPageID }

        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
        shortcut.handler?()
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(panel.isStashed)
        shortcut.handler?()
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isStashed)
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
        XCTAssertTrue(panel.replacedPages.isEmpty)
    }

    func testStartWithNoSavedPageLeavesPanelHidden() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: nil)
        try await repository.waitUntilRestoreReturned()
        for _ in 0 ..< 3 { await Task.yield() }

        XCTAssertNil(runtime.activePage)
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(panel.currentPage)
    }

    func testFailedRestorePublishesHealthAndRetryReadsRepositoryAgain() async throws {
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            pageRepository: repository
        )

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(throwing: RuntimeRepositoryError.restoreFailed)
        await waitUntil {
            runtime.serviceHealth.issues.contains(.pinnedPagePersistenceUnavailable)
        }

        runtime.retryRecovery(for: .pinnedPagePersistenceUnavailable)
        try await repository.waitUntilRestoreRequested(count: 2)
        await repository.finishRestore(with: nil)
        await waitUntil {
            !runtime.serviceHealth.issues.contains(.pinnedPagePersistenceUnavailable)
        }

        XCTAssertNil(runtime.activePage)
    }

    func testTypedActivationWhileRestoreIsDelayedWins() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let storedPage = try makeStoredPage(id: firstPageID, title: "Stored")
        let typedPage = try makePage(id: secondPageID, title: "Typed")

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        runtime.activate(page: typedPage, source: .typedURL)
        await repository.finishRestore(with: storedPage)
        try await repository.waitUntilRestoreReturned()
        try await repository.waitUntilSaveCount(1)
        for _ in 0 ..< 3 { await Task.yield() }

        XCTAssertEqual(runtime.activePage, typedPage)
        XCTAssertEqual(runtime.lastActivationSource, .typedURL)
        XCTAssertEqual(panel.currentPage, typedPage)
    }

    func testBufferedOpenURLWinsOverDelayedRestoreDuringStartup() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let appDelegate = AppDelegate()
        let storedPage = try makeStoredPage(id: firstPageID, title: "Stored")
        let directPage = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/\(secondPageID)"))
        )
        let route = try XCTUnwrap(
            URL(
                string: "notion-pip://pin?url=https%3A%2F%2Fwww.notion.so%2F\(secondPageID)&source=chrome-extension"
            )
        )

        appDelegate.application(NSApplication.shared, open: [route])
        AppStartup.start(runtime: runtime, appDelegate: appDelegate)

        try await repository.waitUntilSaveCount(1)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        let restoreRequestCount = await repository.restoreRequestCount()
        await repository.finishRestore(with: storedPage)
        if restoreRequestCount > 0 {
            try await repository.waitUntilRestoreReturned()
        }
        for _ in 0 ..< 3 {
            await Task.yield()
        }

        XCTAssertEqual(runtime.activePage, directPage)
        XCTAssertEqual(runtime.lastActivationSource, .externalRoute(.chromeExtension))
        XCTAssertEqual(panel.currentPage, directPage)
        XCTAssertEqual(panel.shownPages, [directPage])
    }

    func testTerminationWaitsForPendingAndNewerPageSavesBeforeReplying() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository(delaySaves: true)
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        var terminationReplies: [Bool] = []
        let appDelegate = AppDelegate { _, shouldTerminate in
            terminationReplies.append(shouldTerminate)
        }
        let first = try makePage(id: firstPageID, title: "First")
        let second = try makePage(id: secondPageID, title: "Second")

        AppStartup.start(runtime: runtime, appDelegate: appDelegate)
        runtime.activate(page: first, source: .typedURL)
        try await repository.waitUntilSaveCount(1)

        XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        for _ in 0 ..< 3 {
            await Task.yield()
        }
        XCTAssertTrue(terminationReplies.isEmpty)

        runtime.activate(page: second, source: .notionSearch)
        await repository.finishSave(pageID: firstPageID)
        try await repository.waitUntilSaveCount(2)
        for _ in 0 ..< 3 {
            await Task.yield()
        }
        XCTAssertTrue(terminationReplies.isEmpty)

        await repository.finishSave(pageID: secondPageID)
        await waitUntil { terminationReplies == [true] }
        let savedPageIDs = await repository.savedPageIDs()
        XCTAssertEqual(savedPageIDs, [firstPageID, secondPageID])
    }

    func testTerminationRepliesAfterPendingPageSaveFails() async throws {
        let repository = RuntimePinnedPageRepository(
            delaySaves: true,
            failingPageIDs: [firstPageID]
        )
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            pageRepository: repository
        )
        var terminationReplies: [Bool] = []
        let appDelegate = AppDelegate { _, shouldTerminate in
            terminationReplies.append(shouldTerminate)
        }
        let page = try makePage(id: firstPageID, title: "Failure")

        AppStartup.start(runtime: runtime, appDelegate: appDelegate)
        runtime.activate(page: page, source: .typedURL)
        try await repository.waitUntilSaveCount(1)

        XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        for _ in 0 ..< 3 {
            await Task.yield()
        }
        XCTAssertTrue(terminationReplies.isEmpty)

        await repository.finishSave(pageID: firstPageID)
        await waitUntil { terminationReplies == [true] }
    }

    func testRepeatedTerminationRequestsShareOneLiveCaptureFlush() async throws {
        let runtime = makeRuntime(panel: RuntimePanelCoordinator())
        let participant = RuntimeTerminationParticipant()
        var terminationReplies: [Bool] = []
        let appDelegate = AppDelegate { _, shouldTerminate in
            terminationReplies.append(shouldTerminate)
        }
        AppStartup.start(
            runtime: runtime,
            appDelegate: appDelegate,
            terminationParticipantProvider: { participant }
        )

        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        try await participant.waitUntilCallCount(1)
        XCTAssertTrue(terminationReplies.isEmpty)

        participant.finish(with: true)
        await waitUntil { terminationReplies == [true] }
        XCTAssertEqual(participant.callCount, 1)
    }

    func testCaptureFlushFailureCancelsTerminationAndAllowsRetry() async {
        let runtime = makeRuntime(panel: RuntimePanelCoordinator())
        let participant = RuntimeImmediateTerminationParticipant(results: [false, true])
        var terminationReplies: [Bool] = []
        let appDelegate = AppDelegate { _, shouldTerminate in
            terminationReplies.append(shouldTerminate)
        }
        AppStartup.start(
            runtime: runtime,
            appDelegate: appDelegate,
            terminationParticipantProvider: { participant }
        )

        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        await waitUntil { terminationReplies == [false] }

        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        await waitUntil { terminationReplies == [false, true] }
        XCTAssertEqual(participant.callCount, 2)
    }

    func testActivationImmediatelyAfterStartWinsBeforeRestoreRequestBegins() async throws {
        let panel = RuntimePanelCoordinator()
        let storedPage = try makeStoredPage(id: firstPageID, title: "Stored")
        let repository = RuntimePinnedPageRepository(immediateStoredPage: storedPage)
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let directPage = try makePage(id: secondPageID, title: "Direct")

        runtime.start()
        runtime.activate(page: directPage, source: .typedURL)
        for _ in 0 ..< 10 { await Task.yield() }
        let restoreRequestCount = await repository.restoreRequestCount()

        XCTAssertEqual(runtime.activePage, directPage)
        XCTAssertEqual(runtime.lastActivationSource, .typedURL)
        XCTAssertEqual(panel.currentPage, directPage)
        XCTAssertEqual(restoreRequestCount, 0)
    }

    func testDisconnectWhileRestoreIsDelayedStillRestoresSavedPage() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let storedPage = try makeStoredPage(id: firstPageID, title: "Stored")

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        runtime.disconnectPersonalToken()
        await repository.finishRestore(with: storedPage)
        try await repository.waitUntilRestoreReturned()
        await waitUntil { runtime.activePage?.pageID == self.firstPageID }

        XCTAssertEqual(runtime.activePage?.pageID, firstPageID)
        XCTAssertEqual(runtime.lastActivationSource, .restored)
        XCTAssertTrue(panel.isVisible)
    }

    func testActivationPersistsCanonicalReplacement() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let page = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://notion.so/Roadmap-\(firstPageID)?source=test#fragment"))
        )

        runtime.activate(page: page, source: .pagePicker)
        try await repository.waitUntilSaveCount(1)
        let savedPages = await repository.savedPages()

        XCTAssertEqual(savedPages, [page])
        XCTAssertEqual(savedPages.first?.canonicalURL, page.canonicalURL)
    }

    func testRapidActivationsPersistInActivationOrder() async throws {
        let repository = RuntimePinnedPageRepository(delaySaves: true)
        let runtime = makeRuntime(panel: RuntimePanelCoordinator(), pageRepository: repository)
        let first = try makePage(id: firstPageID, title: "First")
        let second = try makePage(id: secondPageID, title: "Second")

        runtime.activate(page: first, source: .typedURL)
        runtime.activate(page: second, source: .notionSearch)
        try await repository.waitUntilSaveCount(1)
        let firstSaveIDs = await repository.savedPageIDs()

        XCTAssertEqual(firstSaveIDs, [firstPageID])

        await repository.finishSave(pageID: firstPageID)
        try await repository.waitUntilSaveCount(2)
        let allSaveIDs = await repository.savedPageIDs()

        XCTAssertEqual(allSaveIDs, [firstPageID, secondPageID])
        await repository.finishSave(pageID: secondPageID)
    }

    func testFailedSaveDoesNotHidePanelOrPreventNextSave() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository(failingPageIDs: [firstPageID])
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let first = try makePage(id: firstPageID, title: "First")
        let second = try makePage(id: secondPageID, title: "Second")

        runtime.activate(page: first, source: .typedURL)
        try await repository.waitUntilFailedSaveCount(1)
        await waitUntil {
            runtime.serviceHealth.issues.contains(.pinnedPagePersistenceUnavailable)
        }

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.currentPage, first)

        runtime.activate(page: second, source: .notionSearch)
        try await repository.waitUntilSaveCount(2)
        let savedPageIDs = await repository.savedPageIDs()
        await waitUntil {
            !runtime.serviceHealth.issues.contains(.pinnedPagePersistenceUnavailable)
        }

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.currentPage, second)
        XCTAssertEqual(savedPageIDs, [firstPageID, secondPageID])
    }

    func testCorruptRestoredPageLeavesRuntimeEmpty() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let mismatchedPage = try makeStoredPage(id: secondPageID, title: "Mismatch")
        let corruptPage = StoredPageSnapshot(
            pageID: firstPageID,
            canonicalURL: mismatchedPage.canonicalURL,
            displayTitle: mismatchedPage.displayTitle,
            timestamp: mismatchedPage.timestamp
        )

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: corruptPage)
        try await repository.waitUntilRestoreReturned()
        for _ in 0 ..< 3 { await Task.yield() }

        XCTAssertNil(runtime.activePage)
        XCTAssertNil(runtime.lastActivationSource)
        XCTAssertFalse(panel.isVisible)
    }

    func testStartingTwiceRequestsRestoreOnce() async throws {
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: RuntimePanelCoordinator(), pageRepository: repository)

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        runtime.start()
        for _ in 0 ..< 3 { await Task.yield() }
        let restoreRequestCount = await repository.restoreRequestCount()

        XCTAssertEqual(restoreRequestCount, 1)
        await repository.finishRestore(with: nil)
    }

    private func makeRuntime(
        panel: RuntimePanelCoordinator,
        pasteboard: any PasteboardReading = RuntimePasteboard(value: nil),
        shortcutRegistrar: any GlobalShortcutRegistering = RuntimeShortcutRegistrar(),
        pageURLInputPresenter: RuntimePageURLInputPresenter = RuntimePageURLInputPresenter(),
        pageRepository: (any PinnedPagePersisting)? = nil,
        client: any NotionWorkspaceClient = RuntimeNotionClient(),
        destinationSearchDebounceDuration: Duration = .milliseconds(300),
        initialServiceHealth: ServiceHealthState = .healthy
    ) -> AppRuntime {
        let store = RuntimeSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        try! vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        return AppRuntime(
            panelCoordinator: panel,
            pasteboard: pasteboard,
            shortcutRegistrar: shortcutRegistrar,
            pageURLInputPresenter: pageURLInputPresenter,
            pageRepository: pageRepository,
            credentialVault: vault,
            notionClientFactory: { _ in client },
            destinationSearchDebounceDuration: destinationSearchDebounceDuration,
            initialServiceHealth: initialServiceHealth
        )
    }

    private func destinationPage(
        ids: [String],
        nextCursor: String?
    ) -> NotionDestinationSearchPage {
        NotionDestinationSearchPage(
            results: ids.map {
                NotionDestinationSearchResult(
                    destination: .pageParent(pageID: $0, title: $0),
                    lastEditedTime: ""
                )
            },
            nextCursor: nextCursor
        )
    }

    private func makePage(id: String, title: String) throws -> NotionPageReference {
        try NotionPageReference(validating: XCTUnwrap(URL(string: "https://www.notion.so/\(title)-\(id)")))
    }

    private func makeStoredPage(id: String, title: String) throws -> StoredPageSnapshot {
        let page = try makePage(id: id, title: title)
        return StoredPageSnapshot(
            pageID: page.pageID,
            canonicalURL: page.canonicalURL,
            displayTitle: page.displayTitle,
            timestamp: .distantPast
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not met", file: file, line: line)
    }
}

@MainActor
private final class RuntimePanelCoordinator: PiPPanelCoordinating {
    private(set) var currentPage: NotionPageReference?
    private(set) var shownPages: [NotionPageReference] = []
    private(set) var reloadedPages: [NotionPageReference] = []
    private(set) var replacedPages: [NotionPageReference] = []
    private(set) var isVisible = false
    private(set) var isStashed = false

    func show(page: NotionPageReference) {
        currentPage = page
        shownPages.append(page)
        isVisible = true
        isStashed = false
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        currentPage = page
        reloadedPages.append(page)
        isVisible = true
        isStashed = false
    }

    func replace(page: NotionPageReference) {
        currentPage = page
        replacedPages.append(page)
        isVisible = true
        isStashed = false
    }

    func showCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        isVisible = true
        isStashed = false
        return true
    }

    func hide() {
        isVisible = false
        isStashed = false
    }

    func toggleCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        if isVisible {
            hide()
        } else {
            _ = showCurrentPage()
        }
        return true
    }

    func stashOrRestoreCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        if isVisible {
            isVisible = false
            isStashed = true
        } else {
            _ = showCurrentPage()
        }
        return true
    }

    func loseCurrentPage() {
        currentPage = nil
        isVisible = false
        isStashed = false
    }
}

@MainActor
private final class RuntimeSettingsWindowPresenter: SettingsWindowPresenting {
    private(set) var showCount = 0

    func show() {
        showCount += 1
    }
}

private final class RuntimePasteboard: PasteboardReading {
    let value: String?
    private(set) var readCount = 0
    init(value: String?) { self.value = value }
    func readString() -> String? {
        readCount += 1
        return value
    }
}

@MainActor
private final class RuntimeShortcutRegistrar: GlobalShortcutRegistering {
    var handler: (@MainActor () -> Void)?
    private var failuresRemaining: Int

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    func register(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw RuntimeShortcutRegistrationError.failed
        }
        self.handler = handler
    }

    func unregister() {}
}

private enum RuntimeShortcutRegistrationError: Error {
    case failed
}

@MainActor
private final class RuntimePageURLInputPresenter: PageURLInputPresenting {
    private(set) var presentAndFocusCount = 0

    func presentAndFocus() {
        presentAndFocusCount += 1
    }
    func hide() {}
}

private final class RuntimeSecretStore: SecretStoring {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { data = nil }
}

private enum RuntimeRepositoryError: Error {
    case saveFailed
    case restoreFailed
}

private enum RuntimeTestWaitError: Error {
    case timedOut(String)
}

@MainActor
private final class RuntimeTerminationParticipant: ApplicationTerminationParticipating {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<Bool, Never>?

    func prepareForTermination() async -> Bool {
        callCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilCallCount(_ count: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while callCount < count {
            guard clock.now < deadline else {
                throw RuntimeTestWaitError.timedOut("termination participant call")
            }
            await Task.yield()
        }
    }

    func finish(with result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
private final class RuntimeImmediateTerminationParticipant: ApplicationTerminationParticipating {
    private var results: [Bool]
    private(set) var callCount = 0

    init(results: [Bool]) {
        self.results = results
    }

    func prepareForTermination() async -> Bool {
        callCount += 1
        return results.removeFirst()
    }
}

private actor RuntimePinnedPageRepository: PinnedPagePersisting {
    private let delaySaves: Bool
    private let failingPageIDs: Set<String>
    private let immediateStoredPage: StoredPageSnapshot?
    private var restoreRequests = 0
    private var restoreReturned = false
    private var restoreContinuation: CheckedContinuation<StoredPageSnapshot?, any Error>?
    private var pagesSaved: [NotionPageReference] = []
    private var failedSaves = 0
    private var saveContinuations: [String: CheckedContinuation<Void, Never>] = [:]

    init(
        delaySaves: Bool = false,
        failingPageIDs: Set<String> = [],
        immediateStoredPage: StoredPageSnapshot? = nil
    ) {
        self.delaySaves = delaySaves
        self.failingPageIDs = failingPageIDs
        self.immediateStoredPage = immediateStoredPage
    }

    func currentPinnedPage() async throws -> StoredPageSnapshot? {
        restoreRequests += 1
        if let immediateStoredPage {
            restoreReturned = true
            return immediateStoredPage
        }
        let page = try await withCheckedThrowingContinuation { continuation in
            restoreContinuation = continuation
        }
        restoreReturned = true
        return page
    }

    func replaceCurrent(with page: NotionPageReference) async throws -> StoredPageSnapshot {
        pagesSaved.append(page)
        if delaySaves {
            await withCheckedContinuation { continuation in
                saveContinuations[page.pageID] = continuation
            }
        }
        if failingPageIDs.contains(page.pageID) {
            failedSaves += 1
            throw RuntimeRepositoryError.saveFailed
        }
        return StoredPageSnapshot(
            pageID: page.pageID,
            canonicalURL: page.canonicalURL,
            displayTitle: page.displayTitle,
            timestamp: .distantPast
        )
    }

    func waitUntilRestoreRequested(count: Int = 1) async throws {
        try await waitUntil({ restoreRequests >= count }, operation: "restore request \(count)")
    }

    func finishRestore(with page: StoredPageSnapshot?) {
        restoreContinuation?.resume(returning: page)
        restoreContinuation = nil
    }

    func finishRestore(throwing error: any Error) {
        restoreContinuation?.resume(throwing: error)
        restoreContinuation = nil
    }

    func waitUntilRestoreReturned() async throws {
        try await waitUntil({ restoreReturned }, operation: "restore return")
    }

    func restoreRequestCount() -> Int {
        restoreRequests
    }

    func waitUntilSaveCount(_ count: Int) async throws {
        try await waitUntil({ pagesSaved.count >= count }, operation: "save count \(count)")
    }

    func waitUntilFailedSaveCount(_ count: Int) async throws {
        try await waitUntil({ failedSaves >= count }, operation: "failed save count \(count)")
    }

    func savedPages() -> [NotionPageReference] {
        pagesSaved
    }

    func savedPageIDs() -> [String] {
        pagesSaved.map(\.pageID)
    }

    func finishSave(pageID: String) {
        saveContinuations.removeValue(forKey: pageID)?.resume()
    }

    private func waitUntil(
        _ condition: () -> Bool,
        operation: String
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !condition() {
            guard clock.now < deadline else {
                throw RuntimeTestWaitError.timedOut(operation)
            }
            await Task.yield()
        }
    }
}

private actor RuntimeNotionClient: NotionWorkspaceClient {
    func validateConnection() async throws -> NotionConnectionSnapshot { NotionConnectionSnapshot(workspaceName: "Workspace") }
    func searchPages(query: String) async throws -> [NotionPageSearchResult] { [] }
}

private struct RuntimeDestinationSearchRequest: Equatable, Sendable {
    let query: String
    let startCursor: String?
}

private actor RuntimeDestinationSearchClient: NotionWorkspaceClient {
    private var pages: [NotionDestinationSearchPage]
    private var recordedRequests: [RuntimeDestinationSearchRequest] = []

    init(pages: [NotionDestinationSearchPage]) {
        self.pages = pages
    }

    func validateConnection() async throws -> NotionConnectionSnapshot {
        NotionConnectionSnapshot(workspaceName: "Workspace")
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        []
    }

    func searchDestinations(
        query: String,
        startCursor: String?
    ) async throws -> NotionDestinationSearchPage {
        recordedRequests.append(
            RuntimeDestinationSearchRequest(query: query, startCursor: startCursor)
        )
        guard !pages.isEmpty else {
            throw NotionAPIClientError.invalidResponse
        }
        return pages.removeFirst()
    }

    func requests() -> [RuntimeDestinationSearchRequest] {
        recordedRequests
    }
}

private actor DelayedDestinationSearchClient: NotionWorkspaceClient {
    private var startedQueries: Set<String> = []
    private var continuations: [String: CheckedContinuation<NotionDestinationSearchPage, Never>] = [:]

    func validateConnection() async throws -> NotionConnectionSnapshot {
        NotionConnectionSnapshot(workspaceName: "Workspace")
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        []
    }

    func searchDestinations(
        query: String,
        startCursor: String?
    ) async throws -> NotionDestinationSearchPage {
        startedQueries.insert(query)
        return await withCheckedContinuation { continuation in
            continuations[query] = continuation
        }
    }

    func waitUntilStarted(query: String) async {
        while !startedQueries.contains(query) {
            await Task.yield()
        }
    }

    func finish(query: String, with page: NotionDestinationSearchPage) {
        continuations.removeValue(forKey: query)?.resume(returning: page)
    }
}

private actor DelayedSearchClient: NotionWorkspaceClient {
    private let failing: Bool
    private var searchContinuation: CheckedContinuation<Void, Never>?
    private var searchStarted = false

    init(failing: Bool = false) {
        self.failing = failing
    }

    func validateConnection() async throws -> NotionConnectionSnapshot {
        NotionConnectionSnapshot(workspaceName: "Workspace")
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        searchStarted = true
        await withCheckedContinuation { searchContinuation = $0 }
        if failing {
            throw NotionAPIClientError.invalidResponse
        }
        let page = try! NotionPageReference(validating: URL(string: "https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef")!)
        return [NotionPageSearchResult(page: page, title: "Roadmap", lastEditedTime: "")]
    }

    func waitUntilSearchStarts() async {
        while !searchStarted { await Task.yield() }
    }

    func finishSearch() {
        searchContinuation?.resume()
        searchContinuation = nil
    }
}
