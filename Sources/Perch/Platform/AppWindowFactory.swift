import AppKit
import SwiftUI

@MainActor
enum AppWindowFactory {
    static func makeStorageRecovery(
        controller: StorageRecoveryController,
        closeRequestHandler: @escaping @MainActor () -> Void,
        windowFactory: (@MainActor () -> any AppWindow)? = nil
    ) -> AppWindowPresenter {
        let window = windowFactory?() ?? makeWindow(
            role: .storageRecovery,
            title: StorageRecoveryPresentation.title,
            content: AnyView(StorageRecoveryView(controller: controller))
        )
        return AppWindowPresenter(
            window: window,
            closeRequestHandler: closeRequestHandler
        )
    }

    static func makeOnboarding(
        globalShortcut: GlobalShortcut,
        pageURLInputState: PageURLInputState,
        onPinPage: @escaping @MainActor () -> Bool,
        onComplete: @escaping @MainActor () -> Void,
        onOpenSettings: @escaping @MainActor () -> Void
    ) -> AppWindowPresenter {
        let window = makeWindow(
            role: .onboarding,
            title: "Welcome to Perch",
            content: AnyView(
                OnboardingView(
                    globalShortcut: globalShortcut,
                    pageURLInputState: pageURLInputState,
                    onPinPage: onPinPage,
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
        contextSuggestionController: ContextSuggestionController,
        agentStreamingService: AgentStreamingService,
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
                        launchAtLoginService: launchAtLoginService,
                        contextSuggestionController: contextSuggestionController,
                        agentStreamingService: agentStreamingService
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
