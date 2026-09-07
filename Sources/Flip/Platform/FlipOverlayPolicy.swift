import AppKit

enum FlipOverlayPolicy {
    static let styleMask: NSWindow.StyleMask = [.borderless, .resizable]
    static let level = NSWindow.Level.floating
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .moveToActiveSpace,
        .fullScreenAuxiliary,
        .transient,
    ]
    static let chromeHeight: CGFloat = 36
    static let minimumContentSize = CGSize(width: 320, height: 240)

    static func makeWindow(frame: CGRect) -> FlipOccupancyWindow {
        let window = FlipOccupancyWindow(
            contentRect: frame,
            styleMask: styleMask,
            backing: .buffered,
            defer: true
        )
        window.level = level
        window.collectionBehavior = collectionBehavior
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentMinSize = minimumContentSize
        window.setFrame(frame, display: false)
        return window
    }
}

final class FlipOccupancyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
