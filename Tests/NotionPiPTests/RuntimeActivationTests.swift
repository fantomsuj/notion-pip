import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class RuntimeActivationTests: XCTestCase {
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

    func testMenuBarActivationWithoutCurrentPageShowsSetupOptions() {
        let panel = RuntimePanelCoordinator()
        let setup = RuntimeSetupOptionsPresenter()
        let runtime = makeRuntime(panel: panel)
        runtime.bind(setupOptionsPresenter: setup)

        runtime.handleMenuBarActivation()

        XCTAssertEqual(setup.showCount, 1)
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

    func testMenuBarActivationFallsBackToSetupWhenRuntimeAndPanelDisagree() throws {
        let panel = RuntimePanelCoordinator()
        let setup = RuntimeSetupOptionsPresenter()
        let runtime = makeRuntime(panel: panel)
        runtime.bind(setupOptionsPresenter: setup)
        runtime.activate(
            page: try makePage(id: firstPageID, title: "Roadmap"),
            source: .typedURL
        )
        panel.loseCurrentPage()

        runtime.handleMenuBarActivation()

        XCTAssertEqual(setup.showCount, 1)
        XCTAssertFalse(panel.isVisible)
    }

    func testSuccessfulPageActivationDismissesSetupOptions() throws {
        let panel = RuntimePanelCoordinator()
        let setup = RuntimeSetupOptionsPresenter()
        let runtime = makeRuntime(panel: panel)
        runtime.bind(setupOptionsPresenter: setup)
        setup.show()

        runtime.activate(
            page: try makePage(id: firstPageID, title: "Roadmap"),
            source: .typedURL
        )

        XCTAssertFalse(setup.isShown)
        XCTAssertEqual(setup.hideCount, 1)
    }

    func testNewestActivationPreventsLatePreviewFromReplacingIt() async throws {
        let panel = RuntimePanelCoordinator()
        let client = DelayedPreviewClient()
        let runtime = makeRuntime(panel: panel, client: client)
        let firstPage = try makePage(id: firstPageID, title: "First")
        let secondPage = try makePage(id: secondPageID, title: "Second")

        await runtime.bootstrapPersonalTokenConnection()
        runtime.activate(page: firstPage, source: .typedURL)
        await client.waitUntilFirstPreviewStarts()
        runtime.activate(page: secondPage, source: .notionSearch)
        await client.waitUntilSecondPreviewStarts()
        await client.finishFirstPreview()
        await client.waitUntilSecondPreviewPublishes()

        XCTAssertEqual(runtime.activePage, secondPage)
        XCTAssertEqual(runtime.nativePageDocument.snapshot?.pageID, secondPageID)
        XCTAssertEqual(runtime.nativePageDocument.snapshot?.title, "Second")
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
        XCTAssertEqual(panel.replacedPages.map(\.pageID), [secondPageID])
    }

    func testDisconnectPreventsLatePreviewFromRepopulatingClearedCache() async throws {
        let client = DelayedPreviewClient()
        let runtime = makeRuntime(panel: RuntimePanelCoordinator(), client: client)
        let page = try makePage(id: firstPageID, title: "First")

        await runtime.bootstrapPersonalTokenConnection()
        runtime.activate(page: page, source: .typedURL)
        await client.waitUntilFirstPreviewStarts()
        runtime.disconnectPersonalToken()
        await client.finishFirstPreview()
        for _ in 0 ..< 3 { await Task.yield() }

        XCTAssertNil(runtime.nativePageDocument.snapshot)
        XCTAssertEqual(runtime.nativePageDocument.previewState, .idle)
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
        for _ in 0 ..< 3 { await Task.yield() }

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.currentPage, first)

        runtime.activate(page: second, source: .notionSearch)
        try await repository.waitUntilSaveCount(2)
        let savedPageIDs = await repository.savedPageIDs()

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
        client: any NotionWorkspaceClient = ImmediatePreviewClient()
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
            notionClientFactory: { _ in client }
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
    private(set) var replacedPages: [NotionPageReference] = []
    private(set) var isVisible = false
    private(set) var isStashed = false

    func show(page: NotionPageReference) {
        currentPage = page
        shownPages.append(page)
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
private final class RuntimeSetupOptionsPresenter: SetupOptionsPresenting {
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var isShown = false

    func show() {
        showCount += 1
        isShown = true
    }

    func hide() {
        hideCount += 1
        isShown = false
    }
    func toggle() {}
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
    func register(handler: @escaping @MainActor () -> Void) throws { self.handler = handler }
    func unregister() {}
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
}

private enum RuntimeTestWaitError: Error {
    case timedOut(String)
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

    func waitUntilRestoreRequested() async throws {
        try await waitUntil({ restoreRequests > 0 }, operation: "restore request")
    }

    func finishRestore(with page: StoredPageSnapshot?) {
        restoreContinuation?.resume(returning: page)
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

private actor ImmediatePreviewClient: NotionWorkspaceClient {
    func validateConnection() async throws -> NotionConnectionSnapshot { NotionConnectionSnapshot(workspaceName: "Workspace") }
    func searchPages(query: String) async throws -> [NotionPageSearchResult] { [] }
    func fetchPagePreview(page: NotionPageReference) async throws -> NativePageSnapshot {
        NativePageSnapshot(pageID: page.pageID, title: page.displayTitle ?? "Preview", blocks: [], remoteFingerprint: "", fetchedAt: Date())
    }
}

private actor DelayedPreviewClient: NotionWorkspaceClient {
    private var firstContinuation: CheckedContinuation<Void, Never>?
    private var firstStarted = false
    private var secondStarted = false
    private var secondPublished = false

    func validateConnection() async throws -> NotionConnectionSnapshot {
        NotionConnectionSnapshot(workspaceName: "Workspace")
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] { [] }

    func fetchPagePreview(page: NotionPageReference) async throws -> NativePageSnapshot {
        if !firstStarted {
            firstStarted = true
            await withCheckedContinuation { firstContinuation = $0 }
            return NativePageSnapshot(pageID: page.pageID, title: "First", blocks: [], remoteFingerprint: "", fetchedAt: Date())
        }
        secondStarted = true
        secondPublished = true
        return NativePageSnapshot(pageID: page.pageID, title: "Second", blocks: [], remoteFingerprint: "", fetchedAt: Date())
    }

    func finishFirstPreview() { firstContinuation?.resume() }

    func waitUntilFirstPreviewStarts() async { while !firstStarted { await Task.yield() } }
    func waitUntilSecondPreviewStarts() async { while !secondStarted { await Task.yield() } }
    func waitUntilSecondPreviewPublishes() async { while !secondPublished { await Task.yield() } }
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

    func fetchPagePreview(page: NotionPageReference) async throws -> NativePageSnapshot {
        NativePageSnapshot(pageID: page.pageID, title: "Unused", blocks: [], remoteFingerprint: "", fetchedAt: Date())
    }

    func waitUntilSearchStarts() async {
        while !searchStarted { await Task.yield() }
    }

    func finishSearch() {
        searchContinuation?.resume()
        searchContinuation = nil
    }
}
