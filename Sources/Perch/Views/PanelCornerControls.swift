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
    static let minimumHitTarget = InteractionPolicy.compactHitTarget
    static let selectedBackgroundRadius = InteractionPolicy.concentricRadius(
        outer: DesignTokens.Radius.card,
        inset: DesignTokens.Spacing.compact
    )

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
                    ToolbarMotionIcon(
                        style: .corner(corner),
                        systemImage: corner.symbolName
                    )
                        .font(.system(size: 10, weight: .semibold))
                }
                .chromePressStyle(cornerRadius: Self.selectedBackgroundRadius)
                .foregroundStyle(
                    controller.selectedCorner == corner
                        ? DesignTokens.Colors.action
                        : DesignTokens.Colors.primaryText
                )
                .background {
                    if controller.selectedCorner == corner {
                        RoundedRectangle(cornerRadius: Self.selectedBackgroundRadius)
                            .fill(DesignTokens.Colors.action.opacity(0.14))
                    }
                }
                .instantListHoverColor(value: controller.selectedCorner == corner)
                .disabled(!controller.canPosition)
                .accessibilityLabel(corner.accessibilityLabel)
                .accessibilityAddTraits(
                    controller.selectedCorner == corner ? .isSelected : []
                )
                .help(corner.accessibilityLabel)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
