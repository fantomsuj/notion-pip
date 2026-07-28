import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let runtime: AppRuntime
    private let commandModel: AppCommandModel
    private let panelSizeController: PanelSizeController?

    private lazy var eventRouter = StatusItemEventRouter(
        onRegularClick: { [weak self] in
            self?.runtime.handleMenuBarActivation()
        },
        onMenu: { [weak self] in
            self?.showCommandMenu()
        }
    )

    init(
        runtime: AppRuntime,
        commandModel: AppCommandModel,
        panelSizeController: PanelSizeController? = nil,
        statusBar: NSStatusBar = .system
    ) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        self.runtime = runtime
        self.commandModel = commandModel
        self.panelSizeController = panelSizeController
        super.init()

        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "Notion PiP"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Show or hide Notion PiP. Right-click for menu."
        button.setAccessibilityLabel("Notion PiP")
        button.setAccessibilityHelp(
            "Show or hide the pinned Notion page. Right-click for app commands.")
        button.target = self
        button.action = #selector(handleStatusItemAction(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc
    private func handleStatusItemAction(_ sender: NSStatusBarButton) {
        guard let eventType = NSApp.currentEvent?.type else { return }
        eventRouter.handle(eventType: eventType)
    }

    private func showCommandMenu() {
        guard let button = statusItem.button else { return }
        let menu = AppKitCommandMenuFactory.make(
            commandModel: commandModel,
            panelSizeController: panelSizeController
        )
        configureActions(in: menu)
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.minX, y: button.bounds.minY),
            in: button
        )
    }

    @objc
    private func performCommand(_ sender: NSMenuItem) {
        guard let id = AppCommandID(rawValue: sender.tag) else { return }
        commandModel.perform(id)
    }

    private func configureActions(in menu: NSMenu) {
        for item in menu.items where !item.isSeparatorItem {
            if let submenu = item.submenu {
                configurePanelSizeActions(in: submenu)
            } else if AppCommandID(rawValue: item.tag) != nil {
                item.target = self
                item.action = #selector(performCommand(_:))
            }
        }
    }

    private func configurePanelSizeActions(in menu: NSMenu) {
        for item in menu.items where !item.isSeparatorItem {
            item.target = self
            switch item.representedObject as? String {
            case AppKitCommandMenuFactory.resetPanelSizeMarker:
                item.action = #selector(resetPanelSize(_:))
            case AppKitCommandMenuFactory.managePanelSizesMarker:
                item.action = #selector(managePanelSizes(_:))
            case .some:
                item.action = #selector(applyPanelSizePreset(_:))
            case nil:
                item.target = nil
            }
        }
    }

    @objc
    private func applyPanelSizePreset(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
            let id = PanelSizePresetID(rawValue: rawID)
        else {
            return
        }
        panelSizeController?.apply(id)
    }

    @objc
    private func resetPanelSize(_ sender: NSMenuItem) {
        panelSizeController?.resetToDefault()
    }

    @objc
    private func managePanelSizes(_ sender: NSMenuItem) {
        panelSizeController?.managePanelSizes()
    }
}
