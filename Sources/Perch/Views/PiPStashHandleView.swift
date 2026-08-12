import SwiftUI

struct PiPStashHandleDragSnapshot {
    let sequenceNumber: Int
    let candidate: NotionPageDrop?
    let sourceOperationMask: NSDragOperation
}

@MainActor
final class PiPStashHandleDropTargetModel: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var label: String?

    func show(label: String) {
        self.label = label
        isActive = true
    }

    func clear() {
        isActive = false
        label = nil
    }
}

struct PiPStashHandleView: View {
    let side: PanelStashSide
    @ObservedObject var dropTargetModel: PiPStashHandleDropTargetModel
    let onRestore: @MainActor () -> Void
    let onDragEnded: @MainActor (CGRect) -> Void
    let onDragStarted: @MainActor () -> Void
    let onPullRevealChanged: @MainActor (CGFloat) -> Void
    let onPullRevealEnded: @MainActor (CGFloat) -> Bool
    let onHoverChanged: @MainActor (Bool) -> Void
    let onShowRecentPages: @MainActor () -> Void
    let onDropCandidateChanged: @MainActor (NotionPageDrop?) -> Void
    let onDropPerformed: @MainActor (NotionPageDrop) -> Void

    init(
        side: PanelStashSide,
        dropTargetModel: PiPStashHandleDropTargetModel,
        onRestore: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void = { _ in },
        onDragStarted: @escaping @MainActor () -> Void = {},
        onPullRevealChanged: @escaping @MainActor (CGFloat) -> Void = { _ in },
        onPullRevealEnded: @escaping @MainActor (CGFloat) -> Bool = { _ in false },
        onHoverChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onShowRecentPages: @escaping @MainActor () -> Void = {},
        onDropCandidateChanged: @escaping @MainActor (NotionPageDrop?) -> Void = { _ in },
        onDropPerformed: @escaping @MainActor (NotionPageDrop) -> Void = { _ in }
    ) {
        self.side = side
        self.dropTargetModel = dropTargetModel
        self.onRestore = onRestore
        self.onDragEnded = onDragEnded
        self.onDragStarted = onDragStarted
        self.onPullRevealChanged = onPullRevealChanged
        self.onPullRevealEnded = onPullRevealEnded
        self.onHoverChanged = onHoverChanged
        self.onShowRecentPages = onShowRecentPages
        self.onDropCandidateChanged = onDropCandidateChanged
        self.onDropPerformed = onDropPerformed
    }

    var body: some View {
        ZStack {
            Group {
                if dropTargetModel.isActive, let label = dropTargetModel.label {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Open in Perch")
                            .font(.system(size: 13, weight: .semibold))
                        Text(label)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 13, weight: .medium))

                        Image(systemName: side == .left ? "chevron.right" : "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: EdgeStashTabShape(side: side))
            .contentShape(EdgeStashTabShape(side: side))
            .accessibilityHidden(true)

            PiPStashHandleInteractionSurface(
                side: side,
                onActivate: onRestore,
                onDragEnded: onDragEnded,
                onDragStarted: onDragStarted,
                onPullRevealChanged: onPullRevealChanged,
                onPullRevealEnded: onPullRevealEnded,
                onHoverChanged: onHoverChanged,
                onShowRecentPages: onShowRecentPages,
                accessibilityDropLabel: dropTargetModel.isActive ? dropTargetModel.label : nil,
                onDropCandidateChanged: onDropCandidateChanged,
                onDropPerformed: onDropPerformed
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(EdgeStashTabShape(side: side))
    }
}

private struct PiPStashHandleInteractionSurface: NSViewRepresentable {
    let side: PanelStashSide
    let onActivate: @MainActor () -> Void
    let onDragEnded: @MainActor (CGRect) -> Void
    let onDragStarted: @MainActor () -> Void
    let onPullRevealChanged: @MainActor (CGFloat) -> Void
    let onPullRevealEnded: @MainActor (CGFloat) -> Bool
    let onHoverChanged: @MainActor (Bool) -> Void
    let onShowRecentPages: @MainActor () -> Void
    let accessibilityDropLabel: String?
    let onDropCandidateChanged: @MainActor (NotionPageDrop?) -> Void
    let onDropPerformed: @MainActor (NotionPageDrop) -> Void

    func makeNSView(context: Context) -> PiPStashHandleInteractionView {
        PiPStashHandleInteractionView(
            side: side,
            onActivate: onActivate,
            onDragEnded: onDragEnded,
            onDragStarted: onDragStarted,
            onPullRevealChanged: onPullRevealChanged,
            onPullRevealEnded: onPullRevealEnded,
            onHoverChanged: onHoverChanged,
            onShowRecentPages: onShowRecentPages,
            accessibilityDropLabel: accessibilityDropLabel,
            onDropCandidateChanged: onDropCandidateChanged,
            onDropPerformed: onDropPerformed
        )
    }

    func updateNSView(_ nsView: PiPStashHandleInteractionView, context: Context) {
        nsView.configure(
            side: side,
            onActivate: onActivate,
            onDragEnded: onDragEnded,
            onDragStarted: onDragStarted,
            onPullRevealChanged: onPullRevealChanged,
            onPullRevealEnded: onPullRevealEnded,
            onHoverChanged: onHoverChanged,
            onShowRecentPages: onShowRecentPages,
            accessibilityDropLabel: accessibilityDropLabel,
            onDropCandidateChanged: onDropCandidateChanged,
            onDropPerformed: onDropPerformed
        )
    }
}

@MainActor
final class PiPStashHandleInteractionView: NSView {
    private static let dragThreshold: CGFloat = 3

    private let pointerLocation: @MainActor () -> CGPoint
    private let dropCandidateReader: @MainActor (NSPasteboard) -> NotionPageDrop?
    private var side: PanelStashSide
    private var onActivate: @MainActor () -> Void
    private var onDragEnded: @MainActor (CGRect) -> Void
    private var onDragStarted: @MainActor () -> Void
    private var onPullRevealChanged: @MainActor (CGFloat) -> Void
    private var onPullRevealEnded: @MainActor (CGFloat) -> Bool
    private var onHoverChanged: @MainActor (Bool) -> Void
    private var onShowRecentPages: @MainActor () -> Void
    private var onDropCandidateChanged: @MainActor (NotionPageDrop?) -> Void
    private var onDropPerformed: @MainActor (NotionPageDrop) -> Void
    private var initialPointerLocation: CGPoint?
    private var initialWindowOrigin: CGPoint?
    private var dragMode: DragMode?
    private var latestInwardDistance: CGFloat = 0
    private var hoverTrackingArea: NSTrackingArea?
    private var dropSession = NotionPageDropSession()
    private var publishedDrop: (sequenceNumber: Int, drop: NotionPageDrop)?

    private enum DragMode {
        case reposition
        case pullReveal
    }

    init(
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        dropCandidateReader: @escaping @MainActor (NSPasteboard) -> NotionPageDrop? = {
            NotionPageDropPasteboardReader.candidate(from: $0)
        },
        side: PanelStashSide = .right,
        onActivate: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void,
        onDragStarted: @escaping @MainActor () -> Void = {},
        onPullRevealChanged: @escaping @MainActor (CGFloat) -> Void = { _ in },
        onPullRevealEnded: @escaping @MainActor (CGFloat) -> Bool = { _ in false },
        onHoverChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onShowRecentPages: @escaping @MainActor () -> Void = {},
        accessibilityDropLabel: String? = nil,
        onDropCandidateChanged: @escaping @MainActor (NotionPageDrop?) -> Void = { _ in },
        onDropPerformed: @escaping @MainActor (NotionPageDrop) -> Void = { _ in }
    ) {
        self.pointerLocation = pointerLocation
        self.dropCandidateReader = dropCandidateReader
        self.side = side
        self.onActivate = onActivate
        self.onDragEnded = onDragEnded
        self.onDragStarted = onDragStarted
        self.onPullRevealChanged = onPullRevealChanged
        self.onPullRevealEnded = onPullRevealEnded
        self.onHoverChanged = onHoverChanged
        self.onShowRecentPages = onShowRecentPages
        self.onDropCandidateChanged = onDropCandidateChanged
        self.onDropPerformed = onDropPerformed
        super.init(frame: .zero)

        registerForDraggedTypes([.URL, .string])
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
        updateAccessibility(dropLabel: accessibilityDropLabel)
        toolTip = "Pull inward to reveal; drag along the edge to move"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        side: PanelStashSide,
        onActivate: @escaping @MainActor () -> Void,
        onDragEnded: @escaping @MainActor (CGRect) -> Void,
        onDragStarted: @escaping @MainActor () -> Void = {},
        onPullRevealChanged: @escaping @MainActor (CGFloat) -> Void = { _ in },
        onPullRevealEnded: @escaping @MainActor (CGFloat) -> Bool = { _ in false },
        onHoverChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onShowRecentPages: @escaping @MainActor () -> Void = {},
        accessibilityDropLabel: String? = nil,
        onDropCandidateChanged: @escaping @MainActor (NotionPageDrop?) -> Void = { _ in },
        onDropPerformed: @escaping @MainActor (NotionPageDrop) -> Void = { _ in }
    ) {
        self.side = side
        self.onActivate = onActivate
        self.onDragEnded = onDragEnded
        self.onDragStarted = onDragStarted
        self.onPullRevealChanged = onPullRevealChanged
        self.onPullRevealEnded = onPullRevealEnded
        self.onHoverChanged = onHoverChanged
        self.onShowRecentPages = onShowRecentPages
        self.onDropCandidateChanged = onDropCandidateChanged
        self.onDropPerformed = onDropPerformed
        updateAccessibility(dropLabel: publishedDrop == nil ? nil : accessibilityDropLabel)
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
            window.setFrameOrigin(
                CGPoint(
                    x: initialWindowOrigin.x + (side == .left ? inwardDistance : -inwardDistance),
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

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(snapshot: dragSnapshot(from: sender))
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(snapshot: dragSnapshot(from: sender))
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        prepareForDragOperation(sequenceNumber: sender.draggingSequenceNumber)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        performDragOperation(sequenceNumber: sender.draggingSequenceNumber)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        draggingExited()
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        concludeDragOperation()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        draggingEnded()
    }

    func draggingEntered(snapshot: PiPStashHandleDragSnapshot) -> NSDragOperation {
        updateDropTarget(snapshot: snapshot)
    }

    func draggingUpdated(snapshot: PiPStashHandleDragSnapshot) -> NSDragOperation {
        updateDropTarget(snapshot: snapshot)
    }

    func prepareForDragOperation(sequenceNumber: Int) -> Bool {
        dropSession.canPrepare(sequenceNumber: sequenceNumber)
    }

    func performDragOperation(sequenceNumber: Int) -> Bool {
        guard let drop = dropSession.perform(sequenceNumber: sequenceNumber) else {
            return false
        }
        clearDropTarget(resetsSession: false)
        onDropPerformed(drop)
        return true
    }

    func draggingExited() {
        clearDropTarget()
    }

    func concludeDragOperation() {
        clearDropTarget()
    }

    func draggingEnded() {
        clearDropTarget()
    }

    private func dragSnapshot(from sender: any NSDraggingInfo) -> PiPStashHandleDragSnapshot {
        PiPStashHandleDragSnapshot(
            sequenceNumber: sender.draggingSequenceNumber,
            candidate: dropCandidateReader(sender.draggingPasteboard),
            sourceOperationMask: sender.draggingSourceOperationMask
        )
    }

    private func updateDropTarget(
        snapshot: PiPStashHandleDragSnapshot
    ) -> NSDragOperation {
        let operation = dropSession.update(
            sequenceNumber: snapshot.sequenceNumber,
            candidate: snapshot.candidate,
            sourceOperationMask: snapshot.sourceOperationMask
        )
        guard operation == .copy else {
            clearDropTarget(resetsSession: false)
            return []
        }
        guard publishedDrop?.sequenceNumber != snapshot.sequenceNumber,
              let candidate = dropSession.frozenCandidate(
                  sequenceNumber: snapshot.sequenceNumber
              )
        else {
            return .copy
        }

        publishedDrop = (snapshot.sequenceNumber, candidate)
        onDropCandidateChanged(candidate)
        updateAccessibility(dropLabel: candidate.displayLabel(localTitle: nil))
        return .copy
    }

    private func clearDropTarget(resetsSession: Bool = true) {
        if resetsSession {
            dropSession.reset()
        }
        guard publishedDrop != nil else { return }
        publishedDrop = nil
        onDropCandidateChanged(nil)
        updateAccessibility(dropLabel: nil)
    }

    private func updateAccessibility(dropLabel: String?) {
        if let dropLabel {
            setAccessibilityLabel("Open \(dropLabel) in Perch")
            setAccessibilityHelp(nil)
        } else {
            setAccessibilityLabel("Restore Perch")
            setAccessibilityHelp("Bring the stashed Perch back from the side.")
        }
    }

    private func resetInteraction() {
        initialPointerLocation = nil
        initialWindowOrigin = nil
        dragMode = nil
        latestInwardDistance = 0
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
