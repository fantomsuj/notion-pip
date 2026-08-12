import CoreGraphics

enum PanelPullRevealPolicy {
    static let restoreThreshold: CGFloat = 0.42
    private static let resistanceStart: CGFloat = 0.32
    private static let resistedThresholdProgress: CGFloat = 0.365
    private static let snappedThresholdProgress: CGFloat = 0.44

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

    /// Maps pointer progress to a physical-feeling reveal while preserving the raw
    /// progress for the final commit decision. The panel begins to resist shortly
    /// before the commit threshold, then advances by a small perceptible snap when
    /// the threshold is crossed.
    static func interactiveProgress(
        forRawProgress rawProgress: CGFloat,
        reducesMotion: Bool
    ) -> CGFloat {
        let rawProgress = min(max(rawProgress, 0), 1)
        guard !reducesMotion else { return rawProgress }

        if rawProgress < resistanceStart {
            return rawProgress
        }
        if rawProgress < restoreThreshold {
            let intervalProgress = (rawProgress - resistanceStart)
                / (restoreThreshold - resistanceStart)
            return resistanceStart
                + intervalProgress * (resistedThresholdProgress - resistanceStart)
        }

        let intervalProgress = (rawProgress - restoreThreshold)
            / (1 - restoreThreshold)
        return snappedThresholdProgress
            + intervalProgress * (1 - snappedThresholdProgress)
    }

    static func crossedRestoreThreshold(from previous: CGFloat, to current: CGFloat) -> Bool {
        previous < restoreThreshold && current >= restoreThreshold
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
