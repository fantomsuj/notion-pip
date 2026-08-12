import AppKit
import WebKit

@MainActor
enum ExternalTextDrop {
    static func hasReadableText(in pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(
            forClasses: [NSAttributedString.self, NSString.self],
            options: [:]
        )
    }

    static func isExternalDraggingSource(_ source: Any?, relativeTo webView: NSView) -> Bool {
        guard let sourceView = source as? NSView else {
            return true
        }

        return sourceView !== webView && !sourceView.isDescendant(of: webView)
    }
}

@MainActor
final class ExternalTextDropActivation {
    private var dragSequenceNumber: Int?
    private(set) var didActivatePanel = false
    private(set) var didPrepareCurrentDrag = false

    func prepareIfNeeded(
        for dragSequenceNumber: Int,
        isExternalText: Bool,
        activatePanel: () -> Bool,
        focusWebView: () -> Bool
    ) {
        if self.dragSequenceNumber != dragSequenceNumber {
            self.dragSequenceNumber = dragSequenceNumber
            didActivatePanel = false
            didPrepareCurrentDrag = false
        }

        guard isExternalText, !didPrepareCurrentDrag else {
            return
        }

        // A detached panel cannot be activated yet. Once it is active, only
        // retry the first-responder handoff; do not activate the app twice.
        if !didActivatePanel {
            didActivatePanel = activatePanel()
        }
        guard didActivatePanel else {
            return
        }
        didPrepareCurrentDrag = focusWebView()
    }

    func reset() {
        dragSequenceNumber = nil
        didActivatePanel = false
        didPrepareCurrentDrag = false
    }
}

/// A WebKit view that makes an external text drop safe when the PiP panel is inactive.
///
/// WebKit remains the drag destination: this class only prepares the window and then
/// forwards the original drag callbacks and `NSDraggingInfo` to `WKWebView`.
@MainActor
final class ExternalDropActivatingWebView: WKWebView {
    private let externalDropActivation = ExternalTextDropActivation()

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        prepareForExternalTextDrop(sender)
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        super.draggingUpdated(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        prepareForExternalTextDrop(sender)
        return super.prepareForDragOperation(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        externalDropActivation.reset()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { externalDropActivation.reset() }
        return super.performDragOperation(sender)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        super.concludeDragOperation(sender)
        externalDropActivation.reset()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        super.draggingEnded(sender)
        externalDropActivation.reset()
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        super.wantsPeriodicDraggingUpdates()
    }

    private func prepareForExternalTextDrop(_ draggingInfo: NSDraggingInfo) {
        externalDropActivation.prepareIfNeeded(
            for: draggingInfo.draggingSequenceNumber,
            isExternalText: isExternalTextDrag(draggingInfo),
            activatePanel: { [weak self] in
                self?.activatePanelForExternalDrop() ?? false
            },
            focusWebView: { [weak self] in
                self?.focusForExternalDrop() ?? false
            }
        )
    }

    private func isExternalTextDrag(_ draggingInfo: NSDraggingInfo) -> Bool {
        guard ExternalTextDrop.hasReadableText(in: draggingInfo.draggingPasteboard) else {
            return false
        }

        return ExternalTextDrop.isExternalDraggingSource(
            draggingInfo.draggingSource,
            relativeTo: self
        )
    }

    private func activatePanelForExternalDrop() -> Bool {
        guard let panel = window as? KeyCapablePiPPanel, panel.isVisible else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    private func focusForExternalDrop() -> Bool {
        guard let panel = window as? KeyCapablePiPPanel, panel.isVisible else {
            return false
        }
        return panel.makeFirstResponder(self)
    }
}
