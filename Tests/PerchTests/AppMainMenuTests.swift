import AppKit
import WebKit
import XCTest
@testable import Perch

@MainActor
final class AppMainMenuTests: XCTestCase {
    func testViewMenuRoutesCommandRReloadThroughTheResponderChain() throws {
        let mainMenu = AppMainMenuFactory.make()
        let viewMenu = try XCTUnwrap(mainMenu.item(withTitle: "View")?.submenu)
        let reload = try XCTUnwrap(viewMenu.item(withTitle: "Reload"))

        XCTAssertTrue(viewMenu.autoenablesItems)
        XCTAssertEqual(reload.action, NSSelectorFromString("reload:"))
        XCTAssertNil(reload.target)
        XCTAssertEqual(reload.keyEquivalent, "r")
        XCTAssertEqual(reload.keyEquivalentModifierMask, [.command])
        XCTAssertTrue(WKWebView().responds(to: try XCTUnwrap(reload.action)))
    }

    func testEditMenuRoutesStandardCommandsThroughTheResponderChain() throws {
        let mainMenu = AppMainMenuFactory.make()
        let editMenu = try XCTUnwrap(mainMenu.item(withTitle: "Edit")?.submenu)

        XCTAssertTrue(editMenu.autoenablesItems)
        assertCommand(
            titled: "Undo",
            action: NSSelectorFromString("undo:"),
            keyEquivalent: "z",
            modifiers: [.command],
            in: editMenu
        )
        assertCommand(
            titled: "Redo",
            action: NSSelectorFromString("redo:"),
            keyEquivalent: "z",
            modifiers: [.command, .shift],
            in: editMenu
        )
        assertCommand(
            titled: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x",
            modifiers: [.command],
            in: editMenu
        )
        assertCommand(
            titled: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c",
            modifiers: [.command],
            in: editMenu
        )
        assertCommand(
            titled: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v",
            modifiers: [.command],
            in: editMenu
        )
        assertCommand(
            titled: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a",
            modifiers: [.command],
            in: editMenu
        )

        let windowResponder = NSWindow()
        for title in ["Undo", "Redo"] {
            let action = try XCTUnwrap(editMenu.item(withTitle: title)?.action)
            XCTAssertTrue(windowResponder.tryToPerform(action, with: nil))
        }
    }

    private func assertCommand(
        titled title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags,
        in menu: NSMenu,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let item = menu.item(withTitle: title) else {
            XCTFail("Missing \(title) command", file: file, line: line)
            return
        }

        XCTAssertEqual(item.action, action, file: file, line: line)
        XCTAssertNil(item.target, file: file, line: line)
        XCTAssertEqual(item.keyEquivalent, keyEquivalent, file: file, line: line)
        XCTAssertEqual(item.keyEquivalentModifierMask, modifiers, file: file, line: line)
    }
}
