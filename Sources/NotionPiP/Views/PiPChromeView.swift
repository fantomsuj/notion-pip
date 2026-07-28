import AppKit
import SwiftUI

struct PiPChromeView: View {
    static let primaryActionID = AppCommandID.quickCapture
    static let primaryActionAccessibilityLabel = "Quick Capture"
    static let primaryActionHelp = "Capture a note for Notion"
    static let reloadAccessibilityLabel = "Re-pin current Notion page"
    static let reloadHelp = "Re-pin the current Notion page"
    static let stashAccessibilityLabel = "Stash Notion PiP to Side"
    static let stashHelp = "Move the Notion PiP to the nearest screen edge"

    @ObservedObject var webSession: NotionWebSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    let commandModel: AppCommandModel
    let panelSizeController: PanelSizeController?
    let onReloadSavedPin: () -> Void
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
        commandModel: AppCommandModel = .noOp,
        panelSizeController: PanelSizeController? = nil,
        onReloadSavedPin: @escaping () -> Void = {},
        onStash: @escaping () -> Void = {}
    ) {
        self.webSession = webSession
        self.commandModel = commandModel
        self.panelSizeController = panelSizeController
        self.onReloadSavedPin = onReloadSavedPin
        self.onStash = onStash
    }

    func repinCurrentPage() {
        onReloadSavedPin()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                Group {
                    if webSession.state == .loading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Loading Notion page")
                    }

                    Button {
                        commandModel.perform(Self.primaryActionID)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .disabled(!(commandModel.command(for: Self.primaryActionID)?.isEnabled ?? false))
                    .accessibilityLabel(Self.primaryActionAccessibilityLabel)
                    .help(Self.primaryActionHelp)

                    Button(action: repinCurrentPage) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.reloadAccessibilityLabel)
                    .help(Self.reloadHelp)

                    Button(action: webSession.openInBrowser) {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Notion page in browser")

                    PiPAppCommandMenu(
                        commandModel: commandModel,
                        panelSizeController: panelSizeController
                    )

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
                    Button("Try Again", action: repinCurrentPage)
                        .accessibilityLabel("Retry loading Notion page")
                }
                .padding(.horizontal, DesignTokens.Spacing.control)
                .padding(.vertical, DesignTokens.Spacing.compact)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Notion couldn't load this page.")

                Divider()
            }

            if Self.shouldHostNotionWebView(for: webSession),
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
