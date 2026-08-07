import CoreGraphics
import Foundation

struct DisplayDescriptor: Codable, Equatable, Sendable {
    let identifier: UInt32?
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScaleFactor: CGFloat
    let isPrimary: Bool

    func affinity(in topology: DisplayTopology) -> DisplayAffinity {
        DisplayTopologyPolicy.affinity(for: self, in: topology)
    }
}

struct DisplayAffinity: Codable, Equatable, Sendable {
    enum Placement: String, Codable, Equatable, Sendable {
        case primary
        case left
        case right
        case above
        case below
    }

    let identifier: UInt32?
    let visibleSize: CGSize
    let backingScaleFactor: CGFloat
    let isPrimary: Bool
    let placement: Placement
}

struct DisplayTopology: Equatable, Sendable {
    let revision: UInt64
    let displays: [DisplayDescriptor]

    var visibleFrames: [CGRect] {
        displays.map(\.visibleFrame)
    }
}

enum DisplayTopologyPolicy {
    private static let semanticReplacementMaximumCost: CGFloat = 1.25

    static func affinity(
        for display: DisplayDescriptor,
        in topology: DisplayTopology
    ) -> DisplayAffinity {
        DisplayAffinity(
            identifier: display.identifier,
            visibleSize: display.visibleFrame.size,
            backingScaleFactor: display.backingScaleFactor,
            isPrimary: display.isPrimary,
            placement: placement(for: display, in: topology)
        )
    }

    static func targetDisplay(
        for affinity: DisplayAffinity?,
        currentFrame: CGRect,
        in topology: DisplayTopology
    ) -> DisplayDescriptor? {
        guard !topology.displays.isEmpty else { return nil }

        if let identifier = affinity?.identifier,
            let exactMatch = topology.displays.first(where: { $0.identifier == identifier })
        {
            return exactMatch
        }
        if let affinity,
            let replacement = semanticReplacement(for: affinity, in: topology)
        {
            return replacement
        }

        return topology.displays.min { first, second in
            fallbackRank(for: first, currentFrame: currentFrame)
                < fallbackRank(for: second, currentFrame: currentFrame)
        }
    }

    static func semanticReplacement(
        for affinity: DisplayAffinity,
        in topology: DisplayTopology
    ) -> DisplayDescriptor? {
        let candidates = topology.displays.filter { $0.isPrimary == affinity.isPrimary }
        guard let best = candidates.min(by: { first, second in
            semanticRank(for: first, affinity: affinity, topology: topology)
                < semanticRank(for: second, affinity: affinity, topology: topology)
        }) else {
            return nil
        }
        let cost = semanticCost(for: best, affinity: affinity, topology: topology)
        return cost <= semanticReplacementMaximumCost ? best : nil
    }

    private static func placement(
        for display: DisplayDescriptor,
        in topology: DisplayTopology
    ) -> DisplayAffinity.Placement {
        guard !display.isPrimary else { return .primary }
        guard let primary = topology.displays.first(where: \.isPrimary) else {
            return display.frame.midX < 0 ? .left : .right
        }

        let horizontalDistance = display.frame.midX - primary.frame.midX
        let verticalDistance = display.frame.midY - primary.frame.midY
        if abs(horizontalDistance) >= abs(verticalDistance) {
            return horizontalDistance < 0 ? .left : .right
        }
        return verticalDistance < 0 ? .below : .above
    }

    private static func semanticCost(
        for display: DisplayDescriptor,
        affinity: DisplayAffinity,
        topology: DisplayTopology
    ) -> CGFloat {
        let placementCost: CGFloat = placement(for: display, in: topology) == affinity.placement
            ? 0
            : 0.45
        let widthCost = relativeDifference(
            display.visibleFrame.width,
            affinity.visibleSize.width
        )
        let heightCost = relativeDifference(
            display.visibleFrame.height,
            affinity.visibleSize.height
        )
        let displayAspect = display.visibleFrame.width / display.visibleFrame.height
        let affinityAspect = affinity.visibleSize.width / affinity.visibleSize.height
        let aspectCost = relativeDifference(displayAspect, affinityAspect) * 0.5
        let scaleCost = relativeDifference(
            display.backingScaleFactor,
            affinity.backingScaleFactor
        )
        return placementCost + widthCost + heightCost + aspectCost + scaleCost
    }

    private static func semanticRank(
        for display: DisplayDescriptor,
        affinity: DisplayAffinity,
        topology: DisplayTopology
    ) -> (CGFloat, UInt32, CGFloat, CGFloat) {
        (
            semanticCost(for: display, affinity: affinity, topology: topology),
            display.identifier ?? UInt32.max,
            display.frame.minX,
            display.frame.minY
        )
    }

    private static func fallbackRank(
        for display: DisplayDescriptor,
        currentFrame: CGRect
    ) -> (CGFloat, CGFloat, UInt32, CGFloat, CGFloat) {
        let intersection = currentFrame.intersection(display.visibleFrame)
        let intersectionArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let deltaX = currentFrame.midX - display.visibleFrame.midX
        let deltaY = currentFrame.midY - display.visibleFrame.midY
        return (
            -intersectionArea,
            deltaX * deltaX + deltaY * deltaY,
            display.identifier ?? UInt32.max,
            display.frame.minX,
            display.frame.minY
        )
    }

    private static func relativeDifference(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        guard first.isFinite, second.isFinite else { return .greatestFiniteMagnitude }
        let scale = max(abs(first), abs(second), 1)
        return abs(first - second) / scale
    }
}
