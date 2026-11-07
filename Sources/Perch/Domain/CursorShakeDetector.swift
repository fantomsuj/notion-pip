import CoreGraphics
import Foundation

/// Spots a quick back-and-forth shake of the pointer.
///
/// Each axis is tracked on its own. A reversal counts once the pointer has
/// travelled at least `minimumTravel` points back from the furthest point it
/// reached in the previous direction. Enough reversals inside `window`
/// seconds make a shake. Ordinary pointing rarely reverses more than once or
/// twice that quickly, so a shake is hard to trigger by accident.
struct CursorShakeDetector: Equatable, Sendable {
    struct Configuration: Equatable, Sendable {
        var minimumTravel: CGFloat = 36
        var requiredReversals = 4
        var window: TimeInterval = 0.8

        static let standard = Configuration()
    }

    private struct AxisTracker: Equatable, Sendable {
        var anchor: CGFloat?
        var extreme: CGFloat = 0
        var direction: CGFloat = 0
        var reversals: [TimeInterval] = []

        mutating func record(
            _ value: CGFloat,
            at time: TimeInterval,
            configuration: Configuration
        ) -> Bool {
            reversals.removeAll { time - $0 > configuration.window }
            guard let anchor else {
                self.anchor = value
                extreme = value
                return false
            }

            if direction == 0 {
                let travel = value - anchor
                if abs(travel) >= configuration.minimumTravel {
                    direction = travel > 0 ? 1 : -1
                    extreme = value
                }
                return false
            }

            if (value - extreme) * direction > 0 {
                extreme = value
                return false
            }

            guard (extreme - value) * direction >= configuration.minimumTravel else {
                return false
            }
            reversals.append(time)
            direction = -direction
            extreme = value
            return reversals.count >= configuration.requiredReversals
        }
    }

    let configuration: Configuration
    private var horizontal = AxisTracker()
    private var vertical = AxisTracker()

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    /// Records one pointer position. Returns true once when a shake completes,
    /// then starts over so one shake reports once.
    mutating func record(_ point: CGPoint, at time: TimeInterval) -> Bool {
        let shookHorizontally = horizontal.record(point.x, at: time, configuration: configuration)
        let shookVertically = vertical.record(point.y, at: time, configuration: configuration)
        guard shookHorizontally || shookVertically else { return false }
        reset()
        return true
    }

    mutating func reset() {
        horizontal = AxisTracker()
        vertical = AxisTracker()
    }
}
