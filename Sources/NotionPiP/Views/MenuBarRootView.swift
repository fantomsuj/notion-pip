import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var runtime: AppRuntime
    let onQuickCapture: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            header

            Text("Keep one Notion page close at hand without changing your current workspace.")
                .font(.callout)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            PageURLInputView(
                state: runtime.pageURLInputState,
                onSubmit: runtime.validatePageURL
            )

            Button(action: onQuickCapture) {
                Label("Quick Capture", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n")

            if runtime.isNotionConnected {
                NotionWorkspaceSearchView(runtime: runtime)
            }

            if let activePage = runtime.activePage {
                PagePickerView(pages: [activePage], onPin: runtime.pin)
            }

            ServiceHealthView(runtime: runtime)

            Divider()

            HStack {
                Button(action: openSettings.callAsFunction) {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",")

                Spacer()

                Button("Quit", action: onQuit)
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
