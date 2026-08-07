import SwiftUI

struct SettingsView: View {
    @ObservedObject var runtime: AppRuntime
    @ObservedObject var panelSizeController: PanelSizeController
    @State private var personalToken = ""

    var body: some View {
        ScrollView {
            Form {
                Section("Panel Sizes") {
                    PanelSizeSettingsView(controller: panelSizeController)
                }

                Section("Pinned Page") {
                    PageURLInputView(
                        state: runtime.pageURLInputState,
                        onSubmit: runtime.validatePageURL
                    )
                    if runtime.isNotionConnected {
                        NotionWorkspaceSearchView(runtime: runtime)
                    }
                    if let activePage = runtime.activePage {
                        LabeledContent(
                            "Active page",
                            value: activePage.displayTitle ?? activePage.canonicalURL.absoluteString)
                    } else {
                        Text("No page is pinned yet.")
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                    }
                }

                Section("Quick Capture Destination") {
                    QuickCaptureDestinationSettingsView(runtime: runtime)
                }

                Section("Global Shortcut") {
                    GlobalShortcutRecorderView(runtime: runtime)
                    Toggle(
                        "Press and hold to peek",
                        isOn: Binding(
                            get: { runtime.holdToPeekEnabled },
                            set: { runtime.setHoldToPeekEnabled($0) }
                        )
                    )
                    Text(
                        runtime.holdToPeekEnabled
                            ? "Release after a peek to return focus to the app you were using."
                            : "Show or hide the panel as soon as the shortcut is pressed."
                    )
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                }

                Section("Trusted Quick Capture") {
                    QuickCaptureShortcutRecorderView(runtime: runtime)
                    Text("This shortcut is separate from panel Show/Hide.")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.secondaryText)
                    Toggle("Pre-fill Quick Capture from the clipboard", isOn: Binding(
                        get: { runtime.quickCapturePrefillsClipboard },
                        set: { enabled in
                            runtime.setQuickCapturePrefillsClipboard(enabled)
                        }
                    ))
                    Toggle("Insert at the saved Notion cursor when possible", isOn: Binding(
                        get: { runtime.quickCaptureInsertsAtNotionCursor },
                        set: { enabled in
                            runtime.setQuickCaptureInsertsAtNotionCursor(enabled)
                        }
                    ))
                    Text("Clipboard content is read only when you invoke Quick Capture. If the saved cursor is no longer valid, the content opens in Quick Capture instead.")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.secondaryText)
                }

                Section("Quick Copy") {
                    Text(
                        "Quick Copy uses Accessibility only while its bottom-left control is visibly on. Selected text is inserted at your saved Notion cursor, stays in memory only, and never changes the clipboard."
                    )
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                }

                Section("Menu Bar") {
                    Toggle(
                        "Show Notion PiP in the menu bar",
                        isOn: Binding(
                            get: { runtime.savedMenuBarIconVisibility },
                            set: { isVisible in
                                runtime.setMenuBarIconVisibility(isVisible)
                            }
                        )
                    )

                    if runtime.isMenuBarIconVisibilityForced {
                        Text("The menu-bar icon is temporarily visible because the global shortcut is unavailable. Retry the shortcut to return to your saved setting.")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                    }
                }

                Section("Personal Notion Access") {
                    switch runtime.connectionState {
                    case .disconnected, .failed:
                        SecureField("Personal access token", text: $personalToken)
                            .textFieldStyle(.roundedBorder)
                        Button(isReconnectNeeded ? "Reconnect to Notion" : "Connect to Notion") {
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

                    Text(
                        "Use a personal access token (ntn_…). It is stored only in this Mac’s Keychain and acts with your own Notion permissions. It is never exposed to the Notion web view."
                    )
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                }

                if !runtime.serviceHealth.isHealthy {
                    Section("Service Health") {
                        ServiceHealthView(runtime: runtime)
                    }
                }

                Section("Service Status") {
                    CaptureOutboxStatusView(runtime: runtime)
                    LabeledContent(
                        "Pinned-page sync",
                        value: runtime.serviceHealth.issues.contains(.pinnedPagePersistenceUnavailable)
                            ? "Needs attention" : "Ready")
                }

                Section("About") {
                    LabeledContent("Application", value: "Notion PiP")
                    LabeledContent("Minimum macOS", value: "14.0")
                    Text(
                        "The app runs as an accessory with optional menu-bar presence and keeps credentials out of page URLs and logs."
                    )
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    DeveloperStatusView()
                }
            }
        }
        .formStyle(.grouped)
        .padding(DesignTokens.Spacing.container)
        .frame(minWidth: 440, minHeight: 420)
        .onDisappear {
            personalToken = ""
        }
    }

    private var isReconnectNeeded: Bool {
        if case .failed = runtime.connectionState { return true }
        return false
    }
}
