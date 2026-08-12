import CoreGraphics

enum PanelGeometryPolicy {
    static func capture(
        frame: CGRect,
        topology: DisplayTopology,
        desiredContentSize: CGSize? = nil,
        anchor: PanelFrameAnchor? = nil,
        contentRectForFrameRect: (CGRect) -> CGRect
    ) -> PanelGeometry? {
        guard let display = DisplayTopologyPolicy.targetDisplay(
            for: nil,
            currentFrame: frame,
            in: topology
        ) else {
            return nil
        }

        let contentSize = desiredContentSize
            ?? PanelFramePolicy.contentSize(
                forFrame: frame,
                contentRectForFrameRect: contentRectForFrameRect
            )
        guard let validatedContentSize = try? PanelContentSize(contentSize) else {
            return nil
        }

        return try? PanelGeometry(
            desiredContentSize: validatedContentSize,
            frame: frame,
            visibleFrame: display.visibleFrame,
            anchor: anchor
                ?? PanelFramePolicy.nearestAnchor(for: frame, in: display.visibleFrame),
            displayAffinity: display.affinity(in: topology)
        )
    }

    static func capture(
        frame: CGRect,
        visibleFrames: [CGRect],
        desiredContentSize: CGSize? = nil,
        anchor: PanelFrameAnchor? = nil,
        contentRectForFrameRect: (CGRect) -> CGRect
    ) -> PanelGeometry? {
        guard let visibleFrame = PanelFramePolicy.targetVisibleFrame(
            for: frame,
            from: visibleFrames
        ) else {
            return nil
        }

        let contentSize = desiredContentSize
            ?? PanelFramePolicy.contentSize(
                forFrame: frame,
                contentRectForFrameRect: contentRectForFrameRect
            )
        guard let validatedContentSize = try? PanelContentSize(contentSize) else {
            return nil
        }

        return try? PanelGeometry(
            desiredContentSize: validatedContentSize,
            frame: frame,
            visibleFrame: visibleFrame,
            anchor: anchor
                ?? PanelFramePolicy.nearestAnchor(for: frame, in: visibleFrame)
        )
    }

    static func resolvedFrame(
        for geometry: PanelGeometry,
        topology: DisplayTopology,
        minimumContentSize: CGSize,
        frameForContentRect: (CGRect) -> CGRect
    ) -> CGRect {
        guard let display = DisplayTopologyPolicy.targetDisplay(
            for: geometry.displayAffinity,
            currentFrame: geometry.frame,
            in: topology
        ) else {
            return geometry.frame
        }

        if display.visibleFrame == geometry.visibleFrame {
            return PanelFramePolicy.clamped(
                geometry.frame,
                visibleFrames: [display.visibleFrame]
            )
        }

        return PanelFramePolicy.placement(
            preferredContentSize: geometry.desiredContentSize.cgSize,
            anchoredTo: geometry.frame,
            visibleFrames: [display.visibleFrame],
            minimumContentSize: minimumContentSize,
            preserving: geometry.anchor,
            frameForContentRect: frameForContentRect
        ).frame
    }

    static func resolvedFrame(
        for geometry: PanelGeometry,
        visibleFrames: [CGRect],
        minimumContentSize: CGSize,
        frameForContentRect: (CGRect) -> CGRect
    ) -> CGRect {
        if visibleFrames.contains(geometry.visibleFrame) {
            return PanelFramePolicy.clamped(
                geometry.frame,
                visibleFrames: [geometry.visibleFrame]
            )
        }

        return PanelFramePolicy.placement(
            preferredContentSize: geometry.desiredContentSize.cgSize,
            anchoredTo: geometry.frame,
            visibleFrames: visibleFrames,
            minimumContentSize: minimumContentSize,
            preserving: geometry.anchor,
            frameForContentRect: frameForContentRect
        ).frame
    }
}
