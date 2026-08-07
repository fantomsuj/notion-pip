import CoreGraphics

enum PanelStashSide: Equatable, Sendable {
    case left
    case right
}

struct PanelStashPlacement: Equatable, Sendable {
    let side: PanelStashSide
    let frame: CGRect
}

struct PanelStashIntent: Equatable, Sendable {
    let side: PanelStashSide
    let verticalFraction: CGFloat
    let displayAffinity: DisplayAffinity?
}

enum PanelStashPolicy {
    static let handleSize = CGSize(width: 36, height: 96)

    static func placement(
        for intent: PanelStashIntent,
        currentFrame: CGRect,
        topology: DisplayTopology
    ) -> PanelStashPlacement? {
        guard let display = DisplayTopologyPolicy.targetDisplay(
            for: intent.displayAffinity,
            currentFrame: currentFrame,
            in: topology
        ) else {
            return nil
        }

        let visibleFrame = display.visibleFrame
        let x = switch intent.side {
        case .left:
            visibleFrame.minX
        case .right:
            visibleFrame.maxX - handleSize.width
        }
        let verticalTravel = max(visibleFrame.height - handleSize.height, 0)
        let fraction = min(max(intent.verticalFraction, 0), 1)
        let y = visibleFrame.minY + verticalTravel * fraction
        return PanelStashPlacement(
            side: intent.side,
            frame: CGRect(x: x, y: y, width: handleSize.width, height: handleSize.height)
        )
    }

    static func intent(
        for placement: PanelStashPlacement,
        topology: DisplayTopology
    ) -> PanelStashIntent? {
        guard let display = DisplayTopologyPolicy.targetDisplay(
            for: nil,
            currentFrame: placement.frame,
            in: topology
        ) else {
            return nil
        }

        let verticalTravel = display.visibleFrame.height - handleSize.height
        let fraction: CGFloat
        if verticalTravel > 0 {
            fraction = min(
                max((placement.frame.minY - display.visibleFrame.minY) / verticalTravel, 0),
                1
            )
        } else {
            fraction = 0
        }
        return PanelStashIntent(
            side: placement.side,
            verticalFraction: fraction,
            displayAffinity: display.affinity(in: topology)
        )
    }

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

    static func snappedPlacement(
        for handleFrame: CGRect,
        visibleFrames: [CGRect]
    ) -> PanelStashPlacement? {
        guard let visibleFrame = PanelFramePolicy.targetVisibleFrame(
            for: handleFrame,
            from: visibleFrames
        ) else {
            return nil
        }

        let side: PanelStashSide = handleFrame.midX <= visibleFrame.midX ? .left : .right
        let x = switch side {
        case .left:
            visibleFrame.minX
        case .right:
            visibleFrame.maxX - handleSize.width
        }
        let y = min(
            max(handleFrame.minY, visibleFrame.minY),
            visibleFrame.maxY - handleSize.height
        )

        return PanelStashPlacement(
            side: side,
            frame: CGRect(origin: CGPoint(x: x, y: y), size: handleSize)
        )
    }
}
