import CoreGraphics

enum PanelCorner: String, CaseIterable, Equatable, Hashable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    func anchor(inset: CGFloat = PanelFramePolicy.cornerInset) -> PanelFrameAnchor {
        switch self {
        case .topLeft:
            PanelFrameAnchor(
                horizontalEdge: .left,
                horizontalInset: inset,
                verticalEdge: .top,
                verticalInset: inset
            )
        case .topRight:
            PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: inset,
                verticalEdge: .top,
                verticalInset: inset
            )
        case .bottomLeft:
            PanelFrameAnchor(
                horizontalEdge: .left,
                horizontalInset: inset,
                verticalEdge: .bottom,
                verticalInset: inset
            )
        case .bottomRight:
            PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: inset,
                verticalEdge: .bottom,
                verticalInset: inset
            )
        }
    }
}
