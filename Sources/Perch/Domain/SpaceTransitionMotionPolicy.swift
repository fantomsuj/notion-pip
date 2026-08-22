import CoreGraphics
import Foundation

/// Direction of a macOS Space switch, named for the destination Space.
enum SpaceTransitionDirection: Equatable, Sendable {
    /// The destination Space is to the leading (left) side.
    case toLeading
    /// The destination Space is to the trailing (right) side.
    case toTrailing
}

enum SpaceTransitionPhase: Equatable, Sendable {
    case idle
    case hiding
    case hidden
}

struct SpaceTransitionState: Equatable, Sendable {
    var phase: SpaceTransitionPhase = .idle
    var direction: SpaceTransitionDirection?
    var spaceDidChange = false
    var hintDidTimeOut = false

    static let idle = SpaceTransitionState()
}

struct SpaceTransitionContext: Equatable, Sendable {
    var reducesMotion: Bool
    var isBusy: Bool
    var hasVisibleOverlay: Bool

    var canAnimate: Bool {
        !reducesMotion && !isBusy && hasVisibleOverlay
    }
}

enum SpaceTransitionSignal: Equatable, Sendable {
    case gestureHint(SpaceTransitionDirection)
    case activeSpaceDidChange(SpaceTransitionDirection?)
    case hideCompleted
    case hintTimedOut
    case cancelled
}

enum SpaceTransitionCommand: Equatable, Sendable {
    case hide(SpaceTransitionDirection?)
    case show(SpaceTransitionDirection?)
    case hideThenShow(SpaceTransitionDirection?)
    case cancel
}

enum SpaceTransitionAnimation: Equatable, Sendable {
    case hide(SpaceTransitionDirection?)
    case show(SpaceTransitionDirection?)
    case hideThenShow(SpaceTransitionDirection?)

    var direction: SpaceTransitionDirection? {
        switch self {
        case let .hide(direction), let .show(direction), let .hideThenShow(direction):
            return direction
        }
    }
}

/// Timing and visual frames for the PiP's Space-switch disappear/appear motion.
/// The overlay keeps `.canJoinAllSpaces`; this policy only describes how it
/// should fade and travel so it does not sit still while desktops slide.
enum SpaceTransitionMotionPolicy: Sendable {
    static let departureDuration: TimeInterval = 0.14
    static let arrivalDuration: TimeInterval = 0.22
    static let hintValidity: TimeInterval = 0.75
    static let hintTimeout: TimeInterval = 0.8
    static let travelDistance: CGFloat = 28

    static let leftArrowKeyCode: UInt16 = 123
    static let rightArrowKeyCode: UInt16 = 124

    struct VisualFrame: Equatable, Sendable {
        var opacity: CGFloat
        var translationX: CGFloat
    }

    static let restFrame = VisualFrame(opacity: 1, translationX: 0)

    static func direction(forKeyCode keyCode: UInt16) -> SpaceTransitionDirection? {
        switch keyCode {
        case leftArrowKeyCode:
            return .toLeading
        case rightArrowKeyCode:
            return .toTrailing
        default:
            return nil
        }
    }

    /// A swipe toward positive X is a swipe right, which typically reveals the
    /// leading Space. A swipe toward negative X reveals the trailing Space.
    static func direction(forSwipeDeltaX deltaX: CGFloat) -> SpaceTransitionDirection? {
        if deltaX > 0 { return .toLeading }
        if deltaX < 0 { return .toTrailing }
        return nil
    }

    static func resolvedDirection(
        hint: (direction: SpaceTransitionDirection, recordedAt: TimeInterval)?,
        now: TimeInterval,
        validity: TimeInterval = hintValidity
    ) -> SpaceTransitionDirection? {
        guard let hint, now - hint.recordedAt <= validity else { return nil }
        return hint.direction
    }

    static func departureFrame(
        direction: SpaceTransitionDirection?,
        reducesMotion: Bool = false
    ) -> VisualFrame {
        guard !reducesMotion else { return restFrame }
        return VisualFrame(opacity: 0, translationX: departureTranslation(direction))
    }

    static func arrivalStartFrame(
        direction: SpaceTransitionDirection?,
        reducesMotion: Bool = false
    ) -> VisualFrame {
        guard !reducesMotion else { return restFrame }
        return VisualFrame(opacity: 0, translationX: arrivalTranslation(direction))
    }

    static func reduce(
        state: SpaceTransitionState,
        signal: SpaceTransitionSignal,
        context: SpaceTransitionContext
    ) -> (state: SpaceTransitionState, command: SpaceTransitionCommand?) {
        if signal == .cancelled {
            return (.idle, state.phase == .idle ? nil : .cancel)
        }

        guard context.canAnimate else {
            if state.phase == .idle {
                return (state, nil)
            }
            return (.idle, .cancel)
        }

        switch (state.phase, signal) {
        case let (.idle, .gestureHint(direction)):
            return (
                SpaceTransitionState(phase: .hiding, direction: direction),
                .hide(direction)
            )

        case let (.idle, .activeSpaceDidChange(direction)):
            return (.idle, .hideThenShow(direction ?? state.direction))

        case let (.hiding, .gestureHint(direction)):
            var next = state
            next.direction = direction
            return (next, nil)

        case let (.hiding, .activeSpaceDidChange(direction)):
            var next = state
            next.spaceDidChange = true
            if let direction {
                next.direction = direction
            }
            return (next, nil)

        case (.hiding, .hintTimedOut):
            var next = state
            next.hintDidTimeOut = true
            return (next, nil)

        case (.hiding, .hideCompleted):
            if state.spaceDidChange || state.hintDidTimeOut {
                return (.idle, .show(state.direction))
            }
            return (
                SpaceTransitionState(phase: .hidden, direction: state.direction),
                nil
            )

        case let (.hidden, .gestureHint(direction)):
            var next = state
            next.direction = direction
            return (next, nil)

        case let (.hidden, .activeSpaceDidChange(direction)):
            return (.idle, .show(direction ?? state.direction))

        case (.hidden, .hintTimedOut):
            return (.idle, .show(state.direction))

        case (.hidden, .hideCompleted), (.idle, .hideCompleted), (.idle, .hintTimedOut):
            return (state, nil)

        default:
            return (state, nil)
        }
    }

    private static func departureTranslation(_ direction: SpaceTransitionDirection?) -> CGFloat {
        switch direction {
        case .toTrailing:
            return -travelDistance
        case .toLeading:
            return travelDistance
        case nil:
            return 0
        }
    }

    private static func arrivalTranslation(_ direction: SpaceTransitionDirection?) -> CGFloat {
        -departureTranslation(direction)
    }
}
