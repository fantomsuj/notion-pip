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
    let statusMessage: String?
    let appearance: Appearance
    let showsProgress: Bool

    init(
        systemImage: String,
        statusMessage: String?,
        appearance: Appearance,
        showsProgress: Bool
    ) {
        self.systemImage = systemImage
        self.statusMessage = statusMessage
        self.appearance = appearance
        self.showsProgress = showsProgress
    }

    init(state: QuickCopyState) {
        switch state {
        case .off:
            self.init(
                systemImage: "text.append",
                statusMessage: nil,
                appearance: .off,
                showsProgress: false
            )
        case .requestingPermission:
            self.init(
                systemImage: "hourglass",
                statusMessage: "Turning Quick Copy on…",
                appearance: .requesting,
                showsProgress: true
            )
        case .permissionNeeded:
            self.init(
                systemImage: "lock.trianglebadge.exclamationmark",
                statusMessage: "Allow Accessibility, then click to retry.",
                appearance: .permissionNeeded,
                showsProgress: false
            )
        case .armed:
            self.init(
                systemImage: "bolt.fill",
                statusMessage: "Quick Copy on",
                appearance: .active,
                showsProgress: false
            )
        case .inserting:
            self.init(
                systemImage: "text.insert",
                statusMessage: "Adding selection…",
                appearance: .active,
                showsProgress: true
            )
        case let .warning(message):
            self.init(
                systemImage: "exclamationmark.triangle.fill",
                statusMessage: message,
                appearance: .warning,
                showsProgress: false
            )
        case let .failed(message):
            self.init(
                systemImage: "cursorarrow.rays",
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
    static let accessibilityLabel = "Turn Quick Copy on or off"
    static let helpText =
        "Insert selected text from other apps at the saved Notion cursor"

    @ObservedObject var controller: QuickCopyController

    var body: some View {
        let presentation = QuickCopyButtonPresentation(state: controller.state)
        HStack(spacing: DesignTokens.Spacing.compact) {
            Button(action: controller.toggle) {
                Group {
                    if presentation.showsProgress {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: presentation.systemImage)
                    }
                }
                .frame(
                    width: Self.controlSize,
                    height: Self.controlSize
                )
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(foregroundStyle(for: presentation.appearance))
            .background {
                Circle().fill(backgroundStyle(for: presentation.appearance))
            }
            .overlay {
                Circle().strokeBorder(.primary.opacity(0.12))
            }
            .help(Self.helpText)
            .accessibilityLabel(Self.accessibilityLabel)
            .accessibilityValue(presentation.statusMessage ?? "Off")

            if let statusMessage = presentation.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DesignTokens.Spacing.control)
                    .padding(.vertical, DesignTokens.Spacing.compact)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
}
