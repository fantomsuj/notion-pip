import AppKit
import SwiftUI

@MainActor
protocol PanelSnapTargetPresenting: AnyObject {
    func present(_ target: PanelCornerSnapTarget)
    func dismiss()
}

@MainActor
final class PanelSnapTargetOverlayController: PanelSnapTargetPresenting {
    private static let markerSize: CGFloat = 38

    private let panel: NSPanel
    private var presentedTarget: PanelCornerSnapTarget?

    init(panel: NSPanel? = nil) {
        if let panel {
            self.panel = panel
        } else {
            self.panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
        }
        configurePanel()
    }

    func present(_ target: PanelCornerSnapTarget) {
        guard target != presentedTarget else { return }
        presentedTarget = target
        panel.contentView = NSHostingView(rootView: PanelCornerBracket(corner: target.corner))
        panel.setFrame(markerFrame(for: target), display: true)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        guard presentedTarget != nil || panel.isVisible else { return }
        presentedTarget = nil
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
    }

    private func markerFrame(for target: PanelCornerSnapTarget) -> CGRect {
        let size = Self.markerSize
        let origin = switch target.corner {
        case .topLeft:
            CGPoint(x: target.frame.minX, y: target.frame.maxY - size)
        case .topRight:
            CGPoint(x: target.frame.maxX - size, y: target.frame.maxY - size)
        case .bottomLeft:
            CGPoint(x: target.frame.minX, y: target.frame.minY)
        case .bottomRight:
            CGPoint(x: target.frame.maxX - size, y: target.frame.minY)
        }
        return CGRect(origin: origin, size: CGSize(width: size, height: size))
    }
}

private struct PanelCornerBracket: View {
    let corner: PanelCorner

    var body: some View {
        PanelCornerBracketShape(corner: corner)
            .stroke(
                Color(nsColor: .controlAccentColor).opacity(0.46),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
            .padding(7)
            .accessibilityHidden(true)
    }
}

private struct PanelCornerBracketShape: Shape {
    let corner: PanelCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch corner {
        case .topLeft:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .topRight:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomLeft:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomRight:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return path
    }
}
