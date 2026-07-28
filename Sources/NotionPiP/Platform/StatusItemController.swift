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
            "Stash Notion PiP"
        case .show:
            "Show Notion PiP"
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
    private var visibilityCancellable: AnyCancellable?

    private lazy var eventRouter = StatusItemEventRouter(
        onMenu: { [weak self] in
            self?.showCommandMenu()
        }
    )

    init(
        runtime: AppRuntime,
        commandModel: AppCommandModel,
        statusBar: NSStatusBar = .system
    ) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        self.runtime = runtime
        self.commandModel = commandModel
        super.init()

        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "Notion PiP"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Notion PiP"
        button.setAccessibilityLabel("Notion PiP")
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
            contextualCommand: runtime.statusMenuContextCommand
        )
        for item in menu.items where !item.isSeparatorItem {
            item.target = self
            item.action = StatusMenuContextCommand(menuItemTag: item.tag) != nil
                ? #selector(performContextualCommand(_:))
                : #selector(performCommand(_:))
        }
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

    @objc
    private func performContextualCommand(_ sender: NSMenuItem) {
        guard let command = StatusMenuContextCommand(menuItemTag: sender.tag) else { return }
        runtime.performStatusMenuContextCommand(command)
    }
}
