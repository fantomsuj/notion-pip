import CoreGraphics

enum PanelPullRevealPolicy {
    static let restoreThreshold: CGFloat = 0.42

    static func inwardDistance(forHorizontalDelta deltaX: CGFloat, side: PanelStashSide) -> CGFloat {
        max(side == .left ? deltaX : -deltaX, 0)
    }

    static func revealTravel(forPanelWidth width: CGFloat) -> CGFloat {
        min(max(width * 0.42, 150), 240)
    }

    static func progress(forInwardDistance distance: CGFloat, panelWidth: CGFloat) -> CGFloat {
        min(max(distance / revealTravel(forPanelWidth: panelWidth), 0), 1)
    }

    static func shouldRestore(progress: CGFloat) -> Bool {
        progress >= restoreThreshold
    }

    static func hiddenFrame(
        for visibleFrame: CGRect,
        beyond side: PanelStashSide,
        displayFrame: CGRect
    ) -> CGRect {
        let x = switch side {
        case .left:
            displayFrame.minX - visibleFrame.width
        case .right:
            displayFrame.maxX
        }
        return CGRect(origin: CGPoint(x: x, y: visibleFrame.minY), size: visibleFrame.size)
    }

    static func interpolatedFrame(
        from hiddenFrame: CGRect,
        to visibleFrame: CGRect,
        progress: CGFloat
    ) -> CGRect {
        let progress = min(max(progress, 0), 1)
        return CGRect(
            x: hiddenFrame.minX + (visibleFrame.minX - hiddenFrame.minX) * progress,
            y: hiddenFrame.minY + (visibleFrame.minY - hiddenFrame.minY) * progress,
            width: hiddenFrame.width + (visibleFrame.width - hiddenFrame.width) * progress,
            height: hiddenFrame.height + (visibleFrame.height - hiddenFrame.height) * progress
        )
    }
}
