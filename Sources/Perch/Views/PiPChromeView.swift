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

    static let customPinnedFailedLoad = Self(
        message: "This page couldn't load.",
        retryAccessibilityLabel: "Retry loading this page",
        childBehavior: .contain
    )
}

enum PiPDestinationChrome: Equatable {
    case notion
    case customPinned

    init(isShowingCustomURL: Bool) {
        self = isShowingCustomURL ? .customPinned : .notion
    }

    var showsNotionPageActions: Bool { self == .notion }

    var showNotionAccessibilityLabel: String { "Show Notion page" }
    var showNotionHelp: String { "Return to your last Notion page" }

    var openInBrowserAccessibilityLabel: String {
        switch self {
        case .notion:
            "Open Notion page in browser"
        case .customPinned:
            "Open this page in the browser"
        }
    }

    var openInBrowserHelp: String {
        switch self {
        case .notion:
            "Open this page in the Notion app and stash Perch"
        case .customPinned:
            "Open this page in your default browser"
        }
    }

    var reloadAccessibilityLabel: String {
        switch self {
        case .notion:
            "Reload current Notion page"
        case .customPinned:
            "Reload current page"
        }
    }

    var reloadHelp: String {
        switch self {
        case .notion:
            "Reload the current Notion page"
        case .customPinned:
            "Reload the current page"
        }
    }

    var offlineMessage: String {
        switch self {
        case .notion:
            "You're offline. Notion will reconnect when the network is available."
        case .customPinned:
            "You're offline. This page will reload when the network is available."
        }
    }

    var failedLoadPresentation: FailedLoadBannerAccessibilityPresentation {
        switch self {
        case .notion:
            .failedLoad
        case .customPinned:
            .customPinnedFailedLoad
        }
    }

    var failedLoadMessage: String { failedLoadPresentation.message }
}

struct ContextualPageActionPresentation: Equatable {
    let message: String
    let actionTitle: String
    let actionAccessibilityLabel: String
    let dismissAccessibilityLabel: String

    init(action: ContextualPageAction) {
        self.init(
            message: "Notion page found in \(action.sourceApplicationName)",
            actionTitle: "Open Here",
            actionAccessibilityLabel:
                "Open the Notion page from \(action.sourceApplicationName) in Perch",
            dismissAccessibilityLabel: "Dismiss Open Here"
        )
    }

    init(
        message: String,
        actionTitle: String,
        actionAccessibilityLabel: String,
        dismissAccessibilityLabel: String
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.actionAccessibilityLabel = actionAccessibilityLabel
        self.dismissAccessibilityLabel = dismissAccessibilityLabel
    }
}

struct PiPChromeView: View {
    static let primaryActionID = AppCommandID.newNotionPage
    static let primaryActionAccessibilityLabel = "New Notion Page"
    static let primaryActionHelp = "Create a new page in Perch"
    static let reloadAccessibilityLabel = "Reload current Notion page"
    static let reloadHelp = "Reload the current Notion page"
    static let stashAccessibilityLabel = "Stash Perch to Side"
    static let stashHelp = "Move Perch to the nearest screen edge"
    static let pageSwitcherAccessibilityLabel = "Search Notion pages"
    static let pageSwitcherHelp = "Open Notion search (⌘K)"
    static let topControlsHeight = TopEdgeTrackpadMoveController.activeHeight
    static let topControlsSpacing = DesignTokens.Spacing.compact
    /// Tall enough to catch the pointer as it approaches the top edge without
    /// covering a large clickable region of the Notion page underneath.
    static let topControlsRevealHeight: CGFloat = 16
    static let topControlsHoverOutset: CGFloat = 12

    @ObservedObject var webSession: NotionWebSession
    @ObservedObject var contextualPageActionState: ContextualPageActionState
    @ObservedObject private var agentStreamController: AgentStreamController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @StateObject private var topControlsHover = TopControlsHoverController()
    @State private var reloadFeedbackPending = false
    @State private var reloadSuccessHoldExpiresAt: Date?
    @State private var failedLoadShakeToken = 0
    let commandModel: AppCommandModel
    let panelSizeController: PanelSizeController?
    let panelPositionController: PanelPositionController?
    let onReloadSavedPin: () -> Void
    let onStash: () -> Void
    let onReturnToNotion: () -> Void
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
        commandModel: AppCommandModel = .noOp,
        panelSizeController: PanelSizeController? = nil,
        panelPositionController: PanelPositionController? = nil,
        contextualPageActionState: ContextualPageActionState = ContextualPageActionState(),
        agentStreamController: AgentStreamController? = nil,
        onReloadSavedPin: @escaping () -> Void = {},
        onStash: @escaping () -> Void = {},
        onReturnToNotion: @escaping () -> Void = {}
    ) {
        self.webSession = webSession
        self.commandModel = commandModel
        self.panelSizeController = panelSizeController
        self.panelPositionController = panelPositionController
        self.contextualPageActionState = contextualPageActionState
        self.agentStreamController =
            agentStreamController
            ?? AgentStreamController(target: webSession, notifier: AgentStreamNotifierNoOp())
        self.onReloadSavedPin = onReloadSavedPin
        self.onStash = onStash
        self.onReturnToNotion = onReturnToNotion
    }

    func repinCurrentPage() {
        onReloadSavedPin()
    }

    func openInNotionAndStash() {
        webSession.openInBrowser()
        if destinationChrome == .notion {
            onStash()
        }
    }

    func returnToNotionPage() {
        onReturnToNotion()
    }

    private var destinationChrome: PiPDestinationChrome {
        PiPDestinationChrome(isShowingCustomURL: webSession.isShowingCustomURL)
    }

    func continueLoginInBrowser() {
        webSession.performBrowserLoginAction()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let action = contextualPageActionState.action {
                let presentation = ContextualPageActionPresentation(action: action)
                HStack(spacing: DesignTokens.Spacing.control) {
                    Label(presentation.message, systemImage: "link")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: DesignTokens.Spacing.compact)
                    Button(presentation.actionTitle) {
                        contextualPageActionState.accept()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel(presentation.actionAccessibilityLabel)
                    Button {
                        contextualPageActionState.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(presentation.dismissAccessibilityLabel)
                }
                .padding(.horizontal, DesignTokens.Spacing.control)
                .padding(.vertical, DesignTokens.Spacing.compact)
                .accessibilityElement(children: .contain)
                .transition(CrossBlurReveal.statusBanner)

                Divider()
            }

            if let banner = statusBannerKind {
                statusBanner(banner)
                    .transition(CrossBlurReveal.statusBanner)
                    .errorShake(
                        trigger: failedLoadShakeToken,
                        reducesMotion: reduceMotion
                    )
                    .onAppear {
                        if banner == .failedLoad {
                            failedLoadShakeToken += 1
                        }
                    }
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
        .overlay(alignment: .bottomLeading) {
            AgentStreamOverlayView(controller: agentStreamController)
        }
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .frame(width: Self.topControlsRevealHeight)
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
                        .transition(CrossBlurReveal.pipChrome)
                }
            }
        }
        .animation(
            StatusBannerMotion.animation(
                isAppearing: hasVisibleStatusBanner,
                reducesMotion: reduceMotion
            ),
            value: statusBannerMotionIdentity
        )
        .animation(
            PiPChromeRevealMotion.animation(
                isAppearing: showsTopControls,
                reducesMotion: reduceMotion
            ),
            value: Self.topToolbarPresentation(
                showsTopControls: showsTopControls
            )
        )
        .onDisappear {
            topControlsHover.cancel()
        }
        .onChange(of: webSession.state) { previousState, currentState in
            if let expiresAt = ReloadIconSwapPolicy.successHoldExpiresAt(
                isPending: reloadFeedbackPending,
                previousState: previousState,
                currentState: currentState,
                reducesMotion: reduceMotion,
                now: Date()
            ) {
                reloadSuccessHoldExpiresAt = expiresAt
            }
            if reloadFeedbackPending,
                ReloadCompletionMotionPolicy.shouldFinishPendingReload(
                    currentState: currentState
                )
            {
                reloadFeedbackPending = false
            }
        }
        .task(id: reloadSuccessHoldExpiresAt) {
            guard let expiresAt = reloadSuccessHoldExpiresAt else { return }
            let remaining = expiresAt.timeIntervalSinceNow
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            reloadSuccessHoldExpiresAt = nil
        }
    }

    private var topControlsOverlay: some View {
        VStack(spacing: 0) {
            if let panelPositionController {
                PanelCornerControls(controller: panelPositionController)
            }

            if panelPositionController != nil {
                Divider()
                    .frame(width: 14)
                    .padding(.vertical, DesignTokens.Spacing.compact)
            }
            expandedTopControls
        }
        .padding(DesignTokens.Spacing.compact)
        .frame(width: Self.topControlsHeight)
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
        VStack(spacing: Self.topControlsSpacing) {
            if destinationChrome.showsNotionPageActions {
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
                    webSession.presentCommandPalette()
                } label: {
                    Image(systemName: "book")
                        .frame(
                            width: PanelCornerControls.minimumHitTarget,
                            height: PanelCornerControls.minimumHitTarget
                        )
                        .contentShape(Rectangle())
                }
                .chromePressStyle()
                .accessibilityLabel(Self.pageSwitcherAccessibilityLabel)
                .help(Self.pageSwitcherHelp)
            } else {
                Button(action: returnToNotionPage) {
                    NotionToolbarMark()
                        .frame(
                            width: PanelCornerControls.minimumHitTarget,
                            height: PanelCornerControls.minimumHitTarget
                        )
                        .contentShape(Rectangle())
                }
                .chromePressStyle()
                .accessibilityLabel(destinationChrome.showNotionAccessibilityLabel)
                .help(destinationChrome.showNotionHelp)
            }

            Button {
                reloadFeedbackPending = true
                repinCurrentPage()
            } label: {
                ReloadGlyphView(glyph: reloadGlyph)
            }
            .chromePressStyle()
            .accessibilityLabel(reloadControlAccessibilityLabel)
            .help(destinationChrome.reloadHelp)

            Button(action: openInNotionAndStash) {
                if destinationChrome.showsNotionPageActions {
                    NotionToolbarMark()
                        .frame(
                            width: PanelCornerControls.minimumHitTarget,
                            height: PanelCornerControls.minimumHitTarget
                        )
                        .contentShape(Rectangle())
                } else {
                    Image(systemName: "globe")
                        .frame(
                            width: PanelCornerControls.minimumHitTarget,
                            height: PanelCornerControls.minimumHitTarget
                        )
                        .contentShape(Rectangle())
                }
            }
            .chromePressStyle()
            .accessibilityLabel(destinationChrome.openInBrowserAccessibilityLabel)
            .help(destinationChrome.openInBrowserHelp)

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

    private var statusBannerKind: PiPStatusBannerKind? {
        PiPStatusBannerKind(
            sessionState: webSession.state,
            browserLogin: NotionBrowserLoginPresentation(
                state: webSession.browserLoginState
            )
        )
    }

    private var hasVisibleStatusBanner: Bool {
        contextualPageActionState.action != nil || statusBannerKind != nil
    }

    private var statusBannerMotionIdentity: String {
        if let action = contextualPageActionState.action {
            return "contextual:\(action.page.pageID)"
        }
        switch statusBannerKind {
        case let .browserLogin(presentation):
            return "login:\(presentation.message)"
        case .offline:
            return "offline"
        case .failedLoad:
            return "failed"
        case nil:
            return "none"
        }
    }

    private var reloadGlyph: ReloadGlyph {
        ReloadIconSwapPolicy.glyph(
            sessionState: webSession.state,
            successHoldExpiresAt: reloadSuccessHoldExpiresAt,
            now: Date()
        )
    }

    private var reloadControlAccessibilityLabel: String {
        switch reloadGlyph {
        case .idle:
            destinationChrome.reloadAccessibilityLabel
        case .loading:
            destinationChrome == .customPinned ? "Loading page" : "Loading Notion page"
        case .success:
            "Reload complete"
        }
    }

    @ViewBuilder
    private func statusBanner(_ banner: PiPStatusBannerKind) -> some View {
        switch banner {
        case let .browserLogin(browserLogin):
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
        case .offline:
            HStack(spacing: DesignTokens.Spacing.control) {
                Label(
                    destinationChrome.offlineMessage,
                    systemImage: "wifi.slash"
                )
                .font(.caption)
            }
            .padding(.horizontal, DesignTokens.Spacing.control)
            .padding(.vertical, DesignTokens.Spacing.compact)
            .accessibilityElement(children: .contain)

            Divider()
        case .failedLoad:
            let presentation = destinationChrome.failedLoadPresentation
            HStack(spacing: DesignTokens.Spacing.control) {
                Label(presentation.message, systemImage: "exclamationmark.triangle")
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
    }
}

enum PiPStatusBannerKind: Equatable {
    case browserLogin(NotionBrowserLoginPresentation)
    case offline
    case failedLoad

    init?(
        sessionState: NotionWebSessionState,
        browserLogin: NotionBrowserLoginPresentation?
    ) {
        if let browserLogin {
            self = .browserLogin(browserLogin)
        } else if sessionState == .offline {
            self = .offline
        } else if case .failed = sessionState {
            self = .failedLoad
        } else {
            return nil
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
            ToolbarHoverMotion.animation(
                isHovering: isHovering,
                reducesMotion: reduceMotion
            ),
            value: isHovering
        )
        .accessibilityHidden(true)
    }
}
