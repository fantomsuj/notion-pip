import SwiftUI

struct PiPChromeView: View {
    static let stashAccessibilityLabel = "Stash Notion PiP to Side"
    static let stashHelp = "Move the Notion PiP to the nearest screen edge"

    @ObservedObject var webSession: NotionWebSession
    @ObservedObject var nativePageDocument: NativePageDocument
    let commandModel: AppCommandModel
    let onStash: () -> Void
    let onHide: () -> Void
    @State private var surface: Surface = .notion

    private enum Surface: String, CaseIterable, Identifiable {
        case preview = "Preview"
        case notion = "Notion"

        var id: String { rawValue }
    }

    init(
        webSession: NotionWebSession,
        nativePageDocument: NativePageDocument,
        commandModel: AppCommandModel = .noOp,
        onStash: @escaping () -> Void = {},
        onHide: @escaping () -> Void
    ) {
        self.webSession = webSession
        self.nativePageDocument = nativePageDocument
        self.commandModel = commandModel
        self.onStash = onStash
        self.onHide = onHide
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Notion PiP", systemImage: "rectangle.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)

                Spacer()

                if webSession.state == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading Notion page")
                }

                Button(action: webSession.reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reload Notion page")

                Button(action: webSession.openInBrowser) {
                    Image(systemName: "safari")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Notion page in browser")

                Picker("Page surface", selection: $surface) {
                    ForEach(Surface.allCases) { surface in
                        Text(surface.rawValue).tag(surface)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 138)
                .accessibilityLabel("Page surface")

                PiPAppCommandMenu(commandModel: commandModel)

                Button(action: onStash) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.stashAccessibilityLabel)
                .help(Self.stashHelp)

                Button(action: onHide) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide Notion PiP")
            }
            .padding(.horizontal, DesignTokens.Spacing.control)
            .frame(height: 32)

            Divider()

            if case .failed = webSession.state {
                HStack(spacing: DesignTokens.Spacing.control) {
                    Label("Notion couldn't load this page.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                    Spacer()
                    Button("Try Again", action: webSession.reload)
                        .accessibilityLabel("Retry loading Notion page")
                }
                .padding(.horizontal, DesignTokens.Spacing.control)
                .padding(.vertical, DesignTokens.Spacing.compact)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Notion couldn't load this page.")

                Divider()
            }

            if surface == .preview, nativePageDocument.snapshot != nil {
                NativePagePreviewView(document: nativePageDocument) {
                    surface = .notion
                }
            } else {
                NotionWebView(webView: webSession.webView)
            }
        }
        .background(DesignTokens.Colors.background)
    }
}
