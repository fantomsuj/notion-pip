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
    static let pageSwitcherAccessibilityLabel = "Switch Notion page"
    static let topControlsHeight: CGFloat = 32
    static let topControlsRevealHeight: CGFloat = 8
    static let topControlsHoverOutset: CGFloat = 12

    @ObservedObject var webSession: NotionWebSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @StateObject private var topControlsHover = TopControlsHoverController()
    @State private var presentsPageSwitcher = false
    @ObservedObject var pageSwitcherController: PageSwitcherController
    let commandModel: AppCommandModel
    let panelSizeController: PanelSizeController?
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

    static func shouldHostNotionWebView(for session: NotionWebSession) -> Bool {
        session.shouldHostWebView
    }

    init(
        webSession: NotionWebSession,
        pageSwitcherController: PageSwitcherController = PageSwitcherController(),
        commandModel: AppCommandModel = .noOp,
        panelSizeController: PanelSizeController? = nil,
        onReloadSavedPin: @escaping () -> Void = {},
        onStash: @escaping () -> Void = {},
        onPageSwitcherSelection: @escaping (PageSwitcherSelection) -> Void = { _ in }
    ) {
        self.webSession = webSession
        self.pageSwitcherController = pageSwitcherController
        self.commandModel = commandModel
        self.panelSizeController = panelSizeController
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

    func enterOfflineCaptureMode() {
        guard webSession.state == .offline,
              commandModel.command(for: Self.primaryActionID)?.isEnabled == true
        else {
            return
        }
        commandModel.perform(Self.primaryActionID)
    }

    var body: some View {
        VStack(spacing: 0) {
            if webSession.state == .offline {
                HStack(spacing: DesignTokens.Spacing.control) {
                    Label("You're offline. Quick Capture saves notes on this Mac and sends them when Notion reconnects.", systemImage: "wifi.slash")
                        .font(.caption)
                    Spacer()
                    Button("Write Offline Note") {
                        commandModel.perform(Self.primaryActionID)
                    }
                    .disabled(!(commandModel.command(for: Self.primaryActionID)?.isEnabled ?? false))
                    .accessibilityLabel("Write an offline note")
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
                    .overlay {
                        GeometryReader { proxy in
                            Button {
                                let copiedText = NSPasteboard.general.string(forType: .string)
                                guard let copiedText, !copiedText.isEmpty else { return }
                                webSession.rememberCurrentEditorCursor { remembered in
                                    guard remembered else { return }
                                    webSession.insertAtSavedEditorCursor(copiedText) { _ in }
                                }
                            } label: {
                                Label("Fill copied text", systemImage: "doc.on.clipboard")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .frame(
                                width: CursorAdjacentControlPlacement.controlSize,
                                height: CursorAdjacentControlPlacement.controlSize
                            )
                            .help("Insert copied text at the current Notion cursor")
                            .accessibilityLabel("Fill copied text at Notion cursor")
                            .position(
                                CursorAdjacentControlPlacement.center(
                                    for: webSession.editorCaretGeometry,
                                    in: proxy.size
                                )
                            )
                            .animation(nil, value: webSession.editorCaretGeometry)
                        }
                    }
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
                if !showsTopControls {
                    Color.clear
                        .frame(height: Self.topControlsRevealHeight)
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            topControlsHover.setHovering(isHovering)
                        }
                        .accessibilityHidden(true)
                }
                topControlsOverlay
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: showsTopControls
        )
        .onDisappear {
            topControlsHover.cancel()
        }
        .onAppear(perform: enterOfflineCaptureMode)
        .onChange(of: webSession.state) {
            enterOfflineCaptureMode()
        }
    }

    private var topControlsOverlay: some View {
        HStack {
            Spacer()

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

            Button {
                presentsPageSwitcher.toggle()
            } label: {
                Image(systemName: "rectangle.stack")
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.reloadAccessibilityLabel)
            .help(Self.reloadHelp)

            Button(action: openInNotionAndStash) {
                NotionToolbarMark()
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
        .padding(.horizontal, DesignTokens.Spacing.control)
        .frame(height: Self.topControlsHeight)
        .background(DesignTokens.Colors.background)
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle().inset(by: -Self.topControlsHoverOutset))
        .onHover { isHovering in
            topControlsHover.setHovering(isHovering)
        }
        .opacity(showsTopControls ? 1 : 0)
        .offset(y: showsTopControls ? 0 : -Self.topControlsHeight)
        .allowsHitTesting(showsTopControls)
        .accessibilityHidden(!showsTopControls)
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
