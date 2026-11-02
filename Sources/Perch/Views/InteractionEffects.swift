import SwiftUI

struct ChromePressButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = DesignTokens.Radius.control

    func makeBody(configuration: Configuration) -> some View {
        ChromePressButtonBody(
            configuration: configuration,
            cornerRadius: cornerRadius
        )
    }
}

private struct ChromePressButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .background {
                if InteractionPolicy.showsToolbarButtonHighlight(
                    isPressed: configuration.isPressed
                ) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            DesignTokens.Colors.action.opacity(
                                InteractionPolicy.toolbarButtonHighlightOpacity
                            )
                        )
                        .shadow(
                            color: .black.opacity(
                                InteractionPolicy.toolbarButtonShadowOpacity
                            ),
                            radius: 0,
                            x: 0,
                            y: InteractionPolicy.toolbarButtonShadowOffsetY
                        )
                }
            }
            .scaleEffect(
                InteractionPolicy.pressScale(
                    isPressed: configuration.isPressed,
                    reducesMotion: reduceMotion
                )
            )
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: InteractionPolicy.pressDuration),
                value: configuration.isPressed
            )
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(DesignTokens.Colors.action, lineWidth: 2)
                }
            }
    }
}

struct CrossfadeSymbol: View {
    let systemName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: systemName)
            .transition(iconCrossfadeTransition)
    }

    private var iconCrossfadeTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IconCrossfadeModifier(isVisible: false, reducesMotion: reduceMotion),
                identity: IconCrossfadeModifier(isVisible: true, reducesMotion: reduceMotion)
            ),
            removal: .modifier(
                active: IconCrossfadeModifier(isVisible: false, reducesMotion: reduceMotion),
                identity: IconCrossfadeModifier(isVisible: true, reducesMotion: reduceMotion)
            )
        )
    }
}

private struct IconCrossfadeModifier: ViewModifier {
    let isVisible: Bool
    let reducesMotion: Bool

    func body(content: Content) -> some View {
        let frame = InteractionPolicy.iconCrossfadeFrame(
            isVisible: isVisible,
            reducesMotion: reducesMotion
        )
        content
            .scaleEffect(frame.scale)
            .opacity(frame.opacity)
            .blur(radius: frame.blurRadius)
    }
}

struct StaggeredEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(
                InteractionPolicy.entranceOpacity(
                    hasAppeared: hasAppeared,
                    reducesMotion: reduceMotion
                )
            )
            .offset(
                y: InteractionPolicy.entranceOffset(
                    hasAppeared: hasAppeared,
                    reducesMotion: reduceMotion
                )
            )
            .onAppear {
                let delay = InteractionPolicy.entranceDelay(
                    for: index,
                    reducesMotion: reduceMotion
                )
                let animation: Animation? = reduceMotion
                    ? nil
                    : .easeOut(duration: 0.28).delay(delay)
                withAnimation(animation) {
                    hasAppeared = true
                }
            }
    }
}

private struct DisableAnimationOnColorSchemeChange: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.transaction(value: colorScheme) { transaction in
            if !InteractionPolicy.animationForColorSchemeChange() {
                transaction.animation = nil
            }
        }
    }
}

extension View {
    func chromePressStyle(cornerRadius: CGFloat = DesignTokens.Radius.control) -> some View {
        buttonStyle(ChromePressButtonStyle(cornerRadius: cornerRadius))
    }

    func staggeredEntrance(index: Int) -> some View {
        modifier(StaggeredEntrance(index: index))
    }

    func disablesAnimationOnColorSchemeChange() -> some View {
        modifier(DisableAnimationOnColorSchemeChange())
    }

    func instantListHoverColor<Value: Equatable>(value: Value) -> some View {
        animation(
            InteractionPolicy.animationForListHoverColor() ? .default : nil,
            value: value
        )
    }
}
