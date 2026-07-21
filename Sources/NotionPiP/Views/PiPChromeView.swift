import SwiftUI

struct PiPChromeView: View {
    let webSession: NotionWebSession
    let onHide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Notion PiP", systemImage: "rectangle.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)

                Spacer()

                Button(action: onHide) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide Notion PiP")
            }
            .padding(.horizontal, DesignTokens.Spacing.control)
            .frame(height: 32)

            Divider()

            NotionWebView(webView: webSession.webView)
        }
        .background(DesignTokens.Colors.background)
    }
}
