import CoreGraphics

struct ScreenGeometry: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

struct PanelFrameAnchor: Codable, Equatable, Sendable {
    enum HorizontalEdge: Codable, Equatable, Sendable {
        case left
        case right
    }

    enum VerticalEdge: Codable, Equatable, Sendable {
        case bottom
        case top
    }

    let horizontalEdge: HorizontalEdge
    let horizontalInset: CGFloat
    let verticalEdge: VerticalEdge
    let verticalInset: CGFloat
}

struct PanelFramePlacement: Equatable {
    /// The frame that can currently be shown on the selected display.
    let frame: CGRect

    /// The user's requested content size, even when `frame` had to be made smaller.
    let preferredContentSize: CGSize

    /// The edge relationship captured before any temporary size clamping.
    let anchor: PanelFrameAnchor?
}

struct PanelCornerSnapTarget: Equatable {
    let corner: PanelCorner
    let frame: CGRect
}

enum PanelFramePolicy {
    static let cornerInset: CGFloat = 0
    static let cornerSnapThreshold: CGFloat = 72

    static func cornerPlacement(
        preferredContentSize: CGSize,
        at corner: PanelCorner,
        relativeTo currentFrame: CGRect,
        visibleFrames: [CGRect],
        minimumContentSize: CGSize = .zero,
        frameForContentRect: (CGRect) -> CGRect
    ) -> PanelFramePlacement? {
        guard let visibleFrame = targetVisibleFrame(
            for: currentFrame,
            from: visibleFrames
        ) else {
            return nil
        }

        let preferredFrameSize = frameSize(
            forContentSize: preferredContentSize,
            minimumContentSize: minimumContentSize,
            frameForContentRect: frameForContentRect
        )
        let fittedSize = CGSize(
            width: min(
                preferredFrameSize.width,
                max(visibleFrame.width - cornerInset, 0)
            ),
            height: min(
                preferredFrameSize.height,
                max(visibleFrame.height - cornerInset, 0)
            )
        )
        let anchor = corner.anchor()

        return PanelFramePlacement(
            frame: frame(of: fittedSize, anchoredBy: anchor, in: visibleFrame),
            preferredContentSize: preferredContentSize,
            anchor: anchor
        )
    }

    static func corner(
        for frame: CGRect,
        visibleFrames: [CGRect],
        inset: CGFloat = cornerInset,
        tolerance: CGFloat = 1
    ) -> PanelCorner? {
        guard let visibleFrame = targetVisibleFrame(for: frame, from: visibleFrames) else {
            return nil
        }

        return PanelCorner.allCases.first { corner in
            let anchor = corner.anchor(inset: inset)
            let horizontalInset = switch anchor.horizontalEdge {
            case .left:
                frame.minX - visibleFrame.minX
            case .right:
                visibleFrame.maxX - frame.maxX
            }
            let verticalInset = switch anchor.verticalEdge {
            case .bottom:
                frame.minY - visibleFrame.minY
            case .top:
                visibleFrame.maxY - frame.maxY
            }
            return abs(horizontalInset - anchor.horizontalInset) <= tolerance
                && abs(verticalInset - anchor.verticalInset) <= tolerance
        }
    }

    /// Returns a corner-aligned frame when both axes are close to or beyond a
    /// corner. Oversized dimensions are reduced only enough to fit the display.
    /// Frames away from a corner are unchanged.
    static func cornerSnapped(
        _ frame: CGRect,
        visibleFrames: [CGRect],
        inset: CGFloat = cornerInset,
        threshold: CGFloat = cornerSnapThreshold
    ) -> CGRect {
        cornerSnapTarget(
            for: frame,
            visibleFrames: visibleFrames,
            inset: inset,
            threshold: threshold
        )?.frame ?? frame
    }

    static func cornerSnapTarget(
        for frame: CGRect,
        visibleFrames: [CGRect],
        inset: CGFloat = cornerInset,
        threshold: CGFloat = cornerSnapThreshold
    ) -> PanelCornerSnapTarget? {
        guard let visibleFrame = targetVisibleFrame(for: frame, from: visibleFrames) else {
            return nil
        }

        let nearestAnchor = nearestAnchor(for: frame, in: visibleFrame)
        guard nearestAnchor.horizontalInset <= inset + threshold,
            nearestAnchor.verticalInset <= inset + threshold
        else {
            return nil
        }

        let cornerAnchor = PanelFrameAnchor(
            horizontalEdge: nearestAnchor.horizontalEdge,
            horizontalInset: inset,
            verticalEdge: nearestAnchor.verticalEdge,
            verticalInset: inset
        )
        let fittedSize = CGSize(
            width: min(frame.width, max(visibleFrame.width - inset, 0)),
            height: min(frame.height, max(visibleFrame.height - inset, 0))
        )
        return PanelCornerSnapTarget(
            corner: PanelCorner(anchor: cornerAnchor),
            frame: self.frame(
                of: fittedSize,
                anchoredBy: cornerAnchor,
                in: visibleFrame
            )
        )
    }

    /// Clamps an existing window frame. Prefer `placement` when the input size is
    /// a content size so window chrome is included before clamping.
    static func clamped(
        _ frame: CGRect,
        visibleFrames: [CGRect],
        minimumSize: CGSize = .zero
    ) -> CGRect {
        let normalizedFrame = normalized(frame, minimumSize: minimumSize)
        guard let targetFrame = targetVisibleFrame(for: normalizedFrame, from: visibleFrames) else {
            return normalizedFrame
        }

        let width = min(normalizedFrame.width, targetFrame.width)
        let height = min(normalizedFrame.height, targetFrame.height)
        let maximumX = targetFrame.maxX - width
        let maximumY = targetFrame.maxY - height

        return CGRect(
            x: min(max(normalizedFrame.minX, targetFrame.minX), maximumX),
            y: min(max(normalizedFrame.minY, targetFrame.minY), maximumY),
            width: width,
            height: height
        )
    }

    /// Clamps size and vertical origin inside the target visible frame while
    /// allowing the panel to travel past the left or right edge.
    static func clampedAllowingHorizontalOverhang(
        _ frame: CGRect,
        visibleFrames: [CGRect],
        minimumSize: CGSize = .zero
    ) -> CGRect {
        preservingHorizontalOrigin(
            of: frame,
            in: clamped(frame, visibleFrames: visibleFrames, minimumSize: minimumSize)
        )
    }

    /// Keeps the proposed horizontal origin so live movement can hang off a
    /// left or right display edge, while using the vertically constrained frame.
    static func preservingHorizontalOrigin(
        of proposed: CGRect,
        in constrained: CGRect
    ) -> CGRect {
        CGRect(
            origin: CGPoint(x: proposed.origin.x, y: constrained.origin.y),
            size: constrained.size
        )
    }

    /// Resolves a preferred content size into the effective window frame that
    /// can be displayed now.
    ///
    /// The preferred size and captured anchor are returned unchanged when the
    /// effective frame must be temporarily clamped. Passing the returned anchor
    /// to a later call restores the preferred size and placement when a larger
    /// display becomes available.
    static func placement(
        preferredContentSize: CGSize,
        anchoredTo currentFrame: CGRect,
        visibleFrames: [CGRect],
        minimumContentSize: CGSize = .zero,
        preserving anchor: PanelFrameAnchor? = nil,
        frameForContentRect: (CGRect) -> CGRect
    ) -> PanelFramePlacement {
        let preferredFrameSize = frameSize(
            forContentSize: preferredContentSize,
            minimumContentSize: minimumContentSize,
            frameForContentRect: frameForContentRect
        )

        guard
            let targetFrame = targetVisibleFrame(
                for: currentFrame,
                from: visibleFrames
            )
        else {
            return PanelFramePlacement(
                frame: CGRect(origin: currentFrame.origin, size: preferredFrameSize),
                preferredContentSize: preferredContentSize,
                anchor: anchor
            )
        }

        let resolvedAnchor =
            anchor
            ?? nearestAnchor(
                for: currentFrame,
                in: targetFrame
            )
        let preferredFrame = frame(
            of: preferredFrameSize,
            anchoredBy: resolvedAnchor,
            in: targetFrame
        )

        return PanelFramePlacement(
            frame: clamped(preferredFrame, visibleFrames: [targetFrame]),
            preferredContentSize: preferredContentSize,
            anchor: resolvedAnchor
        )
    }

    static func frameSize(
        forContentSize contentSize: CGSize,
        minimumContentSize: CGSize = .zero,
        frameForContentRect: (CGRect) -> CGRect
    ) -> CGSize {
        let effectiveContentSize = CGSize(
            width: max(contentSize.width, minimumContentSize.width),
            height: max(contentSize.height, minimumContentSize.height)
        )
        return frameForContentRect(
            CGRect(origin: .zero, size: effectiveContentSize)
        ).size
    }

    static func contentSize(
        forFrame frame: CGRect,
        contentRectForFrameRect: (CGRect) -> CGRect
    ) -> CGSize {
        contentRectForFrameRect(frame).size
    }

    static func restoredContentSize(
        savedWorkingContentSize: CGSize?,
        restoredFrame: CGRect,
        visibleFrames: [CGRect],
        fallbackContentSize: CGSize,
        frameForContentRect: (CGRect) -> CGRect = { $0 },
        contentRectForFrameRect: (CGRect) -> CGRect = { $0 }
    ) -> CGSize {
        if let savedWorkingContentSize {
            let savedFrame = CGRect(
                origin: restoredFrame.origin,
                size: frameSize(
                    forContentSize: savedWorkingContentSize,
                    frameForContentRect: frameForContentRect
                )
            )
            if !fillsVisibleFrame(savedFrame, visibleFrames: visibleFrames) {
                return savedWorkingContentSize
            }
        }

        guard fillsVisibleFrame(restoredFrame, visibleFrames: visibleFrames) else {
            return contentSize(
                forFrame: restoredFrame,
                contentRectForFrameRect: contentRectForFrameRect
            )
        }
        return fallbackContentSize
    }

    /// Legacy frame-size entry point retained for existing callers.
    static func initialFrame(
        size: CGSize,
        minimumSize: CGSize = .zero,
        pointerLocation: CGPoint,
        screens: [ScreenGeometry],
        inset: CGFloat = cornerInset
    ) -> CGRect? {
        guard
            let screen = screens.first(where: { $0.frame.contains(pointerLocation) })
                ?? screens.first
        else {
            return nil
        }

        let preferredFrame = CGRect(
            x: screen.visibleFrame.maxX - size.width - inset,
            y: screen.visibleFrame.maxY - size.height - inset,
            width: size.width,
            height: size.height
        )
        return clamped(
            preferredFrame,
            visibleFrames: [screen.visibleFrame],
            minimumSize: minimumSize
        )
    }

    static func initialFrame(
        contentSize: CGSize,
        minimumContentSize: CGSize = .zero,
        pointerLocation: CGPoint,
        screens: [ScreenGeometry],
        inset: CGFloat = cornerInset,
        frameForContentRect: (CGRect) -> CGRect
    ) -> CGRect? {
        let convertedFrameSize = frameSize(
            forContentSize: contentSize,
            minimumContentSize: minimumContentSize,
            frameForContentRect: frameForContentRect
        )
        return initialFrame(
            size: convertedFrameSize,
            pointerLocation: pointerLocation,
            screens: screens,
            inset: inset
        )
    }

    static func targetVisibleFrame(for frame: CGRect, from visibleFrames: [CGRect]) -> CGRect? {
        visibleFrames.max { first, second in
            let firstIntersection = intersectionArea(of: frame, and: first)
            let secondIntersection = intersectionArea(of: frame, and: second)
            if firstIntersection != secondIntersection {
                return firstIntersection < secondIntersection
            }

            return squaredDistance(from: frame.center, to: first.center)
                > squaredDistance(from: frame.center, to: second.center)
        }
    }

    static func nearestAnchor(
        for frame: CGRect,
        in visibleFrame: CGRect
    ) -> PanelFrameAnchor {
        let leftInset = frame.minX - visibleFrame.minX
        let rightInset = visibleFrame.maxX - frame.maxX
        let bottomInset = frame.minY - visibleFrame.minY
        let topInset = visibleFrame.maxY - frame.maxY

        let horizontalEdge: PanelFrameAnchor.HorizontalEdge
        let horizontalInset: CGFloat
        if leftInset < rightInset {
            horizontalEdge = .left
            horizontalInset = leftInset
        } else {
            horizontalEdge = .right
            horizontalInset = rightInset
        }

        let verticalEdge: PanelFrameAnchor.VerticalEdge
        let verticalInset: CGFloat
        if bottomInset < topInset {
            verticalEdge = .bottom
            verticalInset = bottomInset
        } else {
            verticalEdge = .top
            verticalInset = topInset
        }

        return PanelFrameAnchor(
            horizontalEdge: horizontalEdge,
            horizontalInset: horizontalInset,
            verticalEdge: verticalEdge,
            verticalInset: verticalInset
        )
    }

    private static func normalized(_ frame: CGRect, minimumSize: CGSize) -> CGRect {
        CGRect(
            origin: frame.origin,
            size: CGSize(
                width: max(frame.width, minimumSize.width),
                height: max(frame.height, minimumSize.height)
            )
        )
    }

    private static func fillsVisibleFrame(
        _ frame: CGRect,
        visibleFrames: [CGRect]
    ) -> Bool {
        guard let visibleFrame = targetVisibleFrame(for: frame, from: visibleFrames) else {
            return false
        }
        let tolerance: CGFloat = 1
        return frame.width >= visibleFrame.width - tolerance
            && frame.height >= visibleFrame.height - tolerance
    }

    private static func intersectionArea(of first: CGRect, and second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func squaredDistance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return deltaX * deltaX + deltaY * deltaY
    }

    private static func frame(
        of size: CGSize,
        anchoredBy anchor: PanelFrameAnchor,
        in visibleFrame: CGRect
    ) -> CGRect {
        let x =
            switch anchor.horizontalEdge {
            case .left:
                visibleFrame.minX + anchor.horizontalInset
            case .right:
                visibleFrame.maxX - anchor.horizontalInset - size.width
            }
        let y =
            switch anchor.verticalEdge {
            case .bottom:
                visibleFrame.minY + anchor.verticalInset
            case .top:
                visibleFrame.maxY - anchor.verticalInset - size.height
            }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

extension CGRect {
    fileprivate var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
