import SwiftUI

enum ToolbarIconMotionStyle: Equatable {
    case pageStack
    case corner(PanelCorner)
    case stash
    case external
    case reload
}

struct ToolbarIconTransform: Equatable {
    static let identity = ToolbarIconTransform(offset: .zero, scale: 1)

    let offset: CGSize
    let scale: CGFloat
}

enum ToolbarIconMotionPolicy {
    static let hoverDuration: TimeInterval = 0.12
    static let reloadDuration: TimeInterval = 0.14

    static func transform(
        for style: ToolbarIconMotionStyle,
        isHovering: Bool,
        reducesMotion: Bool
    ) -> ToolbarIconTransform {
        guard isHovering, !reducesMotion else { return .identity }

        switch style {
        case .pageStack, .reload:
            return .identity
        case let .corner(corner):
            let distance: CGFloat = 1.25
            let offset = switch corner {
            case .topLeft:
                CGSize(width: -distance, height: -distance)
            case .topRight:
                CGSize(width: distance, height: -distance)
            case .bottomLeft:
                CGSize(width: -distance, height: distance)
            case .bottomRight:
                CGSize(width: distance, height: distance)
            }
            return ToolbarIconTransform(offset: offset, scale: 1)
        case .stash:
            return ToolbarIconTransform(offset: .zero, scale: 0.82)
        case .external:
            return ToolbarIconTransform(
                offset: CGSize(width: 1.25, height: -1.25),
                scale: 1.02
            )
        }
    }

    static func pageStackSeparation(
        isHovering: Bool,
        reducesMotion: Bool
    ) -> CGFloat {
        isHovering && !reducesMotion ? 1.5 : 0
    }
}

@MainActor
enum ReloadCompletionMotionPolicy {
    static func shouldAnimate(
        isPending: Bool,
        previousState: NotionWebSessionState,
        currentState: NotionWebSessionState,
        reducesMotion: Bool
    ) -> Bool {
        isPending
            && previousState == .loading
            && currentState == .active
            && !reducesMotion
    }

    static func shouldFinishPendingReload(currentState: NotionWebSessionState) -> Bool {
        currentState != .loading
    }
}

struct ToolbarMotionIcon: View {
    let style: ToolbarIconMotionStyle
    var systemImage: String?
    var rotationDegrees: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let transform = ToolbarIconMotionPolicy.transform(
            for: style,
            isHovering: isHovering,
            reducesMotion: reduceMotion
        )

        glyph
            .offset(transform.offset)
            .scaleEffect(transform.scale)
            .rotationEffect(.degrees(style == .reload ? rotationDegrees : 0))
            .frame(
                width: PanelCornerControls.minimumHitTarget,
                height: PanelCornerControls.minimumHitTarget
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(
                reduceMotion ? nil : .easeOut(duration: ToolbarIconMotionPolicy.hoverDuration),
                value: isHovering
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: ToolbarIconMotionPolicy.reloadDuration),
                value: rotationDegrees
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        if style == .pageStack {
            pageStackGlyph
        } else if let systemImage {
            Image(systemName: systemImage)
        }
    }

    private var pageStackGlyph: some View {
        let separation = ToolbarIconMotionPolicy.pageStackSeparation(
            isHovering: isHovering,
            reducesMotion: reduceMotion
        )

        return ZStack {
            Image(systemName: "rectangle")
                .offset(
                    x: -0.75 - separation / 2,
                    y: -0.75 - separation / 2
                )
            Image(systemName: "rectangle")
                .offset(
                    x: 0.75 + separation / 2,
                    y: 0.75 + separation / 2
                )
        }
        .font(.system(size: 11, weight: .regular))
    }
}
