import SwiftUI

struct PiPStashHandleView: View {
    let side: PanelStashSide
    let onRestore: @MainActor () -> Void
    let onDragEnded: @MainActor (CGRect) -> Void
    let onDragStarted: @MainActor () -> Void
    let onHoverChanged: @MainActor (Bool) -> Void
    let onShowRecentPages: @MainActor () -> Void

    init(
        side: PanelStashSide,
        onRestore: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void = { _ in },
        onDragStarted: @escaping @MainActor () -> Void = {},
        onHoverChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onShowRecentPages: @escaping @MainActor () -> Void = {}
    ) {
        self.side = side
        self.onRestore = onRestore
        self.onDragEnded = onDragEnded
        self.onDragStarted = onDragStarted
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
                onActivate: onRestore,
                onDragEnded: onDragEnded,
                onDragStarted: onDragStarted,
                onHoverChanged: onHoverChanged,
                onShowRecentPages: onShowRecentPages
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(EdgeStashTabShape(side: side))
    }
}

private struct PiPStashHandleInteractionSurface: NSViewRepresentable {
    let onActivate: @MainActor () -> Void
    let onDragEnded: @MainActor (CGRect) -> Void
    let onDragStarted: @MainActor () -> Void
    let onHoverChanged: @MainActor (Bool) -> Void
    let onShowRecentPages: @MainActor () -> Void

    func makeNSView(context: Context) -> PiPStashHandleInteractionView {
        PiPStashHandleInteractionView(
            onActivate: onActivate,
            onDragEnded: onDragEnded,
            onDragStarted: onDragStarted,
            onHoverChanged: onHoverChanged,
            onShowRecentPages: onShowRecentPages
        )
    }

    func updateNSView(_ nsView: PiPStashHandleInteractionView, context: Context) {
        nsView.configure(
            onActivate: onActivate,
            onDragEnded: onDragEnded,
            onDragStarted: onDragStarted,
            onHoverChanged: onHoverChanged,
            onShowRecentPages: onShowRecentPages
        )
    }
}

@MainActor
final class PiPStashHandleInteractionView: NSView {
    private static let dragThreshold: CGFloat = 3

    private let pointerLocation: @MainActor () -> CGPoint
    private var onActivate: @MainActor () -> Void
    private var onDragEnded: @MainActor (CGRect) -> Void
    private var onDragStarted: @MainActor () -> Void
    private var onHoverChanged: @MainActor (Bool) -> Void
    private var onShowRecentPages: @MainActor () -> Void
    private var initialPointerLocation: CGPoint?
    private var initialWindowOrigin: CGPoint?
    private var isDragging = false
    private var hoverTrackingArea: NSTrackingArea?

    init(
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        onActivate: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void,
        onDragStarted: @escaping @MainActor () -> Void = {},
        onHoverChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onShowRecentPages: @escaping @MainActor () -> Void = {}
    ) {
        self.pointerLocation = pointerLocation
        self.onActivate = onActivate
        self.onDragEnded = onDragEnded
        self.onDragStarted = onDragStarted
        self.onHoverChanged = onHoverChanged
        self.onShowRecentPages = onShowRecentPages
        super.init(frame: .zero)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Restore Notion PiP")
        setAccessibilityHelp("Bring the stashed Notion PiP back from the side.")
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Show recent PiP pages") { [weak self] in
                self?.onShowRecentPages()
                return self != nil
            }
        ])
        toolTip = "Drag to move; click to restore Notion PiP"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        onActivate: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void,
        onDragStarted: @escaping @MainActor () -> Void = {},
        onHoverChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onShowRecentPages: @escaping @MainActor () -> Void = {}
    ) {
        self.onActivate = onActivate
        self.onDragEnded = onDragEnded
        self.onDragStarted = onDragStarted
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
        isDragging = false
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
        if !isDragging {
            guard hypot(delta.x, delta.y) >= Self.dragThreshold else { return }
            isDragging = true
            onHoverChanged(false)
            onDragStarted()
        }

        window.setFrameOrigin(
            CGPoint(
                x: initialWindowOrigin.x + delta.x,
                y: initialWindowOrigin.y + delta.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        defer { resetInteraction() }

        if isDragging, let window {
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
        isDragging = false
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
