import AppKit
import CoreGraphics

enum TopEdgeTrackpadMovePhase: Equatable, Sendable {
    case none
    case began
    case changed
    case stationary
    case ended
    case cancelled
}

extension TopEdgeTrackpadMovePhase {
    init(appKitPhase phase: NSEvent.Phase) {
        if phase.contains(.began) {
            self = .began
        } else if phase.contains(.changed) {
            self = .changed
        } else if phase.contains(.stationary) {
            self = .stationary
        } else if phase.contains(.ended) {
            self = .ended
        } else if phase.contains(.cancelled) {
            self = .cancelled
        } else {
            self = .none
        }
    }
}

struct TopEdgeTrackpadMoveInput: Equatable, Sendable {
    let phase: TopEdgeTrackpadMovePhase
    let momentumPhase: TopEdgeTrackpadMovePhase
    let hasPreciseScrollingDeltas: Bool
    let locationInContent: CGPoint
    let contentBounds: CGRect
    let isContentFlipped: Bool
    let isExpanded: Bool
    let visibleFrame: CGRect?
    let translation: CGSize
}

enum TopEdgeTrackpadMoveDecision: Equatable, Sendable {
    case forward
    case consume
    case move(translation: CGSize, visibleFrame: CGRect)
}

@MainActor
final class TopEdgeTrackpadMoveController {
    static let activeHeight: CGFloat = 36

    private var activeVisibleFrame: CGRect?
    private var suppressesMomentum = false

    var isActive: Bool {
        activeVisibleFrame != nil
    }

    func reset() {
        activeVisibleFrame = nil
        suppressesMomentum = false
    }

    func handle(_ input: TopEdgeTrackpadMoveInput) -> TopEdgeTrackpadMoveDecision {
        if input.momentumPhase != .none {
            let shouldConsume = suppressesMomentum || activeVisibleFrame != nil
            activeVisibleFrame = nil
            switch input.momentumPhase {
            case .ended, .cancelled:
                suppressesMomentum = false
            case .began, .changed, .stationary:
                suppressesMomentum = shouldConsume
            case .none:
                break
            }
            return shouldConsume ? .consume : .forward
        }

        switch input.phase {
        case .began:
            suppressesMomentum = false
            guard input.hasPreciseScrollingDeltas,
                !input.isExpanded,
                input.contentBounds.contains(input.locationInContent),
                isInsideActiveRegion(input),
                let visibleFrame = input.visibleFrame
            else {
                activeVisibleFrame = nil
                return .forward
            }
            activeVisibleFrame = visibleFrame
            return decision(for: input.translation, visibleFrame: visibleFrame)

        case .changed:
            guard !input.isExpanded, let activeVisibleFrame else {
                self.activeVisibleFrame = nil
                return .forward
            }
            return decision(for: input.translation, visibleFrame: activeVisibleFrame)

        case .stationary:
            return activeVisibleFrame == nil ? .forward : .consume

        case .ended, .cancelled:
            guard activeVisibleFrame != nil else { return .forward }
            activeVisibleFrame = nil
            suppressesMomentum = true
            return .consume

        case .none:
            return .forward
        }
    }

    private func decision(
        for translation: CGSize,
        visibleFrame: CGRect
    ) -> TopEdgeTrackpadMoveDecision {
        guard translation != .zero else { return .consume }
        return .move(translation: translation, visibleFrame: visibleFrame)
    }

    private func isInsideActiveRegion(_ input: TopEdgeTrackpadMoveInput) -> Bool {
        if input.isContentFlipped {
            return input.locationInContent.y
                < input.contentBounds.minY + Self.activeHeight
        }
        return input.locationInContent.y
            > input.contentBounds.maxY - Self.activeHeight
    }
}
