import SwiftUI

struct CrossBlurRevealModifier: ViewModifier, Animatable {
    var progress: CGFloat
    var translateY: CGFloat
    var blurRadius: CGFloat
    var scale: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: (1 - progress) * translateY)
            .scaleEffect(1 - (1 - progress) * (1 - scale))
            .blur(radius: (1 - progress) * blurRadius)
    }
}

extension AnyTransition {
    static func crossBlurReveal(
        translateY: CGFloat,
        blurRadius: CGFloat,
        scale: CGFloat
    ) -> AnyTransition {
        .modifier(
            active: CrossBlurRevealModifier(
                progress: 0,
                translateY: translateY,
                blurRadius: blurRadius,
                scale: scale
            ),
            identity: CrossBlurRevealModifier(
                progress: 1,
                translateY: translateY,
                blurRadius: blurRadius,
                scale: scale
            )
        )
    }

    static var pipChromeReveal: AnyTransition {
        .crossBlurReveal(
            translateY: PiPChromeRevealMotion.translateY,
            blurRadius: PiPChromeRevealMotion.blurRadius,
            scale: PiPChromeRevealMotion.scale
        )
    }

    static var statusBannerReveal: AnyTransition {
        .crossBlurReveal(
            translateY: StatusBannerMotion.translateY,
            blurRadius: StatusBannerMotion.blurRadius,
            scale: StatusBannerMotion.scale
        )
    }

    static var textsRevealInsertion: AnyTransition {
        .modifier(
            active: CrossBlurRevealModifier(
                progress: 0,
                translateY: TextsRevealMotion.distance,
                blurRadius: TextsRevealMotion.blurRadius,
                scale: 1
            ),
            identity: CrossBlurRevealModifier(
                progress: 1,
                translateY: TextsRevealMotion.distance,
                blurRadius: TextsRevealMotion.blurRadius,
                scale: 1
            )
        )
    }

    static var textsReveal: AnyTransition {
        .asymmetric(
            insertion: .textsRevealInsertion,
            removal: .opacity
        )
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

struct TextsRevealCopy: View {
    let heading: String
    let detail: String
    var headingFont: Font = .system(size: 28, weight: .semibold)
    var detailFont: Font = .body
    var detailColor: Color = DesignTokens.Colors.secondaryText

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
            line(heading, index: 0)
                .font(headingFont)
            line(detail, index: 1)
                .font(detailFont)
                .foregroundStyle(detailColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: heading + "\n" + detail) {
            isShown = reduceMotion
            if !reduceMotion {
                await Task.yield()
            }
            isShown = true
        }
    }

    private func line(_ text: String, index: Int) -> some View {
        Text(text)
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : TextsRevealMotion.distance)
            .blur(radius: isShown ? 0 : TextsRevealMotion.blurRadius)
            .animation(
                isShown
                    ? TextsRevealMotion.appearAnimation(line: index, reducesMotion: reduceMotion)
                    : TextsRevealMotion.fadeOutAnimation(reducesMotion: reduceMotion),
                value: isShown
            )
    }
}
