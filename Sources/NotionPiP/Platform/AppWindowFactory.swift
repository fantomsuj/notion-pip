import AppKit
import SwiftUI

@MainActor
enum AppWindowFactory {
    static func makeQuickCapture(
        repository: CaptureRepository?,
        lifecycle: QuickCaptureLifecycleCoordinator? = nil,
        onNeedsConfiguration: @escaping @MainActor (String) -> Void = { _ in },
        openInNotion: @escaping () -> Void
    ) -> AppWindowPresenter {
        let content: AnyView
        let session: CaptureEditorSession?
        if let repository {
            let editorSession = CaptureEditorSession(
                repository: repository,
                openInNotion: openInNotion
            )
            session = editorSession
            content = AnyView(
                QuickCaptureView(session: editorSession)
                    .padding(DesignTokens.Spacing.container)
                    .frame(minWidth: 440, minHeight: 400)
            )
        } else {
            session = nil
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

        let window = makeWindow(
            role: .quickCapture,
            title: "Quick Capture",
            content: content
        )
        if let session, let lifecycle {
            window.closeRequestHandler = { [weak window, weak session] in
                guard let window, let session, !window.isProcessingCloseRequest else { return }
                window.isProcessingCloseRequest = true
                Task { @MainActor in
                    defer { window.isProcessingCloseRequest = false }
                    do {
                        let snapshot = try await session.latestSnapshot()
                        let outcome = await lifecycle.close(snapshot: snapshot)
                        switch outcome {
                        case .discarded, .enqueued:
                            window.orderOut()
                        case .needsConfiguration(let message):
                            session.reportCloseGuidance(message)
                            window.orderOut()
                            onNeedsConfiguration(message)
                        case .failed(let message):
                            session.reportCloseGuidance(message)
                        }
                    } catch {
                        session.reportCloseGuidance("The latest capture could not be saved.")
                    }
                }
            }
        }
        let terminationHandler: (@MainActor () async -> Bool)?
        if let session {
            terminationHandler = { [weak session] in
                guard let session else { return true }
                return await session.prepareForTermination()
            }
        } else {
            terminationHandler = nil
        }
        return AppWindowPresenter(
            window: window,
            terminationHandler: terminationHandler
        )
    }

    static func makeSettings(
        runtime: AppRuntime,
        panelSizeController: PanelSizeController
    ) -> AppWindowPresenter {
        AppWindowPresenter(
            window: makeWindow(
                role: .settings,
                title: "Notion PiP Settings",
                content: AnyView(
                    SettingsView(
                        runtime: runtime,
                        panelSizeController: panelSizeController
                    )
                )
            )
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
