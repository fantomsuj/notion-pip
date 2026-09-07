import AppKit

@MainActor
final class FlipStatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let runtime: FlipRuntime
    private let showPermissions: () -> Void

    init(
        runtime: FlipRuntime,
        showPermissions: @escaping () -> Void,
        statusBar: NSStatusBar = .system
    ) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        self.runtime = runtime
        self.showPermissions = showPermissions
        super.init()
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "rectangle.on.rectangle.angled",
            accessibilityDescription: FlipIdentity.displayName
        )
        button.toolTip = FlipIdentity.displayName
        button.setAccessibilityHelp("Flip the frontmost window to Notion, or restore it.")
        rebuildMenu()
        runtime.onSessionChanged = { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()
        let occupying = runtime.session.phase == .occupying
        let toggle = NSMenuItem(
            title: occupying ? "Flip Back" : "Flip Frontmost Window",
            action: #selector(toggleFlip),
            keyEquivalent: "f"
        )
        toggle.keyEquivalentModifierMask = [.command, .shift]
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let permissions = NSMenuItem(
            title: "Permissions…",
            action: #selector(openPermissions),
            keyEquivalent: ""
        )
        permissions.target = self
        menu.addItem(permissions)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Flip",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func toggleFlip() {
        runtime.handleShortcut()
    }

    @objc private func openPermissions() {
        showPermissions()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
