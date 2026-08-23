import CoreGraphics

enum StashHandleDropTargetPolicy {
    static let expandedWidth: CGFloat = 260

    static func expandedFrame(
        for placement: PanelStashPlacement,
        visibleFrames: [CGRect]
    ) -> CGRect? {
        guard let visibleFrame = PanelFramePolicy.targetVisibleFrame(
            for: placement.frame,
            from: visibleFrames
        ), placement.frame.minY >= visibleFrame.minY,
           placement.frame.maxY <= visibleFrame.maxY
        else {
            return nil
        }

        let width = min(expandedWidth, visibleFrame.width)
        let anchoredX = switch placement.side {
        case .left:
            placement.frame.minX
        case .right:
            placement.frame.maxX - width
        }
        let x = min(max(anchoredX, visibleFrame.minX), visibleFrame.maxX - width)
        return CGRect(
            x: x,
            y: placement.frame.minY,
            width: width,
            height: placement.frame.height
        )
    }
}
