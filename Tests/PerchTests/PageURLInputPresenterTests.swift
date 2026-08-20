import AppKit
import Foundation
import XCTest
@testable import Perch

@MainActor
final class CurrentPageSetupTests: XCTestCase {
    private let firstPageID = "0123456789abcdef0123456789abcdef"
    private let secondPageID = "fedcba9876543210fedcba9876543210"

    func testShortcutWithoutCurrentPagePresentsSettingsAndFocusesEntryWithoutValidation() {
        let panel = FakePanelCoordinator()
        let settings = PageInputSettingsPresenterSpy()
        let shortcut = PresenterTestShortcutRegistrar()
        let runtime = AppRuntime(
            panelCoordinator: panel,
            pasteboard: PresenterTestPasteboard(value: "not a Notion URL"),
            shortcutRegistrar: shortcut
        )
        runtime.bind(settingsWindowPresenter: settings)
        runtime.start()

        shortcut.handler?()

        XCTAssertEqual(settings.showCount, 1)
        XCTAssertEqual(runtime.pageURLFocusRequest, 1)
        XCTAssertNil(runtime.activePage)
        XCTAssertNil(runtime.pendingPage)
        XCTAssertNil(runtime.lastActivationSource)
        XCTAssertNil(panel.currentPage)
        XCTAssertFalse(runtime.validationFailed)
        XCTAssertNil(runtime.validationMessage)
        XCTAssertTrue(panel.replacedPages.isEmpty)
    }

    func testNoPageInputUsesSettingsAndRequestsFieldFocus() {
        let settings = PageInputSettingsPresenterSpy()
        let runtime = AppRuntime(
            panelCoordinator: FakePanelCoordinator(),
            pasteboard: PresenterTestPasteboard(value: nil),
            shortcutRegistrar: PresenterTestShortcutRegistrar()
        )
        runtime.bind(settingsWindowPresenter: settings)

        runtime.presentCurrentPageSetup()

        XCTAssertEqual(settings.showCount, 1)
        XCTAssertEqual(runtime.pageURLFocusRequest, 1)
    }

    func testValidEntrySubmissionUsesPinCoordinator() throws {
        let panel = FakePanelCoordinator()
        let runtime = AppRuntime(
            panelCoordinator: panel,
            pasteboard: PresenterTestPasteboard(value: nil),
            shortcutRegistrar: PresenterTestShortcutRegistrar()
        )
        let activePage = try makePage(id: firstPageID, title: "Current")
        runtime.pin(page: activePage)
        runtime.pageURLText = "https://www.notion.so/Next-\(secondPageID)"

        let opened = runtime.validatePageURL()

        XCTAssertTrue(opened)
        XCTAssertEqual(panel.replacedPages.map(\.pageID), [secondPageID])
        XCTAssertEqual(runtime.activePage?.pageID, secondPageID)
        XCTAssertFalse(runtime.validationFailed)
    }

    func testInvalidEntrySubmissionStaysVisibleWithValidationFeedback() {
        let runtime = AppRuntime(
            panelCoordinator: FakePanelCoordinator(),
            pasteboard: PresenterTestPasteboard(value: nil),
            shortcutRegistrar: PresenterTestShortcutRegistrar()
        )
        runtime.pageURLText = "https://example.com/not-notion"

        let opened = runtime.validatePageURL()

        XCTAssertFalse(opened)
        XCTAssertTrue(runtime.validationFailed)
        XCTAssertEqual(
            runtime.validationMessage,
            "Use an HTTPS Notion page URL with a page ID."
        )
    }

    private func makePage(id: String, title: String) throws -> NotionPageReference {
        try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/\(title)-\(id)"))
        )
    }
}

@MainActor
private final class PageInputSettingsPresenterSpy: SettingsWindowPresenting {
    private(set) var showCount = 0

    func show() {
        showCount += 1
    }
}

private struct PresenterTestPasteboard: PasteboardReading {
    let value: String?

    func readString() -> String? {
        value
    }
}

@MainActor
private final class PresenterTestShortcutRegistrar: GlobalShortcutRegistering {
    private(set) var handler: (@MainActor () -> Void)?

    func register(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        self.handler = handler
    }

    func revalidate() throws {}
    func unregister() {}
}
