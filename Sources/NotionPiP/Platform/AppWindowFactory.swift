import AppKit
import SwiftUI

@MainActor
enum AppWindowFactory {
    static func makeQuickCapture(
        repository: CaptureRepository?,
        openInNotion: @escaping () -> Void
    ) -> AppWindowPresenter {
        let content: AnyView
        if let repository {
            let session = CaptureEditorSession(
                repository: repository,
                openInNotion: openInNotion
            )
            content = AnyView(
                QuickCaptureView(session: session)
                    .padding(DesignTokens.Spacing.container)
                    .frame(minWidth: 440, minHeight: 400)
            )
        } else {
            content = AnyView(
                VStack(spacing: DesignTokens.Spacing.control) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text("Quick Capture is unavailable")
                        .font(.headline)
                    Text("Your local draft store could not be opened. Restart the app and try again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(DesignTokens.Spacing.container)
                .frame(minWidth: 360, minHeight: 220)
            )
        }

        return AppWindowPresenter(
            window: makeWindow(
                role: .quickCapture,
                title: "Quick Capture",
                content: content
            )
        )
    }

    static func makeSettings(runtime: AppRuntime) -> AppWindowPresenter {
        AppWindowPresenter(
            window: makeWindow(
                role: .settings,
                title: "Notion PiP Settings",
                content: AnyView(SettingsView(runtime: runtime))
            )
        )
    }

    private static func makeWindow(
        role: WindowRole,
        title: String,
        content: AnyView
    ) -> any AppWindow {
        guard let window = role.makeWindow() as? KeyCapableAppWindow else {
            preconditionFailure("App window roles must create KeyCapableAppWindow")
        }
        window.title = title
        window.center()
        window.contentView = NSHostingView(rootView: content)
        return window
    }
}
