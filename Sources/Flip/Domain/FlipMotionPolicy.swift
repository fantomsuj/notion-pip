import CoreGraphics
import Foundation

enum FlipMotionPolicy: Sendable {
    static let duration: TimeInterval = 0.45
    static let reducedMotionDuration: TimeInterval = 0.12
    static let perspective: CGFloat = 1.0 / 800.0

    static func duration(reducesMotion: Bool) -> TimeInterval {
        reducesMotion ? reducedMotionDuration : duration
    }

    static func shouldUseCardFlip(reducesMotion: Bool) -> Bool {
        !reducesMotion
    }
}

enum FlipParkPolicy: Sendable {
    static var preferredStrategies: [FlipParkStrategy] {
        [.hide, .minimize, .moveOffscreen]
    }
}
