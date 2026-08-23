import QuartzCore
import SwiftUI

/// Shared motion scale ported from [transitions.dev](https://transitions.dev).
///
/// Durations, easings, distances, scales, and blur radii match the documented
/// token values so PiP chrome, banners, and icon swaps stay on one clock.
/// CSS snippets are not used; AppKit and SwiftUI consume these values directly.
enum MotionTokens {
    enum Duration {
        /// Per-item stagger offset.
        static let stagger: TimeInterval = 0.040
        /// Tooltip/path delay, shake segment, large stagger.
        static let micro: TimeInterval = 0.080
        /// Modal/dropdown close, text swap, tooltip appear.
        static let quick: TimeInterval = 0.150
        /// Icon swap, dropdown/modal open, tabs sliding, page slide.
        static let fast: TimeInterval = 0.250
        /// Panel close, toast close.
        static let medium: TimeInterval = 0.350
        /// Panel open, skeleton content reveal, input clear.
        static let slow: TimeInterval = 0.400
        /// Emphasis moments, badge appear, text reveal, success check.
        static let verySlow: TimeInterval = 0.500
    }

    enum Distance {
        /// Text swap.
        static let micro: CGFloat = 4
        /// Error shake peak.
        static let small: CGFloat = 6
        /// Badge diagonal reveal, page slide, compact panel travel.
        static let base: CGFloat = 8
        /// Text reveal, toast travel.
        static let medium: CGFloat = 12
        /// Success-check badge appear.
        static let large: CGFloat = 30
    }

    enum Scale {
        /// Modal open / close.
        static let large: CGFloat = 0.96
        /// Dropdown open, toast rest scale.
        static let medium: CGFloat = 0.97
        /// Tooltip open.
        static let small: CGFloat = 0.98
        /// Dropdown close.
        static let tiny: CGFloat = 0.99
        /// Icon-swap incoming glyph.
        static let iconSwapStart: CGFloat = 0.25
    }

    enum Blur {
        /// Panel reveal, icon swap, text swap, skeleton, number pop-in.
        static let small: CGFloat = 2
        /// Page slide, text reveal.
        static let medium: CGFloat = 3
        /// Success check open.
        static let large: CGFloat = 8
    }

    enum Curve: Equatable {
        /// Modal/dropdown/panel open + close, page slide, resize, position change.
        case smoothOut
        /// Icon swap, text swap, text reveal, skeleton reveal.
        case inOut
        /// Tooltip open / close.
        case out
        /// Shimmer, skeleton pulse, spinner.
        case linear
        /// Badge pop open, hover-out return.
        case bounce
        /// Avatar-group hover-out (strong overshoot).
        case bounceStrong
    }

    /// `cubic-bezier(0.22, 1, 0.36, 1)`
    static let smoothOutControlPoints = (x1: 0.22, y1: 1.0, x2: 0.36, y2: 1.0)
    /// `cubic-bezier(0.34, 1.36, 0.64, 1)`
    static let bounceControlPoints = (x1: 0.34, y1: 1.36, x2: 0.64, y2: 1.0)
    /// `cubic-bezier(0.34, 3.85, 0.64, 1)`
    static let bounceStrongControlPoints = (x1: 0.34, y1: 3.85, x2: 0.64, y2: 1.0)

    static func animation(
        duration: TimeInterval,
        curve: Curve,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }
        switch curve {
        case .smoothOut:
            let points = smoothOutControlPoints
            return .timingCurve(points.x1, points.y1, points.x2, points.y2, duration: duration)
        case .inOut:
            return .easeInOut(duration: duration)
        case .out:
            return .easeOut(duration: duration)
        case .linear:
            return .linear(duration: duration)
        case .bounce:
            let points = bounceControlPoints
            return .timingCurve(points.x1, points.y1, points.x2, points.y2, duration: duration)
        case .bounceStrong:
            let points = bounceStrongControlPoints
            return .timingCurve(points.x1, points.y1, points.x2, points.y2, duration: duration)
        }
    }

    static func smoothOutTimingFunction() -> CAMediaTimingFunction {
        CAMediaTimingFunction(
            controlPoints: Float(smoothOutControlPoints.x1),
            Float(smoothOutControlPoints.y1),
            Float(smoothOutControlPoints.x2),
            Float(smoothOutControlPoints.y2)
        )
    }
}
