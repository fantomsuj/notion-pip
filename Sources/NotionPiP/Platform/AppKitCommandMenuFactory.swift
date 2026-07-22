import AppKit

@MainActor
enum AppKitCommandMenuFactory {
    static func make(commandModel: AppCommandModel) -> NSMenu {
        let menu = NSMenu(title: "Notion PiP")
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
        return menu
    }
}
