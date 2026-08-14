import SwiftUI

struct OnboardingView: View {
    let globalShortcut: GlobalShortcut
    @ObservedObject var pageURLInputState: PageURLInputState
    let onPinPage: @MainActor () -> Bool
    let onComplete: @MainActor () -> Void
    let onOpenSettings: @MainActor () -> Void

    @State private var flow = OnboardingFlow()

    private var selection: OnboardingStep { flow.step }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

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

            controls
                .padding(.top, DesignTokens.Spacing.container)
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 430)
        .background(DesignTokens.Colors.background)
        .onAppear {
            requestPageURLFocusIfNeeded()
        }
        .onChange(of: selection) {
            requestPageURLFocusIfNeeded()
        }
    }

    private var header: some View {
        HStack {
            Label("Perch", systemImage: "rectangle.on.rectangle")
                .font(.headline)

            Spacer()

            Text("\(selection.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .accessibilityLabel("Step \(selection.rawValue + 1) of \(OnboardingStep.allCases.count): \(selection.sidebarTitle)")
        }
    }

    private var controls: some View {
        HStack(spacing: DesignTokens.Spacing.control) {
            Button("Skip") {
                perform(.skip)
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if selection != .openPage {
                Button("Back") {
                    perform(.back)
                }
            }

            switch selection {
            case .openPage:
                Button("Set Up Later") {
                    perform(.setUpLater)
                }
            case .bringItBack:
                Button("Shortcut Settings") {
                    perform(.openSettings)
                }

                Button("Continue") {
                    perform(.continue)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .stashIt:
                Button("Finish") {
                    perform(.finish)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        switch selection {
        case .openPage:
            PinPageArtwork(
                state: pageURLInputState,
                onSubmit: { perform(.submitPage, pageOpeningSucceeds: onPinPage()) }
            )
        case .bringItBack:
            ShortcutArtwork(
                title: "Bring Perch forward",
                detail: "Use this shortcut from any app whenever you want your page nearby.",
                shortcut: globalShortcut.displayString
            )
        case .stashIt:
            StashArtwork(shortcut: globalShortcut.displayString)
        }
    }

    private func requestPageURLFocusIfNeeded() {
        guard selection == .openPage else { return }
        pageURLInputState.requestFocus()
    }

    private func perform(
        _ action: OnboardingFlow.Action,
        pageOpeningSucceeds: Bool = false
    ) {
        switch flow.perform(action, pageOpeningSucceeds: pageOpeningSucceeds) {
        case .none:
            break
        case .complete:
            onComplete()
        case .openSettings:
            onOpenSettings()
        }
    }
}

struct OnboardingFlow: Equatable {
    enum Action: Equatable {
        case submitPage
        case setUpLater
        case `continue`
        case back
        case skip
        case finish
        case openSettings
    }

    enum Effect: Equatable {
        case none
        case complete
        case openSettings
    }

    private(set) var step = OnboardingStep.openPage

    @discardableResult
    mutating func perform(
        _ action: Action,
        pageOpeningSucceeds: Bool = false
    ) -> Effect {
        switch action {
        case .submitPage:
            if pageOpeningSucceeds {
                step = .bringItBack
            }
            return .none
        case .setUpLater, .continue:
            step = step.next
            return .none
        case .back:
            step = step.previous
            return .none
        case .skip, .finish:
            return .complete
        case .openSettings:
            return .openSettings
        }
    }
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case openPage
    case bringItBack
    case stashIt

    var id: Int { rawValue }

    var sidebarTitle: String {
        switch self {
        case .openPage: "Open a page"
        case .bringItBack: "Bring it back"
        case .stashIt: "Stash it"
        }
    }

    var heading: String {
        switch self {
        case .openPage: "Start with one Notion page"
        case .bringItBack: "Your page is one shortcut away"
        case .stashIt: "Clear space without losing your page"
        }
    }

    var detail: String {
        switch self {
        case .openPage:
            "Paste a Notion page link below to open it in Perch. Sign in to Notion in the panel if needed."
        case .bringItBack:
            "Press the displayed shortcut from any app to bring Perch forward. You can choose a different shortcut in Settings."
        case .stashIt:
            "When Perch is in the way, press the same shortcut to stash it. Press it again whenever you want it back."
        }
    }

    var next: OnboardingStep {
        OnboardingStep(rawValue: min(rawValue + 1, Self.allCases.count - 1)) ?? self
    }

    var previous: OnboardingStep {
        OnboardingStep(rawValue: max(rawValue - 1, 0)) ?? self
    }
}

private struct PinPageArtwork: View {
    @ObservedObject var state: PageURLInputState
    let onSubmit: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
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

private struct ShortcutArtwork: View {
    let title: String
    let detail: String
    let shortcut: String

    var body: some View {
        ShortcutRow(title: title, detail: detail, shortcut: shortcut)
            .frame(maxWidth: 440)
    }
}

private struct StashArtwork: View {
    let shortcut: String

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.section) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            ShortcutRow(
                title: "Stash Perch when you need room",
                detail: "The same shortcut tucks it away and brings it back.",
                shortcut: shortcut
            )
        }
        .frame(maxWidth: 440)
        .padding(18)
        .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
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
                .background(DesignTokens.Colors.background, in: RoundedRectangle(cornerRadius: 7))
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
