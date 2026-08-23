import SwiftUI

struct PanelSizeMenu: View {
    @ObservedObject var controller: PanelSizeController

    var body: some View {
        Button("Panel Size…") {
            controller.managePanelSizes()
        }
    }
}
