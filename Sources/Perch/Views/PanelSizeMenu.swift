import SwiftUI

struct PanelSizeMenu: View {
    @ObservedObject var controller: PanelSizeController

    var body: some View {
        Menu("Panel Size") {
            ForEach(controller.presets) { preset in
                Button(controller.displayName(for: preset)) {
                    controller.apply(preset.id)
                }
                .disabled(!controller.canApply)
            }

            Divider()

            Button("Reset to Vertical") {
                controller.resetToDefault()
            }
            .disabled(!controller.canApply)

            Button("Manage Panel Sizes…") {
                controller.managePanelSizes()
            }
        }
    }
}
