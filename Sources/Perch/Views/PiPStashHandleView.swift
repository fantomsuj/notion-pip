import SwiftUI

struct PiPStashHandleView: View {
    let side: PanelStashSide
    let pullRevealTravel: CGFloat
    let onRestore: @MainActor () -> Void
    let onDragEnded: @MainActor (CGRect) -> Void
    let onDragStarted: @MainActor () -> Void
    let onPullRevealChanged: @MainActor (CGFloat) -> Void
    let onPullRevealEnded: @MainActor (CGFloat) -> Bool
    let onHoverChanged: @MainActor (Bool) -> Void
    let onShowRecentPages: @MainActor () -> Void

    init(
        side: PanelStashSide,
        pullRevealTravel: CGFloat = 150,
        onRestore: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void = { _ in },
        onDragStarted: @escaping @MainActor () -> Void = {},
        onPullRevealChanged: @escaping @MainActor (CGFloat) -> Void = { _ in },
        onPullRevealEnded: @escaping @MainActor (CGFloat) -> Bool = { _ in false },
        onHoverChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onShowRecentPages: @escaping @MainActor () -> Void = {}
    ) {
        self.side = side
        self.pullRevealTravel = max(pullRevealTravel, 1)
        self.onRestore = onRestore
        self.onDragEnded = onDragEnded
        self.onDragStarted = onDragStarted
        self.onPullRevealChanged = onPullRevealChanged
        self.onPullRevealEnded = onPullRevealEnded
        self.onHoverChanged = onHoverChanged
        self.onShowRecentPages = onShowRecentPages
    }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 13, weight: .medium))

                Image(systemName: side == .left ? "chevron.right" : "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: EdgeStashTabShape(side: side))
            .contentShape(EdgeStashTabShape(side: side))
            .accessibilityHidden(true)

            PiPStashHandleInteractionSurface(
                side: side,
                pullRevealTravel: pullRevealTravel,
                onActivate: onRestore,
                onDragEnded: onDragEnded,
                onDragStarted: onDragStarted,
                onPullRevealChanged: onPullRevealChanged,
                onPullRevealEnded: onPullRevealEnded,
                onHoverChanged: onHoverChanged,
                onShowRecentPages: onShowRecentPages
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(EdgeStashTabShape(side: side))
    }
}

private struct PiPStashHandleInteractionSurface: NSViewRepresentable {
    let side: PanelStashSide
    let pullRevealTravel: CGFloat
    let onActivate: @MainActor () -> Void
    let onDragEnded: @MainActor (CGRect) -> Void
    let onDragStarted: @MainActor () -> Void
    let onPullRevealChanged: @MainActor (CGFloat) -> Void
    let onPullRevealEnded: @MainActor (CGFloat) -> Bool
    let onHoverChanged: @MainActor (Bool) -> Void
    let onShowRecentPages: @MainActor () -> Void

    func makeNSView(context: Context) -> PiPStashHandleInteractionView {
        PiPStashHandleInteractionView(
            side: side,
            pullRevealTravel: pullRevealTravel,
            onActivate: onActivate,
            onDragEnded: onDragEnded,
            onDragStarted: onDragStarted,
            onPullRevealChanged: onPullRevealChanged,
            onPullRevealEnded: onPullRevealEnded,
            onHoverChanged: onHoverChanged,
            onShowRecentPages: onShowRecentPages
        )
    }

    func updateNSView(_ nsView: PiPStashHandleInteractionView, context: Context) {
        nsView.configure(
            side: side,
            pullRevealTravel: pullRevealTravel,
            onActivate: onActivate,
            onDragEnded: onDragEnded,
            onDragStarted: onDragStarted,
            onPullRevealChanged: onPullRevealChanged,
            onPullRevealEnded: onPullRevealEnded,
            onHoverChanged: onHoverChanged,
            onShowRecentPages: onShowRecentPages
        )
    }
}

@MainActor
final class PiPStashHandleInteractionView: NSView {
    private static let dragThreshold: CGFloat = 3

    private let pointerLocation: @MainActor () -> CGPoint
    private let reducesMotion: @MainActor () -> Bool
    private let performThresholdFeedback: @MainActor () -> Void
    private var side: PanelStashSide
    private var pullRevealTravel: CGFloat
    private var onActivate: @MainActor () -> Void
    private var onDragEnded: @MainActor (CGRect) -> Void
    private var onDragStarted: @MainActor () -> Void
    private var onPullRevealChanged: @MainActor (CGFloat) -> Void
    private var onPullRevealEnded: @MainActor (CGFloat) -> Bool
    private var onHoverChanged: @MainActor (Bool) -> Void
    private var onShowRecentPages: @MainActor () -> Void
    private var initialPointerLocation: CGPoint?
    private var initialWindowOrigin: CGPoint?
    private var dragMode: DragMode?
    private var latestInwardDistance: CGFloat = 0
    private var previousRawProgress: CGFloat = 0
    private var didPerformThresholdFeedback = false
    private var hoverTrackingArea: NSTrackingArea?

    private enum DragMode {
        case reposition
        case pullReveal
    }

    init(
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        side: PanelStashSide = .right,
        pullRevealTravel: CGFloat = 150,
        reducesMotion: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        performThresholdFeedback: @escaping @MainActor () -> Void = {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .now
            )
        },
        onActivate: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void,
        onDragStarted: @escaping @MainActor () -> Void = {},
        onPullRevealChanged: @escaping @MainActor (CGFloat) -> Void = { _ in },
        onPullRevealEnded: @escaping @MainActor (CGFloat) -> Bool = { _ in false },
        onHoverChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onShowRecentPages: @escaping @MainActor () -> Void = {}
    ) {
        self.pointerLocation = pointerLocation
        self.reducesMotion = reducesMotion
        self.performThresholdFeedback = performThresholdFeedback
        self.side = side
        self.pullRevealTravel = max(pullRevealTravel, 1)
        self.onActivate = onActivate
        self.onDragEnded = onDragEnded
        self.onDragStarted = onDragStarted
        self.onPullRevealChanged = onPullRevealChanged
        self.onPullRevealEnded = onPullRevealEnded
        self.onHoverChanged = onHoverChanged
        self.onShowRecentPages = onShowRecentPages
        super.init(frame: .zero)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Restore Perch")
        setAccessibilityHelp("Bring the stashed Perch back from the side.")
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Show recent PiP pages") { [weak self] in
                self?.onShowRecentPages()
                return self != nil
            }
        ])
        toolTip = "Pull inward to reveal; drag along the edge to move"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        side: PanelStashSide,
        pullRevealTravel: CGFloat,
        onActivate: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void,
        onDragStarted: @escaping @MainActor () -> Void = {},
        onPullRevealChanged: @escaping @MainActor (CGFloat) -> Void = { _ in },
        onPullRevealEnded: @escaping @MainActor (CGFloat) -> Bool = { _ in false },
        onHoverChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onShowRecentPages: @escaping @MainActor () -> Void = {}
    ) {
        self.side = side
        self.pullRevealTravel = max(pullRevealTravel, 1)
        self.onActivate = onActivate
        self.onDragEnded = onDragEnded
        self.onDragStarted = onDragStarted
        self.onPullRevealChanged = onPullRevealChanged
        self.onPullRevealEnded = onPullRevealEnded
        self.onHoverChanged = onHoverChanged
        self.onShowRecentPages = onShowRecentPages
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        initialPointerLocation = pointerLocation()
        initialWindowOrigin = window?.frame.origin
        dragMode = nil
        latestInwardDistance = 0
        previousRawProgress = 0
        didPerformThresholdFeedback = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialPointerLocation,
              let initialWindowOrigin,
              let window
        else {
            return
        }

        let currentPointerLocation = pointerLocation()
        let delta = CGPoint(
            x: currentPointerLocation.x - initialPointerLocation.x,
            y: currentPointerLocation.y - initialPointerLocation.y
        )
        if dragMode == nil {
            guard hypot(delta.x, delta.y) >= Self.dragThreshold else { return }
            let inwardDistance = PanelPullRevealPolicy.inwardDistance(
                forHorizontalDelta: delta.x,
                side: side
            )
            dragMode = inwardDistance > 0 && abs(delta.x) >= abs(delta.y)
                ? .pullReveal
                : .reposition
            onHoverChanged(false)
            onDragStarted()
        }

        switch dragMode {
        case .reposition:
            window.setFrameOrigin(
                CGPoint(
                    x: initialWindowOrigin.x + delta.x,
                    y: initialWindowOrigin.y + delta.y
                )
            )
        case .pullReveal:
            let inwardDistance = PanelPullRevealPolicy.inwardDistance(
                forHorizontalDelta: delta.x,
                side: side
            )
            latestInwardDistance = inwardDistance
            let rawProgress = min(max(inwardDistance / pullRevealTravel, 0), 1)
            if !didPerformThresholdFeedback,
                PanelPullRevealPolicy.crossedRestoreThreshold(
                    from: previousRawProgress,
                    to: rawProgress
                )
            {
                didPerformThresholdFeedback = true
                performThresholdFeedback()
            }
            previousRawProgress = rawProgress
            let displayedProgress = PanelPullRevealPolicy.interactiveProgress(
                forRawProgress: rawProgress,
                reducesMotion: reducesMotion()
            )
            let displayedInwardDistance = displayedProgress * pullRevealTravel
            window.setFrameOrigin(
                CGPoint(
                    x: initialWindowOrigin.x
                        + (side == .left ? displayedInwardDistance : -displayedInwardDistance),
                    y: initialWindowOrigin.y
                )
            )
            onPullRevealChanged(inwardDistance)
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { resetInteraction() }

        if dragMode == .pullReveal {
            _ = onPullRevealEnded(latestInwardDistance)
        } else if dragMode == .reposition, let window {
            onDragEnded(window.frame)
        } else {
            onActivate()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged(false)
    }

    override func rightMouseUp(with event: NSEvent) {
        onShowRecentPages()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate()
        return true
    }

    private func resetInteraction() {
        initialPointerLocation = nil
        initialWindowOrigin = nil
        dragMode = nil
        latestInwardDistance = 0
        previousRawProgress = 0
        didPerformThresholdFeedback = false
    }
}

private struct EdgeStashTabShape: Shape {
    let side: PanelStashSide
    private let radius: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch side {
        case .left:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        }

        path.closeSubpath()
        return path
    }
}
