import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var runtime: AppRuntime
    @ObservedObject var panelSizeController: PanelSizeController
    @ObservedObject var launchAtLoginService: LaunchAtLoginService

    var body: some View {
        ScrollView {
            Form {
                Section("Current Page") {
                    PageURLInputView(
                        state: runtime.pageURLInputState,
                        onSubmit: { _ = runtime.validatePageURL() }
                    )
                    if let activePage = runtime.activePage {
                        LabeledContent(
                            "Open page",
                            value: activePage.displayTitle ?? activePage.canonicalURL.absoluteString)
                    } else {
                        Text("No page is open in Perch yet.")
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                    }
                }

                Section("Panel Sizes") {
                    PanelSizeSettingsView(controller: panelSizeController)
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
                            ? "Hold to peek. Double-press to keep the panel open."
                            : "Show or hide the panel as soon as the shortcut is pressed."
                    )
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
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
                        "Show Perch in the menu bar",
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

                Section("Launch at Login") {
                    Toggle(
                        "Launch Perch at login",
                        isOn: Binding(
                            get: { launchAtLoginService.isRegistered },
                            set: { launchAtLoginService.setEnabled($0) }
                        )
                    )

                    switch launchAtLoginService.state {
                    case .requiresApproval:
                        Text(
                            "Perch is registered, but macOS requires your approval before it can launch at login. Allow it in System Settings → General → Login Items & Extensions."
                        )
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        Button("Open Login Items Settings") {
                            launchAtLoginService.openSystemSettings()
                        }
                    case .unavailable:
                        Text(
                            "macOS could not find a current login item registration. Turn this setting on to register this app. If registration fails, quit and reopen Perch from its app bundle and try again."
                        )
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                    case .unregistered, .registered:
                        EmptyView()
                    }

                    if let failureMessage = launchAtLoginService.failureMessage {
                        Label(failureMessage, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Colors.error)
                    }
                }

                if !runtime.serviceHealth.isHealthy {
                    Section("Service Health") {
                        ServiceHealthView(runtime: runtime)
                    }
                }

                Section("Service Status") {
                    LabeledContent(
                        "Current-page saving",
                        value: runtime.serviceHealth.issues.contains(.pinnedPagePersistenceUnavailable)
                            ? "Needs attention" : "Ready")
                }

                Section("About") {
                    LabeledContent("Application", value: "Perch")
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
        .onAppear {
            launchAtLoginService.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            launchAtLoginService.refresh()
        }
    }
}
