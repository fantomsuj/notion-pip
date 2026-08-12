import AppKit
import SwiftUI

@MainActor
enum AppWindowFactory {
    static func makeOnboarding(
        globalShortcut: GlobalShortcut,
        onComplete: @escaping @MainActor () -> Void,
        onOpenSettings: @escaping @MainActor () -> Void
    ) -> AppWindowPresenter {
        let window = makeWindow(
            role: .onboarding,
            title: "Welcome to Perch",
            content: AnyView(
                OnboardingView(
                    globalShortcut: globalShortcut,
                    onComplete: onComplete,
                    onOpenSettings: onOpenSettings
                )
            )
        )
        window.closeRequestHandler = onComplete
        return AppWindowPresenter(window: window)
    }

    static func makeSettings(
        runtime: AppRuntime,
        panelSizeController: PanelSizeController,
        launchAtLoginService: LaunchAtLoginService,
        closeRequestHandler: @escaping @MainActor () -> Void
    ) -> AppWindowPresenter {
        AppWindowPresenter(
            window: makeWindow(
                role: .settings,
                title: "Perch Settings",
                content: AnyView(
                    SettingsView(
                        runtime: runtime,
                        panelSizeController: panelSizeController,
                        launchAtLoginService: launchAtLoginService
                    )
                )
            ),
            closeRequestHandler: closeRequestHandler
        )
    }

    private static func makeWindow(
        role: WindowRole,
        title: String,
        content: AnyView
    ) -> KeyCapableAppWindow {
        guard let window = role.makeWindow() as? KeyCapableAppWindow else {
            preconditionFailure("App window roles must create KeyCapableAppWindow")
        }
        window.title = title
        window.center()
        window.contentView = NSHostingView(rootView: content)
        return window
    }
}
