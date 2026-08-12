import AppKit
import Combine

enum StatusMenuContextCommand: Int, Equatable, Sendable {
    case stash = -1
    case show = -2
    case openSettings = -3

    var menuItemTag: Int {
        rawValue
    }

    init?(menuItemTag: Int) {
        self.init(rawValue: menuItemTag)
    }

    init(presentationState: PiPPresentationState) {
        switch presentationState {
        case .unavailable:
            self = .openSettings
        case .visible:
            self = .stash
        case .stashed:
            self = .show
        }
    }

    var title: String {
        switch self {
        case .stash:
            "Stash Perch"
        case .show:
            "Show Perch"
        case .openSettings:
            "Open Settings…"
        }
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let runtime: AppRuntime
    private let commandModel: AppCommandModel
    private let panelSizeController: PanelSizeController?
    private var visibilityCancellable: AnyCancellable?

    private lazy var eventRouter = StatusItemEventRouter(
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
            accessibilityDescription: "Perch"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Perch"
        button.setAccessibilityLabel("Perch")
        button.setAccessibilityHelp("Open commands for the pinned Notion page and app.")
        button.target = self
        button.action = #selector(handleStatusItemAction(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusItem.isVisible = runtime.effectiveMenuBarIconVisibility
        visibilityCancellable = runtime.$effectiveMenuBarIconVisibility
            .removeDuplicates()
            .sink { [weak statusItem] isVisible in
                statusItem?.isVisible = isVisible
            }
    }

    @objc
    private func handleStatusItemAction(_ sender: NSStatusBarButton) {
        guard let eventType = NSApp.currentEvent?.type else { return }
        eventRouter.handle(eventType: eventType)
    }

    private func showCommandMenu() {
        guard let button = statusItem.button else { return }
        let menu = AppKitCommandMenuFactory.makeStatusItemMenu(
            commandModel: commandModel,
            contextualCommand: runtime.statusMenuContextCommand,
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
            } else if StatusMenuContextCommand(menuItemTag: item.tag) != nil {
                item.target = self
                item.action = #selector(performContextualCommand(_:))
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

    @objc
    private func performContextualCommand(_ sender: NSMenuItem) {
        guard let command = StatusMenuContextCommand(menuItemTag: sender.tag) else { return }
        runtime.performStatusMenuContextCommand(command)
    }
}
