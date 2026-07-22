import SwiftUI
import WebKit

struct QuickCaptureView: View {
    @ObservedObject var session: CaptureEditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CaptureWebView(webView: session.webView)
                .frame(minHeight: 280, idealHeight: 320)
                .accessibilityLabel("Quick Capture rich text editor")

            if let conflict = session.conflict {
                ConflictRecoveryView(
                    conflict: conflict,
                    isResolving: session.isResolvingConflict
                ) { action in
                    Task { await session.resolve(action) }
                }
                .padding(.top, DesignTokens.Spacing.control)
            }
        }
    }
}

@MainActor
enum QuickCaptureLaunchAction {
    static func perform(activate: () -> Void, openWindow: () -> Void) {
        activate()
        openWindow()
    }
}

private struct CaptureWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
