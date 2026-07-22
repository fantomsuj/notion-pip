import AppKit
import SwiftUI

struct PiPChromeView: View {
    static let newPageAccessibilityLabel = "Create New Notion Page"
    static let newPageHelp = "Create a new page in Notion"
    static let stashAccessibilityLabel = "Stash Notion PiP to Side"
    static let stashHelp = "Move the Notion PiP to the nearest screen edge"

    @ObservedObject var webSession: NotionWebSession
    @ObservedObject var nativePageDocument: NativePageDocument
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    let commandModel: AppCommandModel
    let onStash: () -> Void
    var showsTopControls: Bool {
        Self.shouldShowTopControls(
            isTypingInPage: webSession.isTypingInPage,
            isVoiceOverEnabled: voiceOverEnabled,
            isSwitchControlEnabled: switchControlEnabled,
            isFullKeyboardAccessEnabled: NSApplication.shared.isFullKeyboardAccessEnabled
        )
    }

    static func shouldShowTopControls(
        isTypingInPage: Bool,
        isVoiceOverEnabled: Bool,
        isSwitchControlEnabled: Bool,
        isFullKeyboardAccessEnabled: Bool
    ) -> Bool {
        !isTypingInPage
            || isVoiceOverEnabled
            || isSwitchControlEnabled
            || isFullKeyboardAccessEnabled
    }

    static func shouldHostNotionWebView(for session: NotionWebSession) -> Bool {
        session.shouldHostWebView
    }

    init(
        webSession: NotionWebSession,
        nativePageDocument: NativePageDocument,
        commandModel: AppCommandModel = .noOp,
        onStash: @escaping () -> Void = {}
    ) {
        self.webSession = webSession
        self.nativePageDocument = nativePageDocument
        self.commandModel = commandModel
        self.onStash = onStash
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Notion PiP", systemImage: "rectangle.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)

                Spacer()

                Group {
                    if webSession.state == .loading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Loading Notion page")
                    }

                    Button {
                        commandModel.perform(.newNotionPage)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .disabled(!(commandModel.command(for: .newNotionPage)?.isEnabled ?? false))
                    .accessibilityLabel(Self.newPageAccessibilityLabel)
                    .help(Self.newPageHelp)

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

                    Picker(
                        "Page surface",
                        selection: Binding(
                            get: { webSession.surface },
                            set: { surface in
                                switch surface {
                                case .preview:
                                    webSession.showPreviewSurface()
                                case .live:
                                    webSession.showLiveSurface()
                                }
                            }
                        )
                    ) {
                        ForEach(NotionPageSurface.allCases) { surface in
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
                }
                .opacity(showsTopControls ? 1 : 0)
                .allowsHitTesting(showsTopControls)
                .accessibilityHidden(!showsTopControls)
            }
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    webSession.revealTopControls()
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: showsTopControls
            )
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

            if webSession.surface == .preview {
                NativePagePreviewView(document: nativePageDocument) {
                    webSession.showLiveSurface()
                }
            } else if Self.shouldHostNotionWebView(for: webSession),
                      let webView = webSession.webView
            {
                NotionWebView(webView: webView)
            } else {
                ContentUnavailableView(
                    "No Notion page selected",
                    systemImage: "doc.text.magnifyingglass"
                )
            }
        }
        .background(DesignTokens.Colors.background)
    }
}
