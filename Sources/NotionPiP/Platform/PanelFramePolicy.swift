import CoreGraphics

struct ScreenGeometry: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

enum PanelFramePolicy {
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

    static func initialFrame(
        size: CGSize,
        minimumSize: CGSize = .zero,
        pointerLocation: CGPoint,
        screens: [ScreenGeometry],
        inset: CGFloat = 24
    ) -> CGRect? {
        guard let screen = screens.first(where: { $0.frame.contains(pointerLocation) })
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

    private static func normalized(_ frame: CGRect, minimumSize: CGSize) -> CGRect {
        CGRect(
            origin: frame.origin,
            size: CGSize(
                width: max(frame.width, minimumSize.width),
                height: max(frame.height, minimumSize.height)
            )
        )
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
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
