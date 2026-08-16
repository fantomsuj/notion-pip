import CoreGraphics
import Foundation

/// Interaction rules adapted from the interfaces.dev cheat sheet for Perch's
/// native chrome. Values stay in the policy so views and tests share one
/// contract for press feedback, hit targets, motion, and spacing.
enum InteractionPolicy: Sendable {
    /// Pressed controls scale to a value between 0.95 and 0.98.
    static let pressedScale: CGFloat = 0.96
    /// Interruptible press timing; name the changing property at the call site.
    static let pressDuration: TimeInterval = 0.2
    static let iconCrossfadeDuration: TimeInterval = 0.2
    static let enteringIconScale: CGFloat = 0.25
    static let enteringIconBlur: CGFloat = 4
    /// Stagger staged entrances by around 100ms.
    static let staggerInterval: TimeInterval = 0.1
    static let hiddenEntranceOffset: CGFloat = 8

    static let minimumHitTarget: CGFloat = 24
    /// Compact overlay chrome stays above the 24pt floor without crowding Notion.
    static let compactHitTarget: CGFloat = 28
    static let preferredHitTarget: CGFloat = 40

    struct IconCrossfadeFrame: Equatable, Sendable {
        var scale: CGFloat
        var opacity: Double
        var blurRadius: CGFloat
    }

    static let iconCrossfadeIdentity = IconCrossfadeFrame(
        scale: 1,
        opacity: 1,
        blurRadius: 0
    )

    static func pressScale(isPressed: Bool, reducesMotion: Bool) -> CGFloat {
        guard isPressed, !reducesMotion else { return 1 }
        return pressedScale
    }

    static func concentricRadius(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, outer - inset)
    }

    /// The gap between groups is at least twice the gap inside one.
    static func groupSpacing(innerSpacing: CGFloat) -> CGFloat {
        innerSpacing * 2
    }

    static func iconCrossfadeFrame(
        isVisible: Bool,
        reducesMotion: Bool
    ) -> IconCrossfadeFrame {
        if isVisible {
            return iconCrossfadeIdentity
        }
        if reducesMotion {
            return IconCrossfadeFrame(scale: 1, opacity: 0, blurRadius: 0)
        }
        return IconCrossfadeFrame(
            scale: enteringIconScale,
            opacity: 0,
            blurRadius: enteringIconBlur
        )
    }

    static func entranceDelay(for index: Int, reducesMotion: Bool) -> TimeInterval {
        guard !reducesMotion, index > 0 else { return 0 }
        return TimeInterval(index) * staggerInterval
    }

    static func entranceOffset(hasAppeared: Bool, reducesMotion: Bool) -> CGFloat {
        hasAppeared || reducesMotion ? 0 : hiddenEntranceOffset
    }

    static func entranceOpacity(hasAppeared: Bool, reducesMotion: Bool) -> Double {
        hasAppeared || reducesMotion ? 1 : 0
    }

    static func animationForColorSchemeChange() -> Bool {
        false
    }

    static func animationForListHoverColor() -> Bool {
        false
    }
}
