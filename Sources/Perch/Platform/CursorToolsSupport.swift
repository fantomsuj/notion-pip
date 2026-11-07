import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// The Accessibility permission the cursor tools use to drop into other apps
/// and to read the front window's title for margin notes.
@MainActor
enum CursorToolsAccessibility {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS to show its Accessibility prompt for Perch. Returns the
    /// current trust, which stays false until the person allows it.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Everything on a pasteboard, so Perch can borrow it for one paste and then
/// put back what the person had copied.
struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    @MainActor
    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

@MainActor
enum SyntheticPaste {
    /// Presses Command-V in whichever app is in front. Needs Accessibility.
    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Sends Paste to Perch's own key window, such as the Notion page.
    static func pasteIntoPerch() {
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    }
}

/// Reads where a margin note is being jotted: the front app and, with
/// Accessibility, its focused window's title and document.
@MainActor
enum MarginNoteSourceReader {
    static func read(
        workspace: NSWorkspace = .shared,
        canReadWindows: Bool = CursorToolsAccessibility.isTrusted
    ) -> MarginNoteSource? {
        guard let application = workspace.frontmostApplication else { return nil }
        let name = application.localizedName
            ?? application.bundleIdentifier
            ?? "Unknown app"
        var source = MarginNoteSource(
            applicationName: name,
            bundleIdentifier: application.bundleIdentifier
        )
        guard canReadWindows else { return source }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let window = element(applicationElement, kAXFocusedWindowAttribute) else {
            return source
        }
        source.windowTitle = string(window, kAXTitleAttribute)
        if let document = string(window, kAXDocumentAttribute) {
            source.documentURL = URL(string: document)
        }
        return source
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        // The type ID check above makes this cast safe.
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else {
            return nil
        }
        return value as? String
    }
}

/// A short message that appears beside the pointer, then fades.
@MainActor
final class CursorToast {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, duration: Duration = .seconds(2.4)) {
        hideTask?.cancel()
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.preferredMaxLayoutWidth = 260

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = DesignTokens.Radius.card
        background.layer?.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: background.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -7),
        ])
        let size = background.fittingSize

        let panel = self.panel ?? CursorOverlayPanel.make()
        panel.contentView = background
        let mouse = NSEvent.mouseLocation
        panel.setFrame(
            CGRect(x: mouse.x + 16, y: mouse.y - 24 - size.height, width: size.width, height: size.height),
            display: true
        )
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
    }
}

@MainActor
enum CursorOverlayPanel {
    /// A borderless panel above other windows that clicks pass straight through.
    static func make() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        return panel
    }
}
