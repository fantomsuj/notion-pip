import AppKit
import SwiftUI

enum PiPTopToolbarPresentation: Equatable {
    case hidden
    case expanded
}

struct PiPChromeView: View {
    static let primaryActionID = AppCommandID.newNotionPage
    static let primaryActionAccessibilityLabel = "New Notion Page"
    static let primaryActionHelp = "Create a page in the Notion app"
    static let reloadAccessibilityLabel = "Re-pin current Notion page"
    static let reloadHelp = "Re-pin the current Notion page"
    static let stashAccessibilityLabel = "Stash Perch to Side"
    static let stashHelp = "Move Perch to the nearest screen edge"
    static let pageSwitcherAccessibilityLabel = "Switch Notion page"
    static let topControlsHeight: CGFloat = 32
    static let topControlsRevealHeight: CGFloat = 8
    static let topControlsHoverOutset: CGFloat = 12

    @ObservedObject var webSession: NotionWebSession
    @ObservedObject var quickCopyController: QuickCopyController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @StateObject private var topControlsHover = TopControlsHoverController()
    @State private var presentsPageSwitcher = false
    @ObservedObject var pageSwitcherController: PageSwitcherController
    let commandModel: AppCommandModel
    let panelSizeController: PanelSizeController?
    let panelPositionController: PanelPositionController?
    let onReloadSavedPin: () -> Void
    let onStash: () -> Void
    let onPageSwitcherSelection: (PageSwitcherSelection) -> Void
    var showsTopControls: Bool {
        Self.shouldShowTopControls(
            isHoveringTopEdge: topControlsHover.isHovering,
            isVoiceOverEnabled: voiceOverEnabled,
            isSwitchControlEnabled: switchControlEnabled,
            isFullKeyboardAccessEnabled: NSApplication.shared.isFullKeyboardAccessEnabled
        )
    }

    static func shouldShowTopControls(
        isHoveringTopEdge: Bool,
        isVoiceOverEnabled: Bool,
        isSwitchControlEnabled: Bool,
        isFullKeyboardAccessEnabled: Bool
    ) -> Bool {
        isHoveringTopEdge
            || isVoiceOverEnabled
            || isSwitchControlEnabled
            || isFullKeyboardAccessEnabled
    }

    static func topControlsReservedHeight(isVisible _: Bool) -> CGFloat {
        0
    }

    static func topToolbarPresentation(
        showsTopControls: Bool
    ) -> PiPTopToolbarPresentation {
        showsTopControls ? .expanded : .hidden
    }

    static func shouldHostNotionWebView(for session: NotionWebSession) -> Bool {
        session.shouldHostWebView
    }

    init(
        webSession: NotionWebSession,
        pageSwitcherController: PageSwitcherController = PageSwitcherController(),
        commandModel: AppCommandModel = .noOp,
        panelSizeController: PanelSizeController? = nil,
        panelPositionController: PanelPositionController? = nil,
        quickCopyController: QuickCopyController? = nil,
        onReloadSavedPin: @escaping () -> Void = {},
        onStash: @escaping () -> Void = {},
        onPageSwitcherSelection: @escaping (PageSwitcherSelection) -> Void = { _ in }
    ) {
        self.webSession = webSession
        self.quickCopyController = quickCopyController ?? QuickCopyController(
            monitor: AccessibilitySelectionMonitor(),
            target: webSession
        )
        self.pageSwitcherController = pageSwitcherController
        self.commandModel = commandModel
        self.panelSizeController = panelSizeController
        self.panelPositionController = panelPositionController
        self.onReloadSavedPin = onReloadSavedPin
        self.onStash = onStash
        self.onPageSwitcherSelection = onPageSwitcherSelection
    }

    func repinCurrentPage() {
        onReloadSavedPin()
    }

    func openInNotionAndStash() {
        webSession.openInBrowser()
        onStash()
    }

    func continueLoginInBrowser() {
        webSession.performBrowserLoginAction()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let browserLogin = NotionBrowserLoginPresentation(
                state: webSession.browserLoginState
            ) {
                HStack(spacing: DesignTokens.Spacing.control) {
                    Label(browserLogin.message, systemImage: "person.badge.key")
                        .font(.caption)
                    Spacer()
                    if browserLogin.showsProgress {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Waiting for browser sign-in")
                    }
                    Button(browserLogin.actionTitle, action: continueLoginInBrowser)
                        .disabled(!browserLogin.actionIsEnabled)
                        .accessibilityLabel(browserLogin.actionTitle)
                }
                .padding(.horizontal, DesignTokens.Spacing.control)
                .padding(.vertical, DesignTokens.Spacing.compact)
                .accessibilityElement(children: .contain)

                Divider()
            } else if webSession.state == .offline {
                HStack(spacing: DesignTokens.Spacing.control) {
                    Label("You're offline. Notion will reconnect when the network is available.", systemImage: "wifi.slash")
                        .font(.caption)
                }
                .padding(.horizontal, DesignTokens.Spacing.control)
                .padding(.vertical, DesignTokens.Spacing.compact)
                .accessibilityElement(children: .contain)

                Divider()
            } else if case .failed = webSession.state {
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
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                Color.clear
                    .frame(height: Self.topControlsRevealHeight)
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        topControlsHover.setHovering(isHovering)
                    }
                    .accessibilityHidden(true)

                let toolbarPresentation = Self.topToolbarPresentation(
                    showsTopControls: showsTopControls
                )
                if toolbarPresentation != .hidden {
                    topControlsOverlay
                        .transition(.opacity)
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            QuickCopyButton(controller: quickCopyController)
                .padding(Self.quickCopyEdgeInsets)
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: showsTopControls
        )
        .onDisappear {
            topControlsHover.cancel()
        }
    }

    private static var quickCopyEdgeInsets: EdgeInsets {
        EdgeInsets(
            top: QuickCopyButton.edgeInset,
            leading: QuickCopyButton.edgeInset,
            bottom: QuickCopyButton.edgeInset,
            trailing: QuickCopyButton.edgeInset
        )
    }

    private var topControlsOverlay: some View {
        HStack(spacing: 0) {
            if let panelPositionController {
                PanelCornerControls(controller: panelPositionController)
            }

            if panelPositionController != nil {
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, DesignTokens.Spacing.compact)
            }
            expandedTopControls
        }
        .padding(DesignTokens.Spacing.compact)
        .frame(height: Self.topControlsHeight)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.border.opacity(0.7), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .contentShape(Rectangle().inset(by: -Self.topControlsHoverOutset))
        .onHover { isHovering in
            topControlsHover.setHovering(isHovering)
        }
        .accessibilityElement(children: .contain)
    }

    private var expandedTopControls: some View {
        HStack(spacing: DesignTokens.Spacing.control) {
            if webSession.state == .loading {
                ProgressView()
                    .controlSize(.small)
                    .frame(
                        width: PanelCornerControls.minimumHitTarget,
                        height: PanelCornerControls.minimumHitTarget
                    )
                    .accessibilityLabel("Loading Notion page")
            }

            Button {
                commandModel.perform(Self.primaryActionID)
            } label: {
                Image(systemName: "plus")
                    .frame(
                        width: PanelCornerControls.minimumHitTarget,
                        height: PanelCornerControls.minimumHitTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!(commandModel.command(for: Self.primaryActionID)?.isEnabled ?? false))
            .accessibilityLabel(Self.primaryActionAccessibilityLabel)
            .help(Self.primaryActionHelp)

            Button {
                presentsPageSwitcher.toggle()
            } label: {
                Image(systemName: "rectangle.stack")
                    .frame(
                        width: PanelCornerControls.minimumHitTarget,
                        height: PanelCornerControls.minimumHitTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.pageSwitcherAccessibilityLabel)
            .help("Resume a pinned or recent Notion page")
            .popover(isPresented: $presentsPageSwitcher, arrowEdge: .top) {
                PageSwitcherView(
                    controller: pageSwitcherController,
                    onDismiss: { presentsPageSwitcher = false },
                    onSelect: { selection in
                        presentsPageSwitcher = false
                        onPageSwitcherSelection(selection)
                    }
                )
            }

            Button(action: repinCurrentPage) {
                Image(systemName: "arrow.clockwise")
                    .frame(
                        width: PanelCornerControls.minimumHitTarget,
                        height: PanelCornerControls.minimumHitTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.reloadAccessibilityLabel)
            .help(Self.reloadHelp)

            Button(action: openInNotionAndStash) {
                NotionToolbarMark()
                    .frame(
                        width: PanelCornerControls.minimumHitTarget,
                        height: PanelCornerControls.minimumHitTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Notion page in browser")

            PiPAppCommandMenu(
                commandModel: commandModel,
                panelSizeController: panelSizeController
            )

            Button(action: onStash) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .frame(
                        width: PanelCornerControls.minimumHitTarget,
                        height: PanelCornerControls.minimumHitTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.stashAccessibilityLabel)
            .help(Self.stashHelp)
        }
    }
}

private struct NotionToolbarMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(lineWidth: 1.2)
            Text("N")
                .font(.system(size: 11, weight: .black, design: .serif))
                .offset(y: -0.25)
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }
}
