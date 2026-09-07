import CoreGraphics
import Foundation

enum FlipGeometry: Sendable {
    static let fullScreenTolerance: CGFloat = 2
    static let minimumOccupiableSize = CGSize(width: 320, height: 240)
    static let frameMatchTolerance: CGFloat = 2
    static let offscreenOrigin = CGPoint(x: -10_000, y: -10_000)

    /// Quartz / Accessibility coordinates use a top-left origin on the primary
    /// display. AppKit windows use a bottom-left origin.
    static func cocoaFrame(
        fromQuartzBounds quartz: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: quartz.origin.x,
            y: primaryScreenHeight - quartz.origin.y - quartz.height,
            width: quartz.width,
            height: quartz.height
        )
    }

    static func quartzBounds(
        fromCocoaFrame cocoa: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: cocoa.origin.x,
            y: primaryScreenHeight - cocoa.origin.y - cocoa.height,
            width: cocoa.width,
            height: cocoa.height
        )
    }

    static func isEffectivelyFullScreen(
        _ frame: CGRect,
        screenFrame: CGRect,
        tolerance: CGFloat = fullScreenTolerance
    ) -> Bool {
        abs(frame.minX - screenFrame.minX) <= tolerance
            && abs(frame.minY - screenFrame.minY) <= tolerance
            && abs(frame.width - screenFrame.width) <= tolerance
            && abs(frame.height - screenFrame.height) <= tolerance
    }

    static func framesMatch(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat = frameMatchTolerance
    ) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    static func isLargeEnoughToOccupy(_ frame: CGRect) -> Bool {
        frame.width >= minimumOccupiableSize.width
            && frame.height >= minimumOccupiableSize.height
    }
}
