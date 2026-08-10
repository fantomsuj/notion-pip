import AppKit

@MainActor
enum AppMainMenuFactory {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = makeEditMenu()
        mainMenu.addItem(editMenuItem)
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenuItem.submenu = makeViewMenu()
        mainMenu.addItem(viewMenuItem)
        return mainMenu
    }

    private static func makeViewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.autoenablesItems = true
        menu.addItem(
            command(
                title: "Reload",
                action: NSSelectorFromString("reload:"),
                keyEquivalent: "r"
            )
        )
        return menu
    }

    private static func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.autoenablesItems = true
        menu.addItem(
            command(
                title: "Undo",
                action: NSSelectorFromString("undo:"),
                keyEquivalent: "z"
            )
        )
        menu.addItem(
            command(
                title: "Redo",
                action: NSSelectorFromString("redo:"),
                keyEquivalent: "z",
                modifiers: [.command, .shift]
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            command(
                title: "Cut",
                action: #selector(NSText.cut(_:)),
                keyEquivalent: "x"
            )
        )
        menu.addItem(
            command(
                title: "Copy",
                action: #selector(NSText.copy(_:)),
                keyEquivalent: "c"
            )
        )
        menu.addItem(
            command(
                title: "Paste",
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            command(
                title: "Select All",
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            )
        )
        return menu
    }

    private static func command(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: keyEquivalent
        )
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
