import SwiftUI

struct SettingsView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        Form {
            Section("Page") {
                PageURLInputView(
                    state: runtime.pageURLInputState,
                    onSubmit: runtime.validatePageURL
                )
            }

            Section("About") {
                LabeledContent("Application", value: "Notion PiP")
                LabeledContent("Minimum macOS", value: "14.0")
                Text("The app runs as a menu-bar accessory and keeps credentials out of page URLs and logs.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
        }
        .formStyle(.grouped)
        .padding(DesignTokens.Spacing.container)
        .frame(width: 440, height: 260)
    }
}
