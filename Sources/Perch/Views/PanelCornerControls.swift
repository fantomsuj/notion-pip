import SwiftUI

extension PanelCorner {
    var symbolName: String {
        switch self {
        case .topLeft:
            "arrow.up.left"
        case .topRight:
            "arrow.up.right"
        case .bottomLeft:
            "arrow.down.left"
        case .bottomRight:
            "arrow.down.right"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .topLeft:
            "Move Perch to top left"
        case .topRight:
            "Move Perch to top right"
        case .bottomLeft:
            "Move Perch to bottom left"
        case .bottomRight:
            "Move Perch to bottom right"
        }
    }
}

struct PanelCornerControls: View {
    static let minimumHitTarget: CGFloat = 24

    @ObservedObject var controller: PanelPositionController

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(PanelCorner.allCases.enumerated()), id: \.element) {
                index,
                corner in
                if index > 0 {
                    Divider()
                        .frame(height: 14)
                }

                Button {
                    controller.move(to: corner)
                } label: {
                    Image(systemName: corner.symbolName)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(
                            width: Self.minimumHitTarget,
                            height: Self.minimumHitTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    controller.selectedCorner == corner
                        ? DesignTokens.Colors.action
                        : DesignTokens.Colors.primaryText
                )
                .background {
                    if controller.selectedCorner == corner {
                        DesignTokens.Colors.action.opacity(0.14)
                    }
                }
                .disabled(!controller.canPosition)
                .accessibilityLabel(corner.accessibilityLabel)
                .accessibilityAddTraits(
                    controller.selectedCorner == corner ? .isSelected : []
                )
                .help(corner.accessibilityLabel)
            }
        }
        .padding(DesignTokens.Spacing.compact)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.border.opacity(0.7), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .accessibilityElement(children: .contain)
    }
}
