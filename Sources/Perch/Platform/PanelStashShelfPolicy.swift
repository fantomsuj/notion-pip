import CoreGraphics

enum PanelStashShelfPolicy {
    static let width: CGFloat = 300
    static let headerHeight: CGFloat = 44
    static let rowHeight: CGFloat = 50
    static let verticalPadding: CGFloat = 8
    static let edgeGap: CGFloat = 8

    static func size(itemCount: Int) -> CGSize {
        let rows = min(max(itemCount, 0), PiPRecentPagesSnapshot.maximumItems)
        return CGSize(
            width: width,
            height: headerHeight + CGFloat(rows) * rowHeight + verticalPadding * 2
        )
    }

    static func frame(
        attachedTo placement: PanelStashPlacement,
        itemCount: Int,
        visibleFrames: [CGRect]
    ) -> CGRect? {
        guard itemCount > 0,
              let visibleFrame = PanelFramePolicy.targetVisibleFrame(
                for: placement.frame,
                from: visibleFrames
              )
        else {
            return nil
        }

        let preferredSize = size(itemCount: itemCount)
        let fittedSize = CGSize(
            width: min(preferredSize.width, visibleFrame.width),
            height: min(preferredSize.height, visibleFrame.height)
        )
        let preferredX = switch placement.side {
        case .left:
            placement.frame.maxX + edgeGap
        case .right:
            placement.frame.minX - edgeGap - fittedSize.width
        }
        let maximumX = visibleFrame.maxX - fittedSize.width
        let x = min(max(preferredX, visibleFrame.minX), maximumX)
        let preferredY = placement.frame.midY - fittedSize.height / 2
        let maximumY = visibleFrame.maxY - fittedSize.height
        let y = min(max(preferredY, visibleFrame.minY), maximumY)

        return CGRect(origin: CGPoint(x: x, y: y), size: fittedSize)
    }
}
