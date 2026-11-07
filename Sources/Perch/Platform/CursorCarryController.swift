import AppKit
import CoreGraphics
import OSLog

/// Carries a screenshot on the pointer. Double-click anywhere to drop it there,
/// or shake the pointer to toss it.
///
/// Dropping puts the image on the pasteboard for a moment and pastes it where
/// the person double-clicked: into the Notion page when that is Perch, or into
/// any other app when Perch has Accessibility. The person's own clipboard is
/// put back afterwards. Without Accessibility, a double-click outside Perch
/// leaves the image on the clipboard to paste with Command-V.
@MainActor
final class CursorCarryController {
    enum Phase: Equatable {
        case idle
        case capturing
        case carrying
    }

    private(set) var phase: Phase = .idle
    var onPhaseChange: (@MainActor (Phase) -> Void)?

    private let logger = Logger(subsystem: "com.fantomsuj.Perch", category: "cursor-carry")
    private let pasteboard: NSPasteboard
    private let toast: CursorToast
    private var captureURL: URL?
    private var image: NSImage?
    private var imageData: Data?
    private var thumbnailPanel: NSPanel?
    private var thumbnailSize: CGSize = .zero
    private var shakeDetector = CursorShakeDetector()
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var swallowsNextMouseUp = false
    private var restoreTask: Task<Void, Never>?

    init(pasteboard: NSPasteboard = .general, toast: CursorToast) {
        self.pasteboard = pasteboard
        self.toast = toast
    }

    /// Starts an area screenshot. Space switches to a window; Escape cancels.
    func beginCarry() {
        switch phase {
        case .capturing:
            return
        case .carrying:
            // A second press swaps the carried shot for a new one.
            endCarry()
        case .idle:
            break
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-carry-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureFinished(at: url)
            }
        }
        do {
            try process.run()
            setPhase(.capturing)
        } catch {
            logger.error("Screenshot capture could not start")
            toast.show("Perch couldn’t start a screenshot.")
        }
    }

    /// Lets go of the carried screenshot without dropping it.
    func toss() {
        guard phase == .carrying else { return }
        animateToss()
    }

    func stop() {
        endCarry()
    }

    // MARK: - Capture

    private func captureFinished(at url: URL) {
        guard phase == .capturing else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            // Escape in the screenshot UI leaves no file. If nothing was saved
            // and Perch can't record the screen, say why.
            try? FileManager.default.removeItem(at: url)
            setPhase(.idle)
            if !CGPreflightScreenCaptureAccess() {
                toast.show("Allow Perch under Screen Recording in System Settings to carry screenshots.")
            }
            return
        }
        captureURL = url
        self.image = image
        imageData = data
        startCarrying(image)
    }

    // MARK: - Carrying

    private func startCarrying(_ image: NSImage) {
        let panel = makeThumbnailPanel(for: image)
        thumbnailPanel = panel
        shakeDetector.reset()
        swallowsNextMouseUp = false
        moveThumbnail(to: NSEvent.mouseLocation)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionTokens.Duration.fast
            panel.animator().alphaValue = 1
        }
        installEventHandling()
        setPhase(.carrying)
    }

    private func makeThumbnailPanel(for image: NSImage) -> NSPanel {
        let maximumSide: CGFloat = 132
        let sourceSize = image.size
        let scale = min(1, maximumSide / max(sourceSize.width, sourceSize.height, 1))
        let imageSize = CGSize(
            width: max(36, sourceSize.width * scale),
            height: max(36, sourceSize.height * scale)
        )

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: imageSize))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = DesignTokens.Radius.control
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 2
        imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor

        let hint = NSTextField(labelWithString: "Double-click to drop · shake to toss")
        hint.font = .systemFont(ofSize: 10, weight: .medium)
        hint.textColor = .white
        hint.alignment = .center
        let hintBackground = NSView()
        hintBackground.wantsLayer = true
        hintBackground.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        hintBackground.layer?.cornerRadius = 4
        hint.translatesAutoresizingMaskIntoConstraints = false
        hintBackground.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: hintBackground.leadingAnchor, constant: 5),
            hint.trailingAnchor.constraint(equalTo: hintBackground.trailingAnchor, constant: -5),
            hint.topAnchor.constraint(equalTo: hintBackground.topAnchor, constant: 2),
            hint.bottomAnchor.constraint(equalTo: hintBackground.bottomAnchor, constant: -2),
        ])
        let hintSize = hintBackground.fittingSize

        let width = max(imageSize.width, hintSize.width)
        let height = imageSize.height + 4 + hintSize.height
        let container = NSView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        imageView.frame = CGRect(
            x: (width - imageSize.width) / 2,
            y: hintSize.height + 4,
            width: imageSize.width,
            height: imageSize.height
        )
        hintBackground.frame = CGRect(
            x: (width - hintSize.width) / 2,
            y: 0,
            width: hintSize.width,
            height: hintSize.height
        )
        container.addSubview(imageView)
        container.addSubview(hintBackground)

        let panel = thumbnailPanel ?? CursorOverlayPanel.make()
        panel.contentView = container
        thumbnailSize = container.frame.size
        panel.setContentSize(thumbnailSize)
        return panel
    }

    private func moveThumbnail(to point: CGPoint) {
        guard let thumbnailPanel else { return }
        // Sit below and to the right of the hotspot so it never covers the
        // spot the person is about to double-click.
        thumbnailPanel.setFrameOrigin(CGPoint(
            x: point.x + 18,
            y: point.y - 18 - thumbnailSize.height
        ))
    }

    private func pointerMoved(at time: TimeInterval) {
        let point = NSEvent.mouseLocation
        moveThumbnail(to: point)
        if shakeDetector.record(point, at: time) {
            // Next turn of the run loop, like a drop.
            Task { @MainActor [weak self] in
                self?.toss()
            }
        }
    }

    // MARK: - Event handling

    private func installEventHandling() {
        removeEventHandling()
        if CursorToolsAccessibility.isTrusted, installEventTap() {
            return
        }
        installMonitors()
    }

    /// With Accessibility, an event tap can hold back the second click of a
    /// double-click, so the target app sees one click that places the cursor
    /// rather than a double-click that selects a word.
    private func installEventTap() -> Bool {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                CursorCarryController.handleTapEvent(type: type, event: event, userInfo: userInfo)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapSource = source
        return true
    }

    private nonisolated static func handleTapEvent(
        type: CGEventType,
        event: CGEvent,
        userInfo: UnsafeMutableRawPointer?
    ) -> Unmanaged<CGEvent>? {
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let clickState = event.getIntegerValueField(.mouseEventClickState)
        let timestamp = TimeInterval(event.timestamp) / 1_000_000_000
        let controller = Unmanaged<CursorCarryController>.fromOpaque(userInfo)
            .takeUnretainedValue()
        // The tap's run-loop source is on the main run loop.
        let swallow = MainActor.assumeIsolated {
            controller.handleTap(type: type, clickState: clickState, timestamp: timestamp)
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    /// Returns true when the event should not reach any app.
    private func handleTap(type: CGEventType, clickState: Int64, timestamp: TimeInterval) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        case .mouseMoved, .leftMouseDragged:
            pointerMoved(at: timestamp)
            return false
        case .leftMouseDown:
            guard phase == .carrying, clickState >= 2 else { return false }
            swallowsNextMouseUp = true
            return true
        case .leftMouseUp:
            guard swallowsNextMouseUp else { return false }
            swallowsNextMouseUp = false
            scheduleDrop(pasteWith: .commandV)
            return true
        default:
            return false
        }
    }

    /// Without Accessibility: Perch can still hold back the second click in
    /// its own windows, and can watch, but not stop, clicks in other apps.
    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let clickCount = event.clickCount
            let timestamp = event.timestamp
            // Local monitors run on the main thread.
            let swallow = MainActor.assumeIsolated {
                self?.handleLocal(type: type, clickCount: clickCount, timestamp: timestamp) ?? false
            }
            return swallow ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let clickCount = event.clickCount
            let timestamp = event.timestamp
            Task { @MainActor [weak self] in
                self?.handleGlobal(type: type, clickCount: clickCount, timestamp: timestamp)
            }
        }
    }

    private func handleLocal(type: NSEvent.EventType, clickCount: Int, timestamp: TimeInterval) -> Bool {
        switch type {
        case .mouseMoved, .leftMouseDragged:
            pointerMoved(at: timestamp)
            return false
        case .leftMouseDown:
            guard phase == .carrying, clickCount >= 2 else { return false }
            swallowsNextMouseUp = true
            return true
        case .leftMouseUp:
            guard swallowsNextMouseUp else { return false }
            swallowsNextMouseUp = false
            scheduleDrop(pasteWith: .perchPaste)
            return true
        default:
            return false
        }
    }

    private func handleGlobal(type: NSEvent.EventType, clickCount: Int, timestamp: TimeInterval) {
        switch type {
        case .mouseMoved, .leftMouseDragged:
            pointerMoved(at: timestamp)
        case .leftMouseUp:
            guard phase == .carrying, clickCount >= 2 else { return }
            drop(pasteWith: .clipboardOnly)
        default:
            break
        }
    }

    private func removeEventHandling() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        eventTap = nil
        eventTapSource = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        swallowsNextMouseUp = false
    }

    // MARK: - Drop and toss

    private enum PasteRoute {
        /// Press Command-V in the front app. Needs Accessibility.
        case commandV
        /// Paste into Perch's own key window.
        case perchPaste
        /// Leave the image on the clipboard for the person to paste.
        case clipboardOnly
    }

    /// Drops on the next turn of the run loop, so the event tap or monitor
    /// that saw the click is not torn down while it is still handling it.
    private func scheduleDrop(pasteWith route: PasteRoute) {
        Task { @MainActor [weak self] in
            self?.drop(pasteWith: route)
        }
    }

    private func drop(pasteWith route: PasteRoute) {
        guard phase == .carrying, let image else { return }
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let imageData {
            item.setData(imageData, forType: .png)
        }
        if let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.writeObjects([item])
        let changeCount = pasteboard.changeCount

        animateDrop()

        switch route {
        case .commandV:
            // Give the app a moment to finish the click before it gets the paste.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(60))
                SyntheticPaste.postCommandV()
                self?.scheduleRestore(snapshot, ifChangeCountIs: changeCount)
            }
        case .perchPaste:
            SyntheticPaste.pasteIntoPerch()
            scheduleRestore(snapshot, ifChangeCountIs: changeCount)
        case .clipboardOnly:
            toast.show("Screenshot copied. Press ⌘V to paste. Allow Accessibility in Perch Settings to drop it in one step.")
        }
    }

    /// Puts the person's clipboard back once the paste has had time to read
    /// the image, unless they copied something new in the meantime.
    private func scheduleRestore(_ snapshot: PasteboardSnapshot, ifChangeCountIs changeCount: Int) {
        restoreTask?.cancel()
        restoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled,
                  self.pasteboard.changeCount == changeCount
            else { return }
            snapshot.restore(to: self.pasteboard)
        }
    }

    private func animateDrop() {
        let frame = thumbnailPanel?.frame ?? .zero
        let target = CGRect(x: frame.minX - 14, y: frame.maxY + 6, width: 8, height: 8)
        finishCarry(animatingTo: target, duration: MotionTokens.Duration.fast, timing: .easeOut)
    }

    private func animateToss() {
        let frame = thumbnailPanel?.frame ?? .zero
        let target = frame.offsetBy(dx: 40, dy: -frame.height * 2)
        finishCarry(animatingTo: target, duration: MotionTokens.Duration.medium, timing: .easeIn)
    }

    /// Ends the carry now and lets the thumbnail animate away on its own, so
    /// a new carry can start while the old one is still fading.
    private func finishCarry(
        animatingTo target: CGRect,
        duration: TimeInterval,
        timing: CAMediaTimingFunctionName
    ) {
        guard let panel = thumbnailPanel else {
            endCarry()
            return
        }
        thumbnailPanel = nil
        endCarry()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: timing)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                panel.contentView = nil
            }
        }
    }

    private func endCarry() {
        removeEventHandling()
        thumbnailPanel?.orderOut(nil)
        thumbnailPanel?.contentView = nil
        thumbnailPanel = nil
        if let captureURL {
            try? FileManager.default.removeItem(at: captureURL)
        }
        captureURL = nil
        image = nil
        imageData = nil
        shakeDetector.reset()
        if phase != .idle {
            setPhase(.idle)
        }
    }

    private func setPhase(_ phase: Phase) {
        guard self.phase != phase else { return }
        self.phase = phase
        onPhaseChange?(phase)
    }
}
