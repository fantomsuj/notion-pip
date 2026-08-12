import SwiftUI

struct OnboardingView: View {
    let globalShortcut: GlobalShortcut
    @ObservedObject var pageURLInputState: PageURLInputState
    let onPinPage: @MainActor () -> Void
    let onComplete: @MainActor () -> Void
    let onOpenSettings: @MainActor () -> Void

    @State private var selection = OnboardingStep.welcome

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 204)

            Divider()

            content
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(DesignTokens.Colors.background)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.container) {
            Text("Perch")
                .font(.headline)
                .padding(.horizontal, DesignTokens.Spacing.compact)

            VStack(spacing: DesignTokens.Spacing.compact) {
                ForEach(OnboardingStep.allCases) { step in
                    Button {
                        selection = step
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.control) {
                            Image(systemName: step.symbolName)
                                .frame(width: 18)
                            Text(step.sidebarTitle)
                            Spacer(minLength: 0)
                        }
                        .font(.callout.weight(step == selection ? .semibold : .regular))
                        .foregroundStyle(
                            step == selection
                                ? DesignTokens.Colors.primaryText
                                : DesignTokens.Colors.secondaryText
                        )
                        .padding(.horizontal, DesignTokens.Spacing.control)
                        .padding(.vertical, 7)
                        .background {
                            if step == selection {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                                    .fill(Color.accentColor.opacity(0.12))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Step \(step.rawValue + 1): \(step.sidebarTitle)")
                }
            }

            Spacer()

            Text("You can reopen this guide from Getting Started… in the app menu.")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DesignTokens.Spacing.compact)
        }
        .padding(DesignTokens.Spacing.container)
        .background(.regularMaterial)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selection.eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .tracking(0.7)
                Spacer()
                Text("\(selection.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            Text(selection.heading)
                .font(.system(size: 28, weight: .semibold))
                .padding(.top, DesignTokens.Spacing.section)

            Text(selection.detail)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DesignTokens.Spacing.control)

            artwork
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 22)

            Divider()

            HStack(spacing: DesignTokens.Spacing.control) {
                Button("Skip") {
                    onComplete()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if selection != .welcome {
                    Button("Back") {
                        selection = selection.previous
                    }
                }

                if selection == .shortcuts {
                    Button("Finish") {
                        onComplete()
                    }
                }

                Button(selection == .shortcuts ? "Open Settings" : "Continue") {
                    if selection == .shortcuts {
                        onOpenSettings()
                    } else {
                        selection = selection.next
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, DesignTokens.Spacing.container)
        }
        .padding(24)
    }

    @ViewBuilder
    private var artwork: some View {
        switch selection {
        case .welcome:
            OverlayArtwork()
        case .pinPage:
            PinPageArtwork(
                state: pageURLInputState,
                onSubmit: onPinPage
            )
        case .panelControls:
            PanelControlsArtwork()
        case .appMenu:
            AppMenuArtwork(globalShortcut: globalShortcut)
        case .shortcuts:
            ShortcutsArtwork(globalShortcut: globalShortcut)
        }
    }
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case pinPage
    case panelControls
    case appMenu
    case shortcuts

    var id: Int { rawValue }

    var sidebarTitle: String {
        switch self {
        case .welcome: "Welcome"
        case .pinPage: "Pin a page"
        case .panelControls: "Panel controls"
        case .appMenu: "Menu & settings"
        case .shortcuts: "Work faster"
        }
    }

    var symbolName: String {
        switch self {
        case .welcome: "rectangle.on.rectangle"
        case .pinPage: "pin"
        case .panelControls: "slider.horizontal.3"
        case .appMenu: "menubar.rectangle"
        case .shortcuts: "keyboard"
        }
    }

    var eyebrow: String {
        switch self {
        case .welcome: "Always within reach"
        case .pinPage: "Your page"
        case .panelControls: "The essentials"
        case .appMenu: "Controls"
        case .shortcuts: "Keyboard"
        }
    }

    var heading: String {
        switch self {
        case .welcome: "Keep one Notion page close"
        case .pinPage: "Choose the page that matters now"
        case .panelControls: "Everything you need is at the top"
        case .appMenu: "Know where the controls live"
        case .shortcuts: "Bring it back without breaking focus"
        }
    }

    var detail: String {
        switch self {
        case .welcome:
            "Perch is a floating panel that follows you across desktop Spaces and full-screen apps. It stays out of the Dock so your workspace remains uncluttered."
        case .pinPage:
            "Paste a Notion page link below to pin it now. The page keeps its navigation and session as you move between other apps."
        case .panelControls:
            "Hover over the top edge of the PiP to reveal the centered toolbar, including four corner arrows and the other controls. Double-click the title bar above it to maximize the PiP, then double-click again to restore it."
        case .appMenu:
            "Click the Perch icon in the menu bar for Show, Stash, New Notion Page, Settings, and this guide. The ellipsis inside the panel opens the same app commands."
        case .shortcuts:
            "Use the global shortcut from any app. You can change it—and whether the menu-bar icon is visible—in Settings."
        }
    }

    var next: OnboardingStep {
        OnboardingStep(rawValue: min(rawValue + 1, Self.allCases.count - 1)) ?? self
    }

    var previous: OnboardingStep {
        OnboardingStep(rawValue: max(rawValue - 1, 0)) ?? self
    }
}

struct OnboardingToolbarControl: Identifiable, Equatable {
    enum Icon: Equatable {
        case system(String)
        case notion
    }

    let title: String
    let icon: Icon

    var id: String { title }

    static let all: [Self] = [
        Self(title: "New Notion page", icon: .system("plus")),
        Self(title: "Switch page", icon: .system("rectangle.stack")),
        Self(title: "Reload pinned page", icon: .system("arrow.clockwise")),
        Self(title: "Open in browser", icon: .notion),
        Self(title: "App menu & sizes", icon: .system("ellipsis.circle")),
        Self(title: "Stash to edge", icon: .system("arrow.down.right.and.arrow.up.left")),
    ]
}

private struct OverlayArtwork: View {
    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.panel)
                .fill(DesignTokens.Colors.surface)
                .overlay {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Circle().fill(.red.opacity(0.75)).frame(width: 8, height: 8)
                            Circle().fill(.yellow.opacity(0.75)).frame(width: 8, height: 8)
                            Circle().fill(.green.opacity(0.75)).frame(width: 8, height: 8)
                            Spacer()
                        }
                        .padding(10)
                        Divider()
                        Spacer()
                    }
                }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
                HStack {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.tint)
                    Text("Project roadmap")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                Divider()
                RoundedRectangle(cornerRadius: 3)
                    .fill(DesignTokens.Colors.primaryText.opacity(0.18))
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 3)
                    .fill(DesignTokens.Colors.primaryText.opacity(0.10))
                    .frame(width: 150, height: 8)
                Spacer()
                Label("Available on every Space", systemImage: "square.grid.2x2")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            .padding(14)
            .frame(width: 260, height: 178)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.panel)
                    .stroke(DesignTokens.Colors.border)
            }
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            .padding(.trailing, 22)
        }
        .frame(maxWidth: 440, minHeight: 220, maxHeight: 240)
        .accessibilityHidden(true)
    }
}

private struct PinPageArtwork: View {
    @ObservedObject var state: PageURLInputState
    let onSubmit: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            Label("Pinned Page", systemImage: "pin")
                .font(.headline)

            PageURLInputView(state: state, onSubmit: onSubmit)

            Label("Your signed-in Notion session stays in the panel", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: 440)
        .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }
}

private struct PanelControlsArtwork: View {
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.section) {
            VStack(spacing: 0) {
                titleBar
                Divider()
                toolbar
            }
            .background(
                DesignTokens.Colors.surface,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .stroke(DesignTokens.Colors.border)
            }

            Grid(
                alignment: .leading,
                horizontalSpacing: DesignTokens.Spacing.container,
                verticalSpacing: DesignTokens.Spacing.control
            ) {
                ForEach(
                    Array(stride(from: 0, to: OnboardingToolbarControl.all.count, by: 2)),
                    id: \.self
                ) { index in
                    GridRow {
                        controlLabel(OnboardingToolbarControl.all[index])
                        controlLabel(OnboardingToolbarControl.all[index + 1])
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.compact)
        }
        .frame(maxWidth: 440)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var titleBar: some View {
        HStack(spacing: 6) {
            Circle().fill(.red.opacity(0.75)).frame(width: 8, height: 8)
            Circle().fill(.yellow.opacity(0.75)).frame(width: 8, height: 8)
            Circle().fill(.green.opacity(0.75)).frame(width: 8, height: 8)
            Spacer()
            Label("Double-click to maximize", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Spacer()
            Color.clear.frame(width: 36, height: 1)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    private var toolbar: some View {
        ZStack {
            DesignTokens.Colors.background

            HStack(spacing: DesignTokens.Spacing.compact) {
                ForEach(PanelCorner.allCases, id: \.self) { corner in
                    Image(systemName: corner.symbolName)
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 16, height: 20)
                }
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, DesignTokens.Spacing.compact)
                ForEach(OnboardingToolbarControl.all) { control in
                    controlIcon(control)
                        .frame(width: 16, height: 20)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.compact)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .stroke(DesignTokens.Colors.border.opacity(0.7), lineWidth: 0.5)
            }
        }
        .frame(height: 34)
    }

    private func controlLabel(_ control: OnboardingToolbarControl) -> some View {
        Label {
            Text(control.title)
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        } icon: {
            controlIcon(control)
                .frame(width: 16)
                .foregroundStyle(DesignTokens.Colors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func controlIcon(_ control: OnboardingToolbarControl) -> some View {
        switch control.icon {
        case let .system(symbolName):
            Image(systemName: symbolName)
        case .notion:
            OnboardingNotionMark()
        }
    }

    private var accessibilitySummary: String {
        "Panel controls. Hover over the top edge to reveal the centered toolbar with four corner movement arrows and: "
            + OnboardingToolbarControl.all.map(\.title).joined(separator: ", ")
            + ". Double-click the title bar to maximize or restore the PiP."
    }
}

private struct OnboardingNotionMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(lineWidth: 1.1)
            Text("N")
                .font(.system(size: 9, weight: .black, design: .serif))
                .offset(y: -0.2)
        }
        .frame(width: 13, height: 13)
    }
}

private struct AppMenuArtwork: View {
    let globalShortcut: GlobalShortcut

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(spacing: DesignTokens.Spacing.control) {
                HStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "rectangle.on.rectangle")
                        .foregroundStyle(.tint)
                        .padding(6)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .frame(width: 190, height: 30)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))

                Text("Menu bar")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            VStack(alignment: .leading, spacing: 0) {
                MenuPreviewRow(title: "Show Perch", shortcut: globalShortcut.displayString)
                Divider()
                MenuPreviewRow(title: "New Notion Page", shortcut: "⌘N")
                Divider()
                MenuPreviewRow(title: "Settings…", shortcut: "⌘,")
                MenuPreviewRow(title: "Getting Started…")
            }
            .padding(.vertical, 6)
            .frame(width: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DesignTokens.Colors.border)
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        }
        .accessibilityHidden(true)
    }

}

private struct MenuPreviewRow: View {
    let title: String
    var shortcut: String? = nil

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 29)
    }
}

private struct ShortcutsArtwork: View {
    let globalShortcut: GlobalShortcut

    var body: some View {
        ShortcutRow(
            title: "Show or hide the panel",
            detail: "Hold to peek. Double-press to keep the panel open.",
            shortcut: globalShortcut.displayString
        )
        .frame(maxWidth: 440)
    }
}

private struct ShortcutRow: View {
    let title: String
    let detail: String
    let shortcut: String

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.container) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(DesignTokens.Colors.border)
                }
                .accessibilityLabel(shortcutAccessibilityLabel)
        }
        .padding(.horizontal, 4)
    }

    private var shortcutAccessibilityLabel: String {
        shortcut
            .replacingOccurrences(of: "⌃", with: "Control ")
            .replacingOccurrences(of: "⌥", with: "Option ")
            .replacingOccurrences(of: "⇧", with: "Shift ")
            .replacingOccurrences(of: "⌘", with: "Command ")
    }
}
