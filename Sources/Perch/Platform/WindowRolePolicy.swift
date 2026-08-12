import AppKit

@MainActor
enum WindowRole {
    case onboarding
    case settings
    case pictureInPicture
    case stashHandle
    case stashShelf

    var policy: WindowRolePolicy {
        switch self {
        case .onboarding:
            WindowRolePolicy(
                kind: .keyWindow,
                styleMask: [.titled, .closable, .resizable],
                level: .normal,
                collectionBehavior: [.moveToActiveSpace, .fullScreenAuxiliary],
                initialContentSize: CGSize(width: 760, height: 520),
                minimumContentSize: CGSize(width: 680, height: 480)
            )
        case .settings:
            WindowRolePolicy(
                kind: .keyWindow,
                styleMask: [.titled, .closable, .resizable],
                level: .normal,
                collectionBehavior: [.moveToActiveSpace, .fullScreenAuxiliary],
                initialContentSize: CGSize(width: 480, height: 460),
                minimumContentSize: CGSize(width: 440, height: 420)
            )
        case .pictureInPicture:
            WindowRolePolicy(
                kind: .keyPanel,
                styleMask: [.titled, .closable, .resizable],
                level: .floating,
                collectionBehavior: [
                    .canJoinAllSpaces,
                    .fullScreenAuxiliary,
                    .transient,
                    .ignoresCycle,
                ],
                initialContentSize: CGSize(width: 480, height: 720),
                minimumContentSize: CGSize(width: 360, height: 420)
            )
        case .stashHandle, .stashShelf:
            WindowRolePolicy(
                kind: self == .stashShelf
                    ? .focusableNonactivatingPanel
                    : .nonactivatingPanel,
                styleMask: [.borderless, .nonactivatingPanel],
                level: .floating,
                collectionBehavior: [
                    .canJoinAllSpaces,
                    .fullScreenAuxiliary,
                    .transient,
                    .ignoresCycle,
                ],
                initialContentSize: .zero,
                minimumContentSize: .zero
            )
        }
    }

    func makeWindow() -> NSWindow {
        let window = policy.makeWindow()
        switch self {
        case .stashHandle, .stashShelf:
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
        default:
            break
        }
        return window
    }
}

@MainActor
struct WindowRolePolicy {
    enum Kind {
        case keyWindow
        case keyPanel
        case nonactivatingPanel
        case focusableNonactivatingPanel
    }

    let kind: Kind
    let styleMask: NSWindow.StyleMask
    let level: NSWindow.Level
    let collectionBehavior: NSWindow.CollectionBehavior
    let initialContentSize: CGSize
    let minimumContentSize: CGSize
    let maximumContentSize: CGSize?

    init(
        kind: Kind,
        styleMask: NSWindow.StyleMask,
        level: NSWindow.Level,
        collectionBehavior: NSWindow.CollectionBehavior,
        initialContentSize: CGSize,
        minimumContentSize: CGSize,
        maximumContentSize: CGSize? = nil
    ) {
        self.kind = kind
        self.styleMask = styleMask
        self.level = level
        self.collectionBehavior = collectionBehavior
        self.initialContentSize = initialContentSize
        self.minimumContentSize = minimumContentSize
        self.maximumContentSize = maximumContentSize
    }

    func makeWindow() -> NSWindow {
        let contentRect = CGRect(origin: .zero, size: initialContentSize)
        let window: NSWindow
        switch kind {
        case .keyWindow:
            window = KeyCapableAppWindow(
                contentRect: contentRect,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
        case .keyPanel:
            window = KeyCapablePiPPanel(
                contentRect: contentRect,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
        case .nonactivatingPanel:
            window = NSPanel(
                contentRect: contentRect,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
        case .focusableNonactivatingPanel:
            window = KeyCapableStashShelfPanel(
                contentRect: contentRect,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
        }
        apply(to: window)
        if let panel = window as? KeyCapablePiPPanel {
            panel.configureCloseButtonForStash()
        }
        return window
    }

    func apply(to window: NSWindow) {
        window.styleMask = styleMask
        window.level = level
        window.collectionBehavior = collectionBehavior
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = minimumContentSize
        if let maximumContentSize {
            window.contentMaxSize = maximumContentSize
        }
    }
}

@MainActor
final class KeyCapableStashShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
