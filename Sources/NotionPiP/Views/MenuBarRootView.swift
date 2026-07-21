import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            header

            Text("Keep one Notion page close at hand without changing your current workspace.")
                .font(.callout)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            PageURLField(
                text: $runtime.pageURLText,
                focusRequest: runtime.pageURLFocusRequest,
                onSubmit: runtime.validatePageURL
            )

            if let validationMessage = runtime.validationMessage {
                Label(
                    validationMessage,
                    systemImage: runtime.validationFailed ? "exclamationmark.circle" : "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(
                    runtime.validationFailed ? DesignTokens.Colors.error : DesignTokens.Colors.secondaryText
                )
                .accessibilityLabel(validationMessage)
            }

            if let activePage = runtime.activePage {
                PagePickerView(pages: [activePage], onPin: runtime.pin)
            }

            Divider()

            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .padding(DesignTokens.Spacing.container)
        .frame(width: 360)
        .background(DesignTokens.Colors.background)
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.control) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.title3)
                .foregroundStyle(DesignTokens.Colors.action)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                Text("Notion PiP")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                Text("Native menu-bar shell")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
