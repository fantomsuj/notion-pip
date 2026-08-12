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

    init(anchor: PanelFrameAnchor) {
        switch (anchor.horizontalEdge, anchor.verticalEdge) {
        case (.left, .top):
            self = .topLeft
        case (.right, .top):
            self = .topRight
        case (.left, .bottom):
            self = .bottomLeft
        case (.right, .bottom):
            self = .bottomRight
        }
    }
}
