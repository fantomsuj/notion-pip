import Foundation
import XCTest
@testable import Perch

@MainActor
final class RuntimeCustomPinnedURLTests: XCTestCase {
    func testAddingACustomURLPinsItAndKeepsTheNotionPageForReturn() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let notionPage = try makePage(id: firstPageID, title: "Roadmap")
        runtime.pin(page: notionPage)
        runtime.setCustomPinnedURLsEnabled(true)
        runtime.customPinnedURLInputState.text = "https://canvas.example.edu/courses/12"

        XCTAssertTrue(runtime.addCustomPinnedURL())

        XCTAssertEqual(runtime.activeCustomURL?.host, "canvas.example.edu")
        XCTAssertEqual(runtime.activePage, notionPage)
        XCTAssertEqual(panel.shownCustomURLs.last?.host, "canvas.example.edu")
        XCTAssertEqual(runtime.lastActivationSource, .customPinnedURL)
        XCTAssertTrue(runtime.customPinnedURLsEnabled)
        XCTAssertEqual(runtime.customPinnedURLs.map(\.host), ["canvas.example.edu"])
        XCTAssertTrue(runtime.customPinnedURLInputState.text.isEmpty)
    }

    func testReturningFromACustomURLRestoresTheLastNotionPage() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let notionPage = try makePage(id: firstPageID, title: "Roadmap")
        runtime.pin(page: notionPage)
        runtime.setCustomPinnedURLsEnabled(true)
        runtime.customPinnedURLInputState.text = "https://canvas.example.edu"
        XCTAssertTrue(runtime.addCustomPinnedURL())

        runtime.returnToNotionPage()

        XCTAssertNil(runtime.activeCustomURL)
        XCTAssertEqual(runtime.activePage, notionPage)
        XCTAssertEqual(panel.replacedPages.last, notionPage)
        XCTAssertNil(panel.currentCustomURL)
    }

    func testDisablingTheBetaFeatureReturnsToNotionWithoutDeletingSavedPins() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let notionPage = try makePage(id: firstPageID, title: "Roadmap")
        runtime.pin(page: notionPage)
        runtime.setCustomPinnedURLsEnabled(true)
        runtime.customPinnedURLInputState.text = "https://canvas.example.edu"
        XCTAssertTrue(runtime.addCustomPinnedURL())

        runtime.setCustomPinnedURLsEnabled(false)

        XCTAssertFalse(runtime.customPinnedURLsEnabled)
        XCTAssertNil(runtime.activeCustomURL)
        XCTAssertEqual(runtime.customPinnedURLs.map(\.host), ["canvas.example.edu"])
        XCTAssertEqual(panel.replacedPages.last, notionPage)
    }

    func testANotionURLEnteredInTheCustomFieldUsesTheNormalPinFlow() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        runtime.setCustomPinnedURLsEnabled(true)
        runtime.customPinnedURLInputState.text =
            "https://www.notion.so/Notes-\(secondPageID)"

        XCTAssertTrue(runtime.addCustomPinnedURL())

        XCTAssertNil(runtime.activeCustomURL)
        XCTAssertEqual(runtime.activePage?.pageID, secondPageID)
        XCTAssertTrue(runtime.customPinnedURLs.isEmpty)
        XCTAssertEqual(runtime.lastActivationSource, .typedURL)
    }

    func testReloadingACustomPinReloadsTheCustomURLInsteadOfTheNotionPage() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        runtime.pin(page: try makePage(id: firstPageID, title: "Roadmap"))
        runtime.setCustomPinnedURLsEnabled(true)
        runtime.customPinnedURLInputState.text = "https://canvas.example.edu"
        XCTAssertTrue(runtime.addCustomPinnedURL())

        runtime.reloadSavedPin()

        XCTAssertEqual(panel.reloadedCustomURLs.map(\.host), ["canvas.example.edu"])
        XCTAssertTrue(panel.reloadedPages.isEmpty)
    }

    func testLaunchRestoresTheLastCustomURLOverTheSavedNotionPage() async throws {
        let panel = RuntimePanelCoordinator()
        let store = CustomPinnedURLStore(
            defaults: UserDefaults(suiteName: "RuntimeCustomPinRestore.\(UUID().uuidString)")!
        )
        let pin = try CustomPinnedURL(validatingString: "https://canvas.example.edu")
        store.save(
            CustomPinnedURLSnapshot(isEnabled: true, pins: [pin], lastActiveID: pin.id)
        )
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            customPinnedURLStore: store
        )
        let storedPage = try makeStoredPage(id: firstPageID, title: "Roadmap")

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: storedPage)
        await waitUntilRuntimeCondition { runtime.activeCustomURL?.id == pin.id }

        XCTAssertEqual(runtime.activePage?.pageID, firstPageID)
        XCTAssertEqual(runtime.activeCustomURL?.host, "canvas.example.edu")
        XCTAssertEqual(panel.shownCustomURLs.last?.host, "canvas.example.edu")
    }

    func testRemovingTheActiveCustomURLReturnsToNotion() throws {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let notionPage = try makePage(id: firstPageID, title: "Roadmap")
        runtime.pin(page: notionPage)
        runtime.setCustomPinnedURLsEnabled(true)
        runtime.customPinnedURLInputState.text = "https://canvas.example.edu"
        XCTAssertTrue(runtime.addCustomPinnedURL())
        let pin = try XCTUnwrap(runtime.activeCustomURL)

        runtime.removeCustomPinnedURL(pin)

        XCTAssertTrue(runtime.customPinnedURLs.isEmpty)
        XCTAssertNil(runtime.activeCustomURL)
        XCTAssertEqual(panel.replacedPages.last, notionPage)
    }
}

final class PiPDestinationChromeTests: XCTestCase {
    func testCustomPinnedChromeHidesNotionActionsAndOffersAReturnPath() {
        XCTAssertTrue(PiPDestinationChrome.notion.showsNotionPageActions)
        XCTAssertFalse(PiPDestinationChrome.customPinned.showsNotionPageActions)
        XCTAssertEqual(
            PiPDestinationChrome.customPinned.showNotionAccessibilityLabel,
            "Show Notion page"
        )
        XCTAssertEqual(
            PiPDestinationChrome.customPinned.failedLoadMessage,
            "This page couldn't load."
        )
        XCTAssertEqual(
            PiPDestinationChrome(isShowingCustomURL: true),
            .customPinned
        )
    }
}
