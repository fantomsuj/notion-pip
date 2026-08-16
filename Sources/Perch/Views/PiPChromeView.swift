import AppKit
import SwiftUI

enum PiPTopToolbarPresentation: Equatable {
    case hidden
    case expanded
}

enum FailedLoadBannerAccessibilityChild: Equatable {
    case message(String)
    case retryButton(String)
}

enum FailedLoadBannerAccessibilityChildBehavior: Equatable {
    case contain
    case combine

    var swiftUIValue: AccessibilityChildBehavior {
        switch self {
        case .contain:
            .contain
        case .combine:
            .combine
        }
    }
}

struct EmptyPageChromePresentation: Equatable {
    let title: String
    let description: String
    let actionTitle: String
    let actionAccessibilityLabel: String

    static let missingPage = Self(
        title: "No Notion page is open",
        description: "Open a page from Settings to keep it beside your other work.",
        actionTitle: "Open Settings",
        actionAccessibilityLabel: "Open Settings to choose a Notion page"
    )
}

struct FailedLoadBannerAccessibilityPresentation: Equatable {
    let message: String
    let retryAccessibilityLabel: String
    let childBehavior: FailedLoadBannerAccessibilityChildBehavior

    var children: [FailedLoadBannerAccessibilityChild] {
        [
            .message(message),
            .retryButton(retryAccessibilityLabel),
        ]
    }

    static let failedLoad = Self(
        message: "Notion couldn't load this page.",
        retryAccessibilityLabel: "Retry loading Notion page",
        childBehavior: .contain
    )
}

struct PiPChromeView: View {
    static let primaryActionID = AppCommandID.newNotionPage
    static let primaryActionAccessibilityLabel = "New Notion Page"
    static let primaryActionHelp = "Create a page in the Notion app"
    static let reloadAccessibilityLabel = "Reload current Notion page"
    static let reloadHelp = "Reload the current Notion page"
    static let stashAccessibilityLabel = "Stash Perch to Side"
    static let stashHelp = "Move Perch to the nearest screen edge"
    static let pageSwitcherAccessibilityLabel = "Switch Notion page"
    static let topControlsHeight: CGFloat = 36
    static let topControlsSpacing = DesignTokens.Spacing.compact
    /// Tall enough to catch the pointer as it approaches the top edge without
    /// covering a large clickable region of the Notion page underneath.
    static let topControlsRevealHeight: CGFloat = 16
    static let topControlsHoverOutset: CGFloat = 12

    @ObservedObject var webSession: NotionWebSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @StateObject private var topControlsHover = TopControlsHoverController()
    @State private var presentsPageSwitcher = false
    @State private var reloadFeedbackPending = false
    @State private var reloadRotationDegrees: Double = 0
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
        showsTopControls: Bool,
        isPageSwitcherPresented: Bool = false
    ) -> PiPTopToolbarPresentation {
        showsTopControls || isPageSwitcherPresented ? .expanded : .hidden
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
        onReloadSavedPin: @escaping () -> Void = {},
        onStash: @escaping () -> Void = {},
        onPageSwitcherSelection: @escaping (PageSwitcherSelection) -> Void = { _ in }
    ) {
        self.webSession = webSession
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
                let presentation = FailedLoadBannerAccessibilityPresentation.failedLoad
                HStack(spacing: DesignTokens.Spacing.control) {
                    Label("Notion couldn't load this page.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                        .accessibilityLabel(presentation.message)
                    Spacer()
                    Button("Try Again", action: repinCurrentPage)
                        .accessibilityLabel(presentation.retryAccessibilityLabel)
                }
                .padding(.horizontal, DesignTokens.Spacing.control)
                .padding(.vertical, DesignTokens.Spacing.compact)
                .accessibilityElement(children: presentation.childBehavior.swiftUIValue)

                Divider()
            }

            if Self.shouldHostNotionWebView(for: webSession),
                let webView = webSession.webView
            {
                NotionWebView(webView: webView)
            } else {
                let emptyPage = EmptyPageChromePresentation.missingPage
                ContentUnavailableView {
                    Label(emptyPage.title, systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text(emptyPage.description)
                } actions: {
                    Button(emptyPage.actionTitle) {
                        commandModel.perform(.settings)
                    }
                    .accessibilityLabel(emptyPage.actionAccessibilityLabel)
                }
            }
        }
        .background(DesignTokens.Colors.background)
        .disablesAnimationOnColorSchemeChange()
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
                    showsTopControls: showsTopControls,
                    isPageSwitcherPresented: presentsPageSwitcher
                )
                if toolbarPresentation != .hidden {
                    topControlsOverlay
                        .transition(.opacity)
                }
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: showsTopControls
        )
        .onDisappear {
            topControlsHover.cancel()
        }
        .onChange(of: webSession.state) { previousState, currentState in
            if ReloadCompletionMotionPolicy.shouldAnimate(
                isPending: reloadFeedbackPending,
                previousState: previousState,
                currentState: currentState,
                reducesMotion: reduceMotion
            ) {
                reloadRotationDegrees += 360
            }
            if reloadFeedbackPending,
                ReloadCompletionMotionPolicy.shouldFinishPendingReload(
                    currentState: currentState
                )
            {
                reloadFeedbackPending = false
            }
        }
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
        HStack(spacing: Self.topControlsSpacing) {
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
            .chromePressStyle()
            .disabled(!(commandModel.command(for: Self.primaryActionID)?.isEnabled ?? false))
            .accessibilityLabel(Self.primaryActionAccessibilityLabel)
            .help(Self.primaryActionHelp)

            Button {
                presentsPageSwitcher.toggle()
            } label: {
                ToolbarMotionIcon(style: .pageStack)
            }
            .chromePressStyle()
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

            Button {
                reloadFeedbackPending = true
                repinCurrentPage()
            } label: {
                ToolbarMotionIcon(
                    style: .reload,
                    systemImage: "arrow.clockwise",
                    rotationDegrees: reloadRotationDegrees
                )
            }
            .chromePressStyle()
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
            .chromePressStyle()
            .accessibilityLabel("Open Notion page in browser")
            .help("Open this page in the Notion app and stash Perch")

            PiPAppCommandMenu(
                commandModel: commandModel,
                panelSizeController: panelSizeController
            )

            Button(action: onStash) {
                ToolbarMotionIcon(
                    style: .stash,
                    systemImage: "arrow.down.right.and.arrow.up.left"
                )
            }
            .chromePressStyle()
            .accessibilityLabel(Self.stashAccessibilityLabel)
            .help(Self.stashHelp)
        }
    }
}

private struct NotionToolbarMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let transform = ToolbarIconMotionPolicy.transform(
            for: .external,
            isHovering: isHovering,
            reducesMotion: reduceMotion
        )

        ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(lineWidth: 1.2)
            Text("N")
                .font(.system(size: 11, weight: .black, design: .serif))
                .offset(y: -0.25)
        }
        .frame(width: 15, height: 15)
        .offset(transform.offset)
        .scaleEffect(transform.scale)
        .frame(
            width: PanelCornerControls.minimumHitTarget,
            height: PanelCornerControls.minimumHitTarget
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(
            reduceMotion ? nil : .easeOut(duration: ToolbarIconMotionPolicy.hoverDuration),
            value: isHovering
        )
        .accessibilityHidden(true)
    }
}
