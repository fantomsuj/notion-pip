import SwiftUI

struct SettingsView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var personalToken = ""

    var body: some View {
        Form {
            if !runtime.serviceHealth.isHealthy {
                Section("Service health") {
                    ServiceHealthView(runtime: runtime)
                }
            }

            Section("Page") {
                PageURLInputView(
                    state: runtime.pageURLInputState,
                    onSubmit: runtime.validatePageURL
                )
            }

            Section("Personal Notion access") {
                switch runtime.connectionState {
                case .disconnected, .failed:
                    SecureField("Personal access token", text: $personalToken)
                        .textFieldStyle(.roundedBorder)
                    Button("Connect to Notion") {
                        let token = personalToken
                        personalToken = ""
                        Task { await runtime.connectPersonalToken(token) }
                    }
                case .connecting:
                    LabeledContent("Status") { ProgressView("Connecting") }
                case .connected(let workspaceName):
                    LabeledContent("Workspace", value: workspaceName)
                    Button("Disconnect", role: .destructive) {
                        runtime.disconnectPersonalToken()
                    }
                }

                if case .failed(let message) = runtime.connectionState {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }

                Text("Use a personal access token (ntn_…). It is stored only in this Mac’s Keychain and acts with your own Notion permissions. It is never exposed to the Notion web view.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
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
        .frame(minWidth: 440, idealWidth: 480, minHeight: 420, idealHeight: 480)
        .onDisappear {
            personalToken = ""
        }
    }
}
