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
                title: "Quick Capture",
                size: CGSize(width: 520, height: 520),
                content: content
            ),
            performanceSignposter: AppPerformanceSignposter.shared,
            firstPresentationOperation: .firstQuickCapturePresentation
        )
    }

    static func makeSettings(runtime: AppRuntime) -> AppWindowPresenter {
        AppWindowPresenter(
            window: makeWindow(
                title: "Notion PiP Settings",
                size: CGSize(width: 480, height: 360),
                content: AnyView(SettingsView(runtime: runtime))
            )
        )
    }

    private static func makeWindow(
        title: String,
        size: CGSize,
        content: AnyView
    ) -> any AppWindow {
        let window = KeyCapableAppWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: content)
        return window
    }
}
