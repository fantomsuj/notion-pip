import AppKit
import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class RuntimePinnedPagePersistenceTests: XCTestCase {
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

    func testStartRestoresSavedPageIntoVisiblePanel() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let storedPage = try makeStoredPage(id: firstPageID, title: "Roadmap")

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: storedPage)
        await waitUntilRuntimeCondition { runtime.activePage?.pageID == firstPageID }

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
        await waitUntilRuntimeCondition { runtime.activePage?.pageID == firstPageID }

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

    func testNoSavedPageOpensSettingsAfterRestoreCompletes() async throws {
        let settings = RuntimeSettingsWindowPresenter()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            pageRepository: repository
        )
        runtime.bind(settingsWindowPresenter: settings)

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: nil)
        try await repository.waitUntilRestoreReturned()
        await waitUntilRuntimeCondition { settings.showCount == 1 }

        XCTAssertNil(runtime.activePage)
        XCTAssertEqual(settings.showCount, 1)
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
        await waitUntilRuntimeCondition {
            runtime.serviceHealth.issues.contains(.pinnedPagePersistenceUnavailable)
        }

        runtime.retryRecovery(for: .pinnedPagePersistenceUnavailable)
        try await repository.waitUntilRestoreRequested(count: 2)
        await repository.finishRestore(with: nil)
        await waitUntilRuntimeCondition {
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
            validating: XCTUnwrap(
                URL(string: "https://www.notion.so/\(secondPageID)")
            )
        )
        let route = try XCTUnwrap(
            URL(
                string: """
                notion-pip://pin?url=https%3A%2F%2Fwww.notion.so%2F\(secondPageID)\
                &source=chrome-extension
                """
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
        XCTAssertEqual(
            runtime.lastActivationSource,
            .externalRoute(.chromeExtension)
        )
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

    func testDirectActivationSuppressesSettingsAfterEmptyRestore() async throws {
        let settings = RuntimeSettingsWindowPresenter()
        let repository = RuntimePinnedPageRepository()
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let directPage = try makePage(id: secondPageID, title: "Direct")
        runtime.bind(settingsWindowPresenter: settings)

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        runtime.activate(page: directPage, source: .typedURL)
        await repository.finishRestore(with: nil)
        for _ in 0 ..< 10 { await Task.yield() }

        XCTAssertEqual(runtime.activePage, directPage)
        XCTAssertEqual(panel.currentPage, directPage)
        XCTAssertEqual(settings.showCount, 0)
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
        await waitUntilRuntimeCondition { runtime.activePage?.pageID == firstPageID }

        XCTAssertEqual(runtime.activePage?.pageID, firstPageID)
        XCTAssertEqual(runtime.lastActivationSource, .restored)
        XCTAssertTrue(panel.isVisible)
    }

    func testActivationPersistsCanonicalReplacement() async throws {
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            pageRepository: repository
        )
        let page = try NotionPageReference(
            validating: XCTUnwrap(
                URL(
                    string: """
                    https://notion.so/Roadmap-\(firstPageID)?source=test#fragment
                    """
                )
            )
        )

        runtime.activate(page: page, source: .pagePicker)
        try await repository.waitUntilSaveCount(1)
        let savedPages = await repository.savedPages()

        XCTAssertEqual(savedPages, [page])
        XCTAssertEqual(savedPages.first?.canonicalURL, page.canonicalURL)
    }

    func testRapidActivationsPersistInActivationOrder() async throws {
        let repository = RuntimePinnedPageRepository(delaySaves: true)
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            pageRepository: repository
        )
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
        let repository = RuntimePinnedPageRepository(
            failingPageIDs: [firstPageID]
        )
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let first = try makePage(id: firstPageID, title: "First")
        let second = try makePage(id: secondPageID, title: "Second")

        runtime.activate(page: first, source: .typedURL)
        try await repository.waitUntilFailedSaveCount(1)
        await waitUntilRuntimeCondition {
            runtime.serviceHealth.issues.contains(.pinnedPagePersistenceUnavailable)
        }

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.currentPage, first)

        runtime.activate(page: second, source: .notionSearch)
        try await repository.waitUntilSaveCount(2)
        let savedPageIDs = await repository.savedPageIDs()
        await waitUntilRuntimeCondition {
            !runtime.serviceHealth.issues.contains(.pinnedPagePersistenceUnavailable)
        }

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.currentPage, second)
        XCTAssertEqual(savedPageIDs, [firstPageID, secondPageID])
    }

    func testCorruptRestoredPageLeavesRuntimeEmpty() async throws {
        let panel = RuntimePanelCoordinator()
        let settings = RuntimeSettingsWindowPresenter()
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(panel: panel, pageRepository: repository)
        let mismatchedPage = try makeStoredPage(id: secondPageID, title: "Mismatch")
        let corruptPage = StoredPageSnapshot(
            pageID: firstPageID,
            canonicalURL: mismatchedPage.canonicalURL,
            displayTitle: mismatchedPage.displayTitle,
            timestamp: mismatchedPage.timestamp
        )
        runtime.bind(settingsWindowPresenter: settings)

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: corruptPage)
        try await repository.waitUntilRestoreReturned()
        for _ in 0 ..< 3 { await Task.yield() }

        XCTAssertNil(runtime.activePage)
        XCTAssertNil(runtime.lastActivationSource)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(settings.showCount, 1)
    }

    func testStartingTwiceRequestsRestoreOnce() async throws {
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            pageRepository: repository
        )

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        runtime.start()
        for _ in 0 ..< 3 { await Task.yield() }
        let restoreRequestCount = await repository.restoreRequestCount()

        XCTAssertEqual(restoreRequestCount, 1)
        await repository.finishRestore(with: nil)
    }
}
