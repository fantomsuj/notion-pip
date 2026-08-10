import AppKit
@preconcurrency import ApplicationServices

typealias QuickCopyScheduledCancellation = @MainActor () -> Void
typealias QuickCopyCommitScheduler = @MainActor (
    Duration,
    @escaping @MainActor () -> Void
) -> QuickCopyScheduledCancellation

@MainActor
final class QuickCopySelectionCommitCoordinator {
    private let keyboardDebounce: Duration
    private let schedule: QuickCopyCommitScheduler
    private let onCommit: @MainActor () -> Void
    private var pendingKeyboardCommit: QuickCopyScheduledCancellation?

    init(
        keyboardDebounce: Duration = .milliseconds(250),
        schedule: @escaping QuickCopyCommitScheduler = { delay, operation in
            let task = Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                operation()
            }
            return { task.cancel() }
        },
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.keyboardDebounce = keyboardDebounce
        self.schedule = schedule
        self.onCommit = onCommit
    }

    func selectedTextDidChange() {
        pendingKeyboardCommit?()
        pendingKeyboardCommit = schedule(keyboardDebounce) { [weak self] in
            guard let self else { return }
            self.pendingKeyboardCommit = nil
            self.onCommit()
        }
    }

    func mouseDidRelease() {
        pendingKeyboardCommit?()
        pendingKeyboardCommit = nil
        onCommit()
    }

    func cancel() {
        pendingKeyboardCommit?()
        pendingKeyboardCommit = nil
    }
}

/// Reads selected text from the frontmost application while Quick Copy is visibly armed.
/// The monitor never synthesizes input, takes screenshots, or accesses the pasteboard.
@MainActor
final class AccessibilitySelectionMonitor: NSObject, QuickCopyMonitoring {
    var onEvent: (@MainActor (QuickCopyMonitorEvent) -> Void)?

    private var workspaceObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var permissionTimer: Timer?
    private var accessibilityObserver: AXObserver?
    private var observedApplicationElement: AXUIElement?
    private var observedFocusedElement: AXUIElement?
    private var isMonitoring = false
    private var sequence: UInt64 = 0
    private lazy var commitCoordinator = QuickCopySelectionCommitCoordinator {
        [weak self] in
        self?.commitCurrentSelection()
    }

    func requestAccessibilityAccess() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard !isMonitoring else { return }
        guard AXIsProcessTrusted() else {
            onEvent?(.permissionRevoked)
            return
        }

        isMonitoring = true
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.observeFrontmostApplication()
            }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.commitCoordinator.mouseDidRelease()
            }
        }
        let permissionTimer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(checkAccessibilityPermission),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(permissionTimer, forMode: .common)
        self.permissionTimer = permissionTimer
        observeFrontmostApplication()
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        commitCoordinator.cancel()
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        removeAccessibilityObserver()
    }

    @objc private func checkAccessibilityPermission() {
        guard isMonitoring, !AXIsProcessTrusted() else { return }
        stop()
        onEvent?(.permissionRevoked)
    }

    private func observeFrontmostApplication() {
        removeAccessibilityObserver()
        guard isMonitoring,
              let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return
        }

        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier
        )
        var observer: AXObserver?
        let result = AXObserverCreate(
            application.processIdentifier,
            Self.accessibilityNotificationCallback,
            &observer
        )
        guard result == .success, let observer else {
            onEvent?(.unsupportedSource(application.localizedName))
            return
        }

        accessibilityObserver = observer
        observedApplicationElement = applicationElement
        AXObserverAddNotification(
            observer,
            applicationElement,
            kAXFocusedUIElementChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        observeFocusedElement()
    }

    private func observeFocusedElement() {
        guard let observer = accessibilityObserver,
              let applicationElement = observedApplicationElement
        else {
            return
        }
        if let observedFocusedElement {
            AXObserverRemoveNotification(
                observer,
                observedFocusedElement,
                kAXSelectedTextChangedNotification as CFString
            )
        }
        observedFocusedElement = nil

        let (error, value) = copyAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: applicationElement
        )
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return
        }
        // The Core Foundation type check above establishes this bridge invariant.
        let focusedElement = unsafeDowncast(value, to: AXUIElement.self)
        observedFocusedElement = focusedElement
        AXObserverAddNotification(
            observer,
            focusedElement,
            kAXSelectedTextChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func removeAccessibilityObserver() {
        guard let observer = accessibilityObserver else {
            observedApplicationElement = nil
            observedFocusedElement = nil
            return
        }
        if let observedFocusedElement {
            AXObserverRemoveNotification(
                observer,
                observedFocusedElement,
                kAXSelectedTextChangedNotification as CFString
            )
        }
        if let observedApplicationElement {
            AXObserverRemoveNotification(
                observer,
                observedApplicationElement,
                kAXFocusedUIElementChangedNotification as CFString
            )
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        accessibilityObserver = nil
        observedApplicationElement = nil
        observedFocusedElement = nil
    }

    private func handleAccessibilityNotification(_ notification: String) {
        guard isMonitoring else { return }
        if notification == (kAXFocusedUIElementChangedNotification as String) {
            observeFocusedElement()
        } else if notification == (kAXSelectedTextChangedNotification as String) {
            commitCoordinator.selectedTextDidChange()
        }
    }

    private func commitCurrentSelection() {
        guard isMonitoring, AXIsProcessTrusted(),
              let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return
        }
        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier
        )
        let (focusedError, focusedValue) = copyAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: applicationElement
        )
        guard focusedError == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            onEvent?(.unsupportedSource(application.localizedName))
            return
        }
        // The Core Foundation type check above establishes this bridge invariant.
        let focusedElement = unsafeDowncast(focusedValue, to: AXUIElement.self)
        let role = stringAttribute(kAXRoleAttribute as CFString, from: focusedElement)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: focusedElement)
        if subrole == (kAXSecureTextFieldSubrole as String)
            || role?.localizedCaseInsensitiveContains("secure") == true
        {
            onEvent?(.secureSource)
            return
        }

        let (selectionError, selectionValue) = copyAttribute(
            kAXSelectedTextAttribute as CFString,
            from: focusedElement
        )
        if selectionError == .attributeUnsupported {
            onEvent?(.unsupportedSource(application.localizedName))
            return
        }
        guard selectionError == .success,
              let text = selectionValue as? String,
              !text.isEmpty
        else {
            return
        }

        sequence &+= 1
        onEvent?(
            .candidate(
                QuickCopyCandidate(
                    text: text,
                    source: QuickCopySource(
                        processID: application.processIdentifier,
                        bundleIdentifier: application.bundleIdentifier,
                        applicationName: application.localizedName
                    ),
                    sequence: sequence
                )
            )
        )
    }

    private func copyAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        return (error, value)
    }

    private func stringAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> String? {
        let (error, value) = copyAttribute(attribute, from: element)
        return error == .success ? value as? String : nil
    }

    private static let accessibilityNotificationCallback: AXObserverCallback = {
        _, _, notification, context in
        guard let context else { return }
        let notificationName = notification as String
        let monitor = Unmanaged<AccessibilitySelectionMonitor>
            .fromOpaque(context)
            .takeUnretainedValue()
        Task { @MainActor in
            monitor.handleAccessibilityNotification(notificationName)
        }
    }
}
