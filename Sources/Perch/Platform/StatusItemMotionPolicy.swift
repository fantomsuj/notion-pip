import CoreGraphics
import Foundation

enum StatusItemMotionPolicy {
    static let morphDuration: TimeInterval = 0.08
    static let nodDuration: TimeInterval = 0.016
    static let nodTranslation: CGFloat = 2
    static let morphScale: CGFloat = 0.86
    static let markHoverSeparation: CGFloat = 1.5

    static func shouldAnimate(reducesMotion: Bool) -> Bool {
        !reducesMotion
    }

    static func nodOffset(reducesMotion: Bool) -> CGFloat {
        reducesMotion ? 0 : nodTranslation
    }

    static func hoverSeparation(reducesMotion: Bool) -> CGFloat {
        reducesMotion ? 0 : markHoverSeparation
    }
}
