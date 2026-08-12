import AppKit

@MainActor
enum AppKitCommandMenuFactory {
    static let resetPanelSizeMarker = "panel-size:reset"
    static let managePanelSizesMarker = "panel-size:manage"

    static func makeStatusItemMenu(
        commandModel: AppCommandModel,
        contextualCommand: StatusMenuContextCommand,
        panelSizeController: PanelSizeController? = nil
    ) -> NSMenu {
        let menu = make(
            commandModel: commandModel,
            panelSizeController: panelSizeController
        )
        menu.insertItem(.separator(), at: 0)
        let contextualItem = NSMenuItem(
            title: contextualCommand.title,
            action: nil,
            keyEquivalent: ""
        )
        contextualItem.tag = contextualCommand.menuItemTag
        menu.insertItem(contextualItem, at: 0)
        return menu
    }

    static func make(
        commandModel: AppCommandModel,
        panelSizeController: PanelSizeController? = nil
    ) -> NSMenu {
        let menu = NSMenu(title: "Perch")
        menu.autoenablesItems = false
        for (groupIndex, group) in commandModel.groups.enumerated() {
            if groupIndex > 0 {
                menu.addItem(.separator())
            }
            for command in group.commands {
                let item = NSMenuItem(
                    title: command.title,
                    action: nil,
                    keyEquivalent: command.keyEquivalent
                )
                item.keyEquivalentModifierMask = command.modifierMask
                item.isEnabled = command.isEnabled
                item.tag = command.id.rawValue
                menu.addItem(item)
            }
        }
        if let panelSizeController {
            menu.addItem(.separator())
            menu.addItem(panelSizeMenuItem(controller: panelSizeController))
        }
        return menu
    }

    private static func panelSizeMenuItem(
        controller: PanelSizeController
    ) -> NSMenuItem {
        let parent = NSMenuItem(title: "Panel Size", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Panel Size")
        submenu.autoenablesItems = false

        for preset in controller.presets {
            let item = NSMenuItem(
                title: controller.displayName(for: preset),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = controller.canApply
            item.representedObject = preset.id.rawValue
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let reset = NSMenuItem(
            title: "Reset to Vertical",
            action: nil,
            keyEquivalent: ""
        )
        reset.isEnabled = controller.canApply
        reset.representedObject = resetPanelSizeMarker
        submenu.addItem(reset)

        let manage = NSMenuItem(
            title: "Manage Panel Sizes…",
            action: nil,
            keyEquivalent: ""
        )
        manage.isEnabled = true
        manage.representedObject = managePanelSizesMarker
        submenu.addItem(manage)

        parent.submenu = submenu
        return parent
    }
}
