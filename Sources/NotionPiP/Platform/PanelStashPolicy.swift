import CoreGraphics

enum PanelStashSide: Equatable {
    case left
    case right
}

struct PanelStashPlacement: Equatable {
    let side: PanelStashSide
    let frame: CGRect
}

enum PanelStashPolicy {
    static let handleSize = CGSize(width: 36, height: 96)

    static func placement(
        for panelFrame: CGRect,
        visibleFrames: [CGRect]
    ) -> PanelStashPlacement? {
        guard let visibleFrame = PanelFramePolicy.targetVisibleFrame(
            for: panelFrame,
            from: visibleFrames
        ) else {
            return nil
        }

        let side: PanelStashSide = panelFrame.midX <= visibleFrame.midX ? .left : .right
        let x = switch side {
        case .left:
            visibleFrame.minX
        case .right:
            visibleFrame.maxX - handleSize.width
        }
        let centeredY = panelFrame.midY - handleSize.height / 2
        let y = min(
            max(centeredY, visibleFrame.minY),
            visibleFrame.maxY - handleSize.height
        )

        return PanelStashPlacement(
            side: side,
            frame: CGRect(origin: CGPoint(x: x, y: y), size: handleSize)
        )
    }
}
