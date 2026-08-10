import CoreGraphics

enum PanelTopologyPresentation: Equatable, Sendable {
    case visible
    case stashed(PanelStashIntent)
    case expanded
    case hidden
}

struct PanelTopologyDecision: Equatable, Sendable {
    let acceptedRevision: UInt64
    let panelFrame: CGRect?
    let panelFrameShouldDisplay: Bool
    let stashPlacement: PanelStashPlacement?
}

enum PanelTopologyPolicy {
    static func resolve(
        committedGeometry: PanelGeometry?,
        currentPanelFrame: CGRect,
        fallbackContentSize: CGSize? = nil,
        presentation: PanelTopologyPresentation,
        lastAcceptedRevision: UInt64,
        topology: DisplayTopology,
        minimumContentSize: CGSize,
        frameForContentRect: (CGRect) -> CGRect
    ) -> PanelTopologyDecision? {
        guard topology.revision > lastAcceptedRevision else { return nil }
        guard !topology.displays.isEmpty else {
            return PanelTopologyDecision(
                acceptedRevision: topology.revision,
                panelFrame: nil,
                panelFrameShouldDisplay: false,
                stashPlacement: nil
            )
        }

        switch presentation {
        case .expanded:
            return PanelTopologyDecision(
                acceptedRevision: topology.revision,
                panelFrame: nil,
                panelFrameShouldDisplay: true,
                stashPlacement: nil
            )
        case let .stashed(intent):
            return PanelTopologyDecision(
                acceptedRevision: topology.revision,
                panelFrame: nil,
                panelFrameShouldDisplay: false,
                stashPlacement: PanelStashPolicy.placement(
                    for: intent,
                    currentFrame: currentPanelFrame,
                    topology: topology
                )
            )
        case .visible, .hidden:
            let frame: CGRect
            if let committedGeometry {
                frame = PanelGeometryPolicy.resolvedFrame(
                    for: committedGeometry,
                    topology: topology,
                    minimumContentSize: minimumContentSize,
                    frameForContentRect: frameForContentRect
                )
            } else {
                frame = PanelFramePolicy.placement(
                    preferredContentSize: fallbackContentSize ?? currentPanelFrame.size,
                    anchoredTo: currentPanelFrame,
                    visibleFrames: topology.visibleFrames,
                    minimumContentSize: minimumContentSize,
                    frameForContentRect: frameForContentRect
                ).frame
            }
            return PanelTopologyDecision(
                acceptedRevision: topology.revision,
                panelFrame: frame,
                panelFrameShouldDisplay: presentation == .visible,
                stashPlacement: nil
            )
        }
    }
}
