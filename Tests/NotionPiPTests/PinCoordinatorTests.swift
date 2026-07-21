import AppKit
import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class PinCoordinatorTests: XCTestCase {
    private let firstPageID = "0123456789abcdef0123456789abcdef"
    private let secondPageID = "fedcba9876543210fedcba9876543210"

    func testPanelCoordinatorDeduplicatesSamePageLoadWhileForegroundingPanel() throws {
        let panel = FakePanelWindow()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: loader)
        let page = try makePage(id: firstPageID, title: "Roadmap")

        coordinator.show(page: page)
        coordinator.show(page: page)

        XCTAssertEqual(loader.loadedPages.map(\.pageID), [firstPageID])
        XCTAssertEqual(panel.presentCount, 2)
        XCTAssertEqual(coordinator.currentPage?.pageID, firstPageID)
    }

    func testPanelCoordinatorReplacesPageInExistingPanel() throws {
        let panel = FakePanelWindow()
        let loader = FakePageLoader()
        let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: loader)
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")

        coordinator.show(page: firstPage)
        coordinator.replace(page: secondPage)

        XCTAssertEqual(loader.loadedPages.map(\.pageID), [firstPageID, secondPageID])
        XCTAssertEqual(panel.presentCount, 2)
        XCTAssertEqual(coordinator.currentPage?.pageID, secondPageID)
    }

    func testPinCoordinatorUsesReplaceForDifferentActivePage() throws {
        let panel = FakePanelCoordinator()
        let coordinator = PinCoordinator(
            panelCoordinator: panel,
            pasteboard: FakePasteboard(value: nil),
            requestPageURLFocus: {}
        )
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")

        coordinator.pin(page: firstPage)
        coordinator.pin(page: secondPage)

        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
        XCTAssertEqual(panel.replacedPages.map(\.pageID), [secondPageID])
    }

    func testOpenURLsAcceptsCanonicalRoute() throws {
        let panel = FakePanelCoordinator()
        let coordinator = PinCoordinator(
            panelCoordinator: panel,
            pasteboard: FakePasteboard(value: nil),
            requestPageURLFocus: {}
        )
        let routeURL = try XCTUnwrap(
            URL(
                string: "notion-pip://pin?url=https%3A%2F%2Fwww.notion.so%2F\(firstPageID)&source=chrome-extension"
            )
        )

        coordinator.handleOpenURLs([routeURL])

        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
    }

    func testAppDelegateBuffersOpenURLsUntilBindingAndDrainsOnlyOnce() throws {
        let appDelegate = AppDelegate()
        let handler = FakeApplicationURLHandler()
        let routeURL = try XCTUnwrap(
            URL(
                string: "notion-pip://pin?url=https%3A%2F%2Fwww.notion.so%2F\(firstPageID)&source=chrome-extension"
            )
        )

        appDelegate.application(NSApplication.shared, open: [routeURL])
        XCTAssertTrue(handler.deliveries.isEmpty)

        appDelegate.bind(urlHandler: handler)
        appDelegate.bind(urlHandler: handler)

        XCTAssertEqual(handler.deliveries, [[routeURL]])
    }

    func testMenuDisplayTitleIsLimitedToThirtyCharacters() throws {
        let page = try makePage(
            id: firstPageID,
            title: "12345678901234567890123456789012345"
        )

        let title = PagePickerDisplay.title(for: page)

        XCTAssertEqual(title, "12345678901234567890123456789…")
        XCTAssertEqual(title.count, 30)
    }

    func testAppRuntimeRegistersShortcutOnlyOnce() {
        let shortcut = FakeShortcutRegistrar()
        let runtime = AppRuntime(
            panelCoordinator: FakePanelCoordinator(),
            pasteboard: FakePasteboard(value: nil),
            shortcutRegistrar: shortcut
        )

        runtime.start()
        runtime.start()

        XCTAssertEqual(shortcut.registerCount, 1)
        XCTAssertNotNil(shortcut.handler)
    }

    private func makePage(id: String, title: String) throws -> NotionPageReference {
        try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/\(title)-\(id)"))
        )
    }
}

@MainActor
private final class FakePanelWindow: PiPPanelWindow {
    private(set) var presentCount = 0
    private(set) var orderOutCount = 0

    func present() {
        presentCount += 1
    }

    func orderOut() {
        orderOutCount += 1
    }
}

@MainActor
private final class FakePageLoader: NotionPageLoading {
    private(set) var loadedPages: [NotionPageReference] = []

    func load(page: NotionPageReference) {
        loadedPages.append(page)
    }
}

@MainActor
final class FakePanelCoordinator: PiPPanelCoordinating {
    private(set) var currentPage: NotionPageReference?
    private(set) var shownPages: [NotionPageReference] = []
    private(set) var replacedPages: [NotionPageReference] = []
    private(set) var hideCount = 0

    func show(page: NotionPageReference) {
        currentPage = page
        shownPages.append(page)
    }

    func replace(page: NotionPageReference) {
        currentPage = page
        replacedPages.append(page)
    }

    func hide() {
        hideCount += 1
    }
}

struct FakePasteboard: PasteboardReading {
    let value: String?

    func readString() -> String? {
        value
    }
}

@MainActor
private final class FakeApplicationURLHandler: ApplicationURLHandling {
    private(set) var deliveries: [[URL]] = []

    func handleOpenURLs(_ urls: [URL]) {
        deliveries.append(urls)
    }
}

@MainActor
private final class FakeShortcutRegistrar: GlobalShortcutRegistering {
    private(set) var registerCount = 0
    private(set) var handler: (@MainActor () -> Void)?

    func register(handler: @escaping @MainActor () -> Void) throws {
        registerCount += 1
        self.handler = handler
    }

    func unregister() {}
}
