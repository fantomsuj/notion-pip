import AppKit
import SwiftUI

struct PiPAppCommandMenu: View {
    let commandModel: AppCommandModel
    var panelSizeController: PanelSizeController? = nil

    var commandIDs: [AppCommandID] {
        commandModel.commands.map(\.id)
    }

    let symbolName = "ellipsis"

    var body: some View {
        Menu {
            ForEach(Array(commandModel.groups.enumerated()), id: \.offset) { groupIndex, group in
                if groupIndex > 0 {
                    Divider()
                }
                ForEach(group.commands, id: \.id) { command in
                    commandButton(command)
                }
            }
            if let panelSizeController {
                Divider()
                PanelSizeMenu(controller: panelSizeController)
            }
        } label: {
            Image(systemName: symbolName)
                .frame(
                    width: PanelCornerControls.minimumHitTarget,
                    height: PanelCornerControls.minimumHitTarget
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("App menu")
    }

    @ViewBuilder
    private func commandButton(_ command: AppCommand) -> some View {
        if let character = command.keyEquivalent.first {
            Button(command.title) {
                command.perform()
            }
            .keyboardShortcut(
                KeyEquivalent(character),
                modifiers: eventModifiers(command.modifierMask)
            )
            .disabled(!command.isEnabled)
        } else {
            Button(command.title) {
                command.perform()
            }
            .disabled(!command.isEnabled)
        }
    }

    private func eventModifiers(_ modifiers: NSEvent.ModifierFlags) -> EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }
}
