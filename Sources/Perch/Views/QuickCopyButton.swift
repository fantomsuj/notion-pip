import SwiftUI

struct QuickCopyButtonPresentation: Equatable {
    enum Appearance: Equatable {
        case off
        case requesting
        case active
        case permissionNeeded
        case warning
        case failed
    }

    let systemImage: String
    let title: String
    let statusMessage: String?
    let appearance: Appearance
    let showsProgress: Bool

    init(
        systemImage: String,
        title: String,
        statusMessage: String?,
        appearance: Appearance,
        showsProgress: Bool
    ) {
        self.systemImage = systemImage
        self.title = title
        self.statusMessage = statusMessage
        self.appearance = appearance
        self.showsProgress = showsProgress
    }

    init(state: QuickCopyState) {
        switch state {
        case .off:
            self.init(
                systemImage: "text.append",
                title: "Quick Copy to Notion",
                statusMessage: nil,
                appearance: .off,
                showsProgress: false
            )
        case .requestingPermission:
            self.init(
                systemImage: "hourglass",
                title: "Getting ready…",
                statusMessage: "Saving your Notion cursor…",
                appearance: .requesting,
                showsProgress: true
            )
        case .permissionNeeded:
            self.init(
                systemImage: "lock.trianglebadge.exclamationmark",
                title: "Allow Access",
                statusMessage: "Grant Accessibility access, then try again.",
                appearance: .permissionNeeded,
                showsProgress: false
            )
        case .armed:
            self.init(
                systemImage: "checkmark",
                title: "Quick Copy on",
                statusMessage: nil,
                appearance: .active,
                showsProgress: false
            )
        case .inserting:
            self.init(
                systemImage: "text.insert",
                title: "Adding selection…",
                statusMessage: nil,
                appearance: .active,
                showsProgress: true
            )
        case .added:
            self.init(
                systemImage: "checkmark",
                title: "Added",
                statusMessage: nil,
                appearance: .active,
                showsProgress: false
            )
        case let .warning(message):
            self.init(
                systemImage: "exclamationmark.triangle.fill",
                title: "Quick Copy on",
                statusMessage: message,
                appearance: .warning,
                showsProgress: false
            )
        case let .failed(message):
            self.init(
                systemImage: "cursorarrow.rays",
                title: "Try Quick Copy Again",
                statusMessage: message,
                appearance: .failed,
                showsProgress: false
            )
        }
    }
}

struct QuickCopyButton: View {
    static let controlSize: CGFloat = 30
    static let edgeInset: CGFloat = 8
    static let accessibilityLabel = "Quick Copy selections to Notion"
    static let helpText =
        "Place the cursor in Notion, turn on Quick Copy, then select text in another app"

    @ObservedObject var controller: QuickCopyController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let presentation = QuickCopyButtonPresentation(state: controller.state)
        HStack(spacing: DesignTokens.Spacing.compact) {
            Button(action: controller.toggle) {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    ZStack {
                        if presentation.showsProgress {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 14, height: 14)
                        } else {
                            CrossfadeSymbol(systemName: presentation.systemImage)
                                .id(presentation.systemImage)
                                .frame(width: 14, height: 14)
                        }
                    }
                    .frame(width: 14, height: 14)
                    .animation(iconCrossfadeAnimation, value: presentation.systemImage)
                    .animation(iconCrossfadeAnimation, value: presentation.showsProgress)

                    Text(presentation.title)
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, DesignTokens.Spacing.control)
                .frame(minHeight: Self.controlSize)
                .contentShape(Capsule())
            }
            .chromePressStyle(cornerRadius: Self.controlSize / 2)
            .foregroundStyle(foregroundStyle(for: presentation.appearance))
            .background {
                Capsule().fill(backgroundStyle(for: presentation.appearance))
            }
            .overlay {
                Capsule().strokeBorder(.primary.opacity(0.12))
            }
            .help(Self.helpText)
            .accessibilityLabel(Self.accessibilityLabel)
            .accessibilityValue(presentation.statusMessage ?? presentation.title)

            if let statusMessage = presentation.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DesignTokens.Spacing.control)
                    .padding(.vertical, DesignTokens.Spacing.compact)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    )
            }
        }
    }

    private func foregroundStyle(
        for appearance: QuickCopyButtonPresentation.Appearance
    ) -> Color {
        switch appearance {
        case .active:
            .white
        case .warning, .permissionNeeded:
            .orange
        case .failed:
            DesignTokens.Colors.error
        case .off, .requesting:
            .primary
        }
    }

    private func backgroundStyle(
        for appearance: QuickCopyButtonPresentation.Appearance
    ) -> Color {
        switch appearance {
        case .active:
            .accentColor
        case .warning, .permissionNeeded:
            .orange.opacity(0.18)
        case .failed:
            DesignTokens.Colors.error.opacity(0.16)
        case .off, .requesting:
            Color(nsColor: .controlBackgroundColor).opacity(0.9)
        }
    }

    private var iconCrossfadeAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: InteractionPolicy.iconCrossfadeDuration)
    }
}
