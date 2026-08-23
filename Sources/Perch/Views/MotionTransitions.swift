import SwiftUI

struct CrossBlurReveal: Transition {
    var translateY: CGFloat
    var blurRadius: CGFloat
    var scale: CGFloat

    init(
        translateY: CGFloat,
        blurRadius: CGFloat,
        scale: CGFloat
    ) {
        self.translateY = translateY
        self.blurRadius = blurRadius
        self.scale = scale
    }

    static var pipChrome: Self {
        Self(
            translateY: PiPChromeRevealMotion.translateY,
            blurRadius: PiPChromeRevealMotion.blurRadius,
            scale: PiPChromeRevealMotion.scale
        )
    }

    static var statusBanner: Self {
        Self(
            translateY: StatusBannerMotion.translateY,
            blurRadius: StatusBannerMotion.blurRadius,
            scale: StatusBannerMotion.scale
        )
    }

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .offset(y: phase.isIdentity ? 0 : translateY)
            .scaleEffect(phase.isIdentity ? 1 : scale)
            .blur(radius: phase.isIdentity ? 0 : blurRadius)
    }
}

struct ErrorShakeModifier: ViewModifier {
    var trigger: Int
    var reducesMotion: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(
            initialValue: CGFloat(0),
            trigger: reducesMotion ? 0 : trigger
        ) { view, offset in
            view.offset(x: reducesMotion ? 0 : offset)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(
                    ErrorShakeMotion.distance,
                    duration: ErrorShakeMotion.segmentA
                )
                LinearKeyframe(
                    -ErrorShakeMotion.distance,
                    duration: ErrorShakeMotion.segmentA
                )
                LinearKeyframe(
                    ErrorShakeMotion.overshoot,
                    duration: ErrorShakeMotion.segmentB
                )
                LinearKeyframe(0, duration: ErrorShakeMotion.segmentB)
            }
        }
    }
}

extension View {
    func errorShake(trigger: Int, reducesMotion: Bool) -> some View {
        modifier(ErrorShakeModifier(trigger: trigger, reducesMotion: reducesMotion))
    }

    func iconSwapActive(_ isActive: Bool, reducesMotion: Bool) -> some View {
        opacity(IconSwapMotion.opacity(isActive: isActive))
            .blur(
                radius: IconSwapMotion.blurRadius(
                    isActive: isActive,
                    reducesMotion: reducesMotion
                )
            )
            .scaleEffect(
                IconSwapMotion.scale(
                    isActive: isActive,
                    reducesMotion: reducesMotion
                )
            )
            .allowsHitTesting(isActive)
            .accessibilityHidden(true)
    }
}
