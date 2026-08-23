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

struct PanelDragStashDecision: Equatable, Sendable {
    let placement: PanelStashPlacement
    let restoreFrame: CGRect
}

enum PanelStashPolicy {
    static let handleSize = CGSize(width: 36, height: 96)
    static let dragHiddenFraction: CGFloat = 0.40

    static func dragDecision(
        for panelFrame: CGRect,
        topology: DisplayTopology,
        hiddenFraction: CGFloat = dragHiddenFraction
    ) -> PanelDragStashDecision? {
        guard panelFrame.width > 0,
            let display = DisplayTopologyPolicy.targetDisplay(
                for: nil,
                currentFrame: panelFrame,
                in: topology
            )
        else {
            return nil
        }

        let displayFrame = display.frame
        let visibleFrame = display.visibleFrame
        let requiredOverhang = panelFrame.width * min(max(hiddenFraction, 0), 1)
        let leftOverhang = displayFrame.minX - panelFrame.minX
        let rightOverhang = panelFrame.maxX - displayFrame.maxX
        let side: PanelStashSide
        if leftOverhang > 0,
            leftOverhang >= requiredOverhang,
            !hasAdjacentDisplay(
                beyond: .left,
                of: display,
                panelFrame: panelFrame,
                in: topology
            )
        {
            side = .left
        } else if rightOverhang > 0,
            rightOverhang >= requiredOverhang,
            !hasAdjacentDisplay(
                beyond: .right,
                of: display,
                panelFrame: panelFrame,
                in: topology
            )
        {
            side = .right
        } else {
            return nil
        }

        let handleY = clampedHandleMinY(centering: panelFrame, in: visibleFrame)
        let handleX = switch side {
        case .left:
            visibleFrame.minX
        case .right:
            visibleFrame.maxX - handleSize.width
        }
        return PanelDragStashDecision(
            placement: PanelStashPlacement(
                side: side,
                frame: CGRect(
                    origin: CGPoint(x: handleX, y: handleY),
                    size: handleSize
                )
            ),
            restoreFrame: PanelFramePolicy.clamped(
                panelFrame,
                visibleFrames: [visibleFrame]
            )
        )
    }

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
        let y = clampedHandleMinY(centering: panelFrame, in: visibleFrame)

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
        let travel = max(visibleFrame.height - handleSize.height, 0)
        let y = min(
            max(handleFrame.minY, visibleFrame.minY),
            visibleFrame.minY + travel
        )

        return PanelStashPlacement(
            side: side,
            frame: CGRect(origin: CGPoint(x: x, y: y), size: handleSize)
        )
    }

    private static func hasAdjacentDisplay(
        beyond side: PanelStashSide,
        of display: DisplayDescriptor,
        panelFrame: CGRect,
        in topology: DisplayTopology
    ) -> Bool {
        let overhang = overhangRect(
            beyond: side,
            of: display.frame,
            panelFrame: panelFrame
        )
        guard overhang.width > 0, overhang.height > 0 else { return false }
        return topology.displays.contains { candidate in
            guard candidate.identifier != display.identifier
                    || candidate.frame != display.frame
            else {
                return false
            }
            return candidate.frame.intersects(overhang)
        }
    }

    private static func overhangRect(
        beyond side: PanelStashSide,
        of displayFrame: CGRect,
        panelFrame: CGRect
    ) -> CGRect {
        switch side {
        case .left:
            CGRect(
                x: panelFrame.minX,
                y: panelFrame.minY,
                width: displayFrame.minX - panelFrame.minX,
                height: panelFrame.height
            )
        case .right:
            CGRect(
                x: displayFrame.maxX,
                y: panelFrame.minY,
                width: panelFrame.maxX - displayFrame.maxX,
                height: panelFrame.height
            )
        }
    }

    private static func clampedHandleMinY(
        centering panelFrame: CGRect,
        in visibleFrame: CGRect
    ) -> CGFloat {
        let travel = max(visibleFrame.height - handleSize.height, 0)
        let centeredY = panelFrame.midY - handleSize.height / 2
        return min(max(centeredY, visibleFrame.minY), visibleFrame.minY + travel)
    }
}
