import CoreGraphics

enum PanelFramePolicy {
    static func clamped(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard let targetFrame = targetVisibleFrame(for: frame, from: visibleFrames) else {
            return frame
        }

        let width = min(frame.width, targetFrame.width)
        let height = min(frame.height, targetFrame.height)
        let maximumX = targetFrame.maxX - width
        let maximumY = targetFrame.maxY - height

        return CGRect(
            x: min(max(frame.minX, targetFrame.minX), maximumX),
            y: min(max(frame.minY, targetFrame.minY), maximumY),
            width: width,
            height: height
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
