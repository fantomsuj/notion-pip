import AppKit
import SwiftUI

struct SettingsView: View {
    private static let privacyURLString =
        "https://github.com/fantomsuj/notion-pip/blob/master/docs/PRIVACY.md"
    private static let supportURLString =
        "https://github.com/fantomsuj/notion-pip/issues/new"
    private static let installationURLString =
        "https://github.com/fantomsuj/notion-pip/blob/master/docs/SUPPORT.md"

    @ObservedObject var runtime: AppRuntime
    @ObservedObject var panelSizeController: PanelSizeController
    @ObservedObject var launchAtLoginService: LaunchAtLoginService
    @ObservedObject var contextSuggestionController: ContextSuggestionController

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
                        "Press and hold to peek (Experimental)",
                        isOn: Binding(
                            get: { runtime.holdToPeekEnabled },
                            set: { runtime.setHoldToPeekEnabled($0) }
                        )
                    )
                    Text(
                        runtime.holdToPeekEnabled
                            ? "Hold to peek. Double-press to keep the panel open. Turn this off if shortcut timing feels unpredictable."
                            : "Show or hide the panel as soon as the shortcut is pressed."
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

                Section("Context Suggestions") {
                    Toggle(
                        "Suggest pages for the app I'm using",
                        isOn: Binding(
                            get: { contextSuggestionController.isEnabled },
                            set: { contextSuggestionController.setEnabled($0) }
                        )
                    )

                    Text(
                        "Perch locally compares the active app, window title, and an available page URL with your pinned and recent pages. When you reveal Perch, it can also check the focused URL for an exact Notion page. Raw Accessibility context is never saved or uploaded; pages you open follow normal local history."
                    )
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)

                    if contextSuggestionController.permissionState == .needsPermission {
                        Label(
                            "Allow Perch in Privacy & Security → Accessibility, then return here.",
                            systemImage: "hand.raised"
                        )
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        if let accessibilitySettings = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        ) {
                            Link("Open Accessibility Settings", destination: accessibilitySettings)
                        }
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
                    let metadata = AppMetadata.current
                    LabeledContent("Application") {
                        PerchIdentityLabel(title: "Perch")
                    }
                    LabeledContent("Version", value: metadata.versionAndBuild)
                    LabeledContent("Requires macOS", value: metadata.minimumSystemVersion)
                    if let privacyURL = URL(string: Self.privacyURLString) {
                        Link("Privacy Policy", destination: privacyURL)
                    }
                    if let supportURL = URL(string: Self.supportURLString) {
                        Link("Support and Feedback", destination: supportURL)
                    }
                    if let installationURL = URL(string: Self.installationURLString) {
                        Link("Installation and Uninstall Help", destination: installationURL)
                    }
                    Text(
                        "The app runs as an accessory with optional menu-bar presence and keeps credentials out of page URLs and logs."
                    )
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    if let copyright = metadata.copyright {
                        Text(copyright)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(DesignTokens.Spacing.container)
        .frame(minWidth: 440, minHeight: 420)
        .disablesAnimationOnColorSchemeChange()
        .onAppear {
            launchAtLoginService.refresh()
            contextSuggestionController.refreshPermission()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            launchAtLoginService.refresh()
            contextSuggestionController.refreshPermission()
        }
    }
}
