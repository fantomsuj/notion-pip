import SwiftUI

struct PiPStashHandleView: View {
    let side: PanelStashSide
    let onRestore: @MainActor () -> Void
    let onDragEnded: @MainActor (CGRect) -> Void

    init(
        side: PanelStashSide,
        onRestore: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void = { _ in }
    ) {
        self.side = side
        self.onRestore = onRestore
        self.onDragEnded = onDragEnded
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
                onDragEnded: onDragEnded
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(EdgeStashTabShape(side: side))
    }
}

private struct PiPStashHandleInteractionSurface: NSViewRepresentable {
    let onActivate: @MainActor () -> Void
    let onDragEnded: @MainActor (CGRect) -> Void

    func makeNSView(context: Context) -> PiPStashHandleInteractionView {
        PiPStashHandleInteractionView(
            onActivate: onActivate,
            onDragEnded: onDragEnded
        )
    }

    func updateNSView(_ nsView: PiPStashHandleInteractionView, context: Context) {
        nsView.configure(
            onActivate: onActivate,
            onDragEnded: onDragEnded
        )
    }
}

@MainActor
final class PiPStashHandleInteractionView: NSView {
    private static let dragThreshold: CGFloat = 3

    private let pointerLocation: @MainActor () -> CGPoint
    private var onActivate: @MainActor () -> Void
    private var onDragEnded: @MainActor (CGRect) -> Void
    private var initialPointerLocation: CGPoint?
    private var initialWindowOrigin: CGPoint?
    private var isDragging = false

    init(
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        onActivate: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void
    ) {
        self.pointerLocation = pointerLocation
        self.onActivate = onActivate
        self.onDragEnded = onDragEnded
        super.init(frame: .zero)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Restore Perch")
        setAccessibilityHelp("Bring the stashed Perch back from the side.")
        toolTip = "Drag to move; click to restore Perch"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        onActivate: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void
    ) {
        self.onActivate = onActivate
        self.onDragEnded = onDragEnded
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
