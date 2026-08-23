import CoreGraphics
import Foundation
import SwiftUI

/// Compact panel-reveal for the hover PiP toolbar.
///
/// Travel is the page-slide distance rather than the full 100 pt demo panel so
/// the 36 pt chrome still reads as an open without covering the page.
enum PiPChromeRevealMotion {
    static let appearDuration = MotionTokens.Duration.fast
    static let dismissDuration = MotionTokens.Duration.quick
    static let translateY = -MotionTokens.Distance.base
    static let blurRadius = MotionTokens.Blur.small
    static let scale = MotionTokens.Scale.small

    static func animation(isAppearing: Bool, reducesMotion: Bool) -> Animation? {
        MotionTokens.animation(
            duration: isAppearing ? appearDuration : dismissDuration,
            curve: .smoothOut,
            reducesMotion: reducesMotion
        )
    }
}

/// Toast-style motion for top-of-PiP status banners.
///
/// Banners are docked at the top, so they drop in from above rather than rise
/// from below. Timing keeps the toast open/close asymmetry.
enum StatusBannerMotion {
    static let appearDuration = MotionTokens.Duration.fast
    static let dismissDuration = MotionTokens.Duration.quick
    static let translateY = -MotionTokens.Distance.medium
    static let blurRadius = MotionTokens.Blur.small
    static let scale = MotionTokens.Scale.medium

    static func animation(isAppearing: Bool, reducesMotion: Bool) -> Animation? {
        MotionTokens.animation(
            duration: isAppearing ? appearDuration : dismissDuration,
            curve: .smoothOut,
            reducesMotion: reducesMotion
        )
    }
}

/// Menu-dropdown motion for the page-switcher popover content.
enum PageSwitcherDropdownMotion {
    static let appearDuration = MotionTokens.Duration.fast
    static let dismissDuration = MotionTokens.Duration.quick
    static let restScale = MotionTokens.Scale.medium
    static let closingScale = MotionTokens.Scale.tiny

    static func animation(isAppearing: Bool, reducesMotion: Bool) -> Animation? {
        MotionTokens.animation(
            duration: isAppearing ? appearDuration : dismissDuration,
            curve: .smoothOut,
            reducesMotion: reducesMotion
        )
    }

    static func scale(isOpen: Bool, isClosing: Bool) -> CGFloat {
        if isClosing {
            return closingScale
        }
        return isOpen ? 1 : restScale
    }
}

/// Cross-fade with blur and scale for two glyphs in one slot.
enum IconSwapMotion {
    static let duration = MotionTokens.Duration.fast
    static let inactiveBlurRadius = MotionTokens.Blur.small
    static let inactiveScale = MotionTokens.Scale.iconSwapStart

    static func animation(reducesMotion: Bool) -> Animation? {
        MotionTokens.animation(
            duration: duration,
            curve: .inOut,
            reducesMotion: reducesMotion
        )
    }

    static func opacity(isActive: Bool) -> Double {
        isActive ? 1 : 0
    }

    static func blurRadius(isActive: Bool, reducesMotion: Bool) -> CGFloat {
        guard !reducesMotion, !isActive else { return 0 }
        return inactiveBlurRadius
    }

    static func scale(isActive: Bool, reducesMotion: Bool) -> CGFloat {
        guard !reducesMotion, !isActive else { return 1 }
        return inactiveScale
    }
}

/// Icon-swap + success-check pairing for the reload control.
enum ReloadGlyph: Equatable {
    case idle
    case loading
    case success
}

enum ReloadIconSwapPolicy {
    static let duration = IconSwapMotion.duration
    static let blurRadius = IconSwapMotion.inactiveBlurRadius
    static let startScale = IconSwapMotion.inactiveScale
    static let successHoldDuration = MotionTokens.Duration.verySlow

    static func glyph(
        sessionState: NotionWebSessionState,
        successHoldExpiresAt: Date?,
        now: Date
    ) -> ReloadGlyph {
        if sessionState == .loading {
            return .loading
        }
        if let successHoldExpiresAt, now < successHoldExpiresAt {
            return .success
        }
        return .idle
    }

    static func successHoldExpiresAt(
        isPending: Bool,
        previousState: NotionWebSessionState,
        currentState: NotionWebSessionState,
        reducesMotion: Bool,
        now: Date
    ) -> Date? {
        guard ReloadCompletionMotionPolicy.shouldAnimate(
            isPending: isPending,
            previousState: previousState,
            currentState: currentState,
            reducesMotion: reducesMotion
        ) else {
            return nil
        }
        return now.addingTimeInterval(successHoldDuration)
    }
}

/// Error-state shake keyframes from transitions.dev (`A, A, B, B` legs).
enum ErrorShakeMotion {
    struct Keyframe: Equatable {
        let elapsed: TimeInterval
        let offset: CGFloat
    }

    static let distance = MotionTokens.Distance.small
    static let overshoot = MotionTokens.Distance.micro
    static let segmentA = MotionTokens.Duration.micro
    static let segmentB: TimeInterval = 0.060

    static var totalDuration: TimeInterval {
        segmentA * 2 + segmentB * 2
    }

    static var keyframes: [Keyframe] {
        [
            Keyframe(elapsed: 0, offset: 0),
            Keyframe(elapsed: segmentA, offset: distance),
            Keyframe(elapsed: segmentA * 2, offset: -distance),
            Keyframe(elapsed: segmentA * 2 + segmentB, offset: overshoot),
            Keyframe(elapsed: totalDuration, offset: 0),
        ]
    }

    static func offset(at elapsed: TimeInterval, reducesMotion: Bool) -> CGFloat {
        guard !reducesMotion else { return 0 }
        let frames = keyframes
        guard let first = frames.first, let last = frames.last else { return 0 }
        if elapsed <= first.elapsed { return first.offset }
        if elapsed >= last.elapsed { return 0 }

        for index in 1 ..< frames.count {
            let end = frames[index]
            guard elapsed <= end.elapsed else { continue }
            let start = frames[index - 1]
            let span = end.elapsed - start.elapsed
            guard span > 0 else { return end.offset }
            let progress = (elapsed - start.elapsed) / span
            return start.offset + (end.offset - start.offset) * progress
        }
        return 0
    }
}

/// Sliding-pill motion for the mutually exclusive corner controls.
enum CornerSelectionMotion {
    static let duration = MotionTokens.Duration.fast

    static func animation(reducesMotion: Bool) -> Animation? {
        MotionTokens.animation(
            duration: duration,
            curve: .smoothOut,
            reducesMotion: reducesMotion
        )
    }
}

/// Staggered texts-reveal for onboarding copy and shelf rows.
enum TextsRevealMotion {
    static let duration = MotionTokens.Duration.verySlow
    static let distance = MotionTokens.Distance.medium
    static let stagger = MotionTokens.Duration.stagger
    static let blurRadius = MotionTokens.Blur.medium
    static let fadeOutDuration = MotionTokens.Duration.fast

    static func appearDelay(forLine index: Int) -> TimeInterval {
        stagger * TimeInterval(max(index, 0))
    }

    static func appearAnimation(line index: Int, reducesMotion: Bool) -> Animation? {
        MotionTokens.animation(
            duration: duration,
            curve: .smoothOut,
            reducesMotion: reducesMotion
        )?
        .delay(appearDelay(forLine: index))
    }

    static func fadeOutAnimation(reducesMotion: Bool) -> Animation? {
        MotionTokens.animation(
            duration: fadeOutDuration,
            curve: .out,
            reducesMotion: reducesMotion
        )
    }
}

enum ToolbarHoverMotion {
    static let duration = MotionTokens.Duration.quick

    static func animation(isHovering: Bool, reducesMotion: Bool) -> Animation? {
        MotionTokens.animation(
            duration: duration,
            curve: isHovering ? .out : .bounce,
            reducesMotion: reducesMotion
        )
    }
}
