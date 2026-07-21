import AppKit
import SwiftUI

@main
struct NotionPiPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime: AppRuntime
    @StateObject private var captureFeature: QuickCaptureFeatureRuntime

    init() {
        let runtime = AppRuntime()
        _runtime = StateObject(wrappedValue: runtime)
        _captureFeature = StateObject(
            wrappedValue: QuickCaptureFeatureRuntime {
                guard let page = runtime.activePage else { return }
                NSWorkspace.shared.open(page.canonicalURL)
            }
        )
        appDelegate.bind(urlHandler: runtime)
        runtime.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(runtime: runtime)
        } label: {
            Label("Notion PiP", systemImage: "rectangle.on.rectangle")
        }
        .menuBarExtraStyle(.window)

        Window("Quick Capture", id: "quick-capture") {
            if let session = captureFeature.session {
                QuickCaptureView(session: session)
                    .padding(DesignTokens.Spacing.container)
                    .frame(minWidth: 440, minHeight: 400)
            } else {
                VStack(spacing: DesignTokens.Spacing.control) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text("Quick Capture is unavailable")
                        .font(.headline)
                    Text(captureFeature.startupMessage ?? "The draft store could not be opened.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(DesignTokens.Spacing.container)
                .frame(minWidth: 360, minHeight: 220)
            }
        }
        .defaultSize(width: 520, height: 520)

        Settings {
            SettingsView(runtime: runtime)
        }
    }
}

@MainActor
private final class QuickCaptureFeatureRuntime: ObservableObject {
    let session: CaptureEditorSession?
    let startupMessage: String?

    init(openInNotion: @escaping () -> Void) {
        do {
            session = CaptureEditorSession(
                repository: try CaptureRepository(),
                openInNotion: openInNotion
            )
            startupMessage = nil
        } catch {
            session = nil
            startupMessage = "Your local draft store could not be opened. Restart the app and try again."
        }
    }
}
