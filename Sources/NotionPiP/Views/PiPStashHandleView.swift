import SwiftUI

struct PiPStashHandleView: View {
    let side: PanelStashSide
    let onRestore: @MainActor () -> Void

    var body: some View {
        Button(action: onRestore) {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 13, weight: .medium))

                Image(systemName: side == .left ? "chevron.right" : "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: EdgeStashTabShape(side: side))
            .contentShape(EdgeStashTabShape(side: side))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Restore Notion PiP")
        .accessibilityHint("Bring the stashed Notion PiP back from the side.")
        .help("Restore Notion PiP")
    }
}

private struct EdgeStashTabShape: Shape {
    let side: PanelStashSide
    private let radius: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch side {
        case .left:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        }

        path.closeSubpath()
        return path
    }
}
