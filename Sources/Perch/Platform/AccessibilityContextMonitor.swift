import AppKit
@preconcurrency import ApplicationServices

@MainActor
protocol ContextMonitoring: AnyObject {
    var onSnapshot: (@MainActor (ContextSnapshot?) -> Void)? { get set }
    var onAuthorizationChange: (@MainActor (Bool) -> Void)? { get set }
    var isAuthorized: Bool { get }
    func requestAccess() -> Bool
    func start()
    func stop()
    func captureSourceIdentity() -> ContextSourceIdentity?
    func captureExactPage(
        completion: @escaping @MainActor (ContextSnapshot?) -> Void
    )
    func captureExactPage(
        from source: ContextSourceIdentity,
        completion: @escaping @MainActor (ContextSnapshot?) -> Void
    )
}

extension ContextMonitoring {
    func captureSourceIdentity() -> ContextSourceIdentity? {
        nil
    }

    func captureExactPage(
        completion: @escaping @MainActor (ContextSnapshot?) -> Void
    ) {
        completion(nil)
    }

    func captureExactPage(
        from source: ContextSourceIdentity,
        completion: @escaping @MainActor (ContextSnapshot?) -> Void
    ) {
        captureExactPage(completion: completion)
    }
}

/// Reads a narrow, transient description of the frontmost app after explicit consent.
/// It does not read selected text, keystrokes, pasteboard contents, screenshots, or DOM data.
@MainActor
final class AccessibilityContextMonitor: ContextMonitoring {
    var onSnapshot: (@MainActor (ContextSnapshot?) -> Void)?
    var onAuthorizationChange: (@MainActor (Bool) -> Void)?

    var isAuthorized: Bool { AXIsProcessTrusted() }

    private var timer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var lastSnapshot: ContextSnapshot?
    private var targetProcessIdentifier: pid_t?
    private var readGeneration: UInt = 0
    private var isReadInFlight = false
    private var isMonitoring = false
    private let reader = AccessibilityContextReader()
    private let workerQueue = DispatchQueue(
        label: "com.fantomsuj.Perch.context-suggestions.accessibility",
        qos: .utility
    )

    func requestAccess() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func start() {
        guard !isMonitoring else { return }
        guard isAuthorized else {
            onAuthorizationChange?(false)
            return
        }
        isMonitoring = true
        onAuthorizationChange?(true)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateContext()
                self?.poll()
            }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        lastSnapshot = nil
        targetProcessIdentifier = nil
        readGeneration &+= 1
    }

    func captureExactPage(
        completion: @escaping @MainActor (ContextSnapshot?) -> Void
    ) {
        guard let source = captureSourceIdentity() else {
            completion(nil)
            return
        }
        captureExactPage(from: source, completion: completion)
    }

    func captureSourceIdentity() -> ContextSourceIdentity? {
        guard isAuthorized,
              let application = NSWorkspace.shared.frontmostApplication,
              !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return nil
        }
        return ContextSourceIdentity(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier ?? "unknown",
            applicationName: application.localizedName ?? "Application"
        )
    }

    func captureExactPage(
        from source: ContextSourceIdentity,
        completion: @escaping @MainActor (ContextSnapshot?) -> Void
    ) {
        guard isAuthorized,
              source.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            completion(nil)
            return
        }
        let reader = reader
        workerQueue.async {
            let snapshot = reader.readExactPage(source: source)
            Task { @MainActor in
                let runningApplication = source.processIdentifier.flatMap(
                    NSRunningApplication.init(processIdentifier:)
                )
                guard AccessibilityContextSourceValidation.acceptsResult(
                    source: source,
                    runningProcessIdentifier: runningApplication?.processIdentifier,
                    runningBundleIdentifier: runningApplication?.bundleIdentifier,
                    isTerminated: runningApplication?.isTerminated ?? true
                ), AXIsProcessTrusted()
                else {
                    completion(nil)
                    return
                }
                completion(snapshot)
            }
        }
    }

    private func poll() {
        guard isMonitoring else { return }
        guard isAuthorized else {
            stop()
            onAuthorizationChange?(false)
            return
        }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            invalidateContext()
            return
        }

        let processIdentifier = application.processIdentifier
        if targetProcessIdentifier != processIdentifier {
            invalidateContext()
            targetProcessIdentifier = processIdentifier
        }
        guard !isReadInFlight else { return }
        isReadInFlight = true
        readGeneration &+= 1
        let generation = readGeneration
        let bundleIdentifier = application.bundleIdentifier ?? "unknown"
        let applicationName = application.localizedName ?? "Application"
        let reader = reader
        workerQueue.async { [weak self] in
            let snapshot = reader.read(
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName
            )
            Task { @MainActor in
                guard let self else { return }
                self.isReadInFlight = false
                guard self.isMonitoring else { return }
                guard self.readGeneration == generation,
                      self.targetProcessIdentifier == processIdentifier
                else {
                    self.poll()
                    return
                }
                self.publish(snapshot)
            }
        }
    }

    private func invalidateContext() {
        targetProcessIdentifier = nil
        readGeneration &+= 1
        publish(nil)
    }

    private func publish(_ snapshot: ContextSnapshot?) {
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        onSnapshot?(snapshot)
    }
}

private struct AccessibilityContextReader: Sendable {
    func read(
        processIdentifier: pid_t,
        bundleIdentifier: String,
        applicationName: String
    ) -> ContextSnapshot? {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard let focusedElement = elementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: applicationElement
        ) else { return nil }
        let role = stringAttribute(kAXRoleAttribute as CFString, from: focusedElement)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: focusedElement)
        guard !AccessibilityContextSecurityPolicy.isSecure(role: role, subrole: subrole),
              let focusedWindow = elementAttribute(
                  kAXFocusedWindowAttribute as CFString,
                  from: applicationElement
              )
        else { return nil }

        let windowTitle = stringAttribute(kAXTitleAttribute as CFString, from: focusedWindow)
        let documentValue = stringAttribute(
            kAXDocumentAttribute as CFString,
            from: focusedWindow
        )
        return ContextSnapshot(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            windowTitle: windowTitle,
            documentURL: documentValue.flatMap(URL.init(string:)),
            sourceProcessIdentifier: processIdentifier
        )
    }

    func readExactPage(source: ContextSourceIdentity) -> ContextSnapshot? {
        guard let processIdentifier = source.processIdentifier else { return nil }
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard let focusedElement = elementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: applicationElement
        ) else { return nil }
        guard let focusedWindow = elementAttribute(
            kAXFocusedWindowAttribute as CFString,
            from: applicationElement
        )
        else { return nil }

        var candidateValues = urlAttributeValues(from: focusedWindow)
        var element: AXUIElement? = focusedElement
        for _ in 0 ..< 4 {
            guard let currentElement = element else { break }
            candidateValues.append(contentsOf: urlAttributeValues(from: currentElement))
            element = elementAttribute(kAXParentAttribute as CFString, from: currentElement)
        }
        return AccessibilityExactPageContextResolver.snapshot(
            source: source,
            urlAttributeValues: candidateValues
        )
    }

    private func urlAttributeValues(from element: AXUIElement) -> [String] {
        [
            urlStringAttribute(kAXDocumentAttribute as CFString, from: element),
            urlStringAttribute(kAXURLAttribute as CFString, from: element),
        ].compactMap { $0 }
    }

    private func elementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // The Core Foundation type check above establishes this bridge invariant.
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func stringAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let string = value as? String
        else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func urlStringAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value
        else { return nil }
        let rawValue: String?
        if let url = value as? URL {
            rawValue = url.absoluteString
        } else {
            rawValue = value as? String
        }
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

enum AccessibilityContextSourceValidation {
    static func acceptsResult(
        source: ContextSourceIdentity,
        runningProcessIdentifier: pid_t?,
        runningBundleIdentifier: String?,
        isTerminated: Bool
    ) -> Bool {
        guard !isTerminated,
              let sourceProcessIdentifier = source.processIdentifier,
              runningProcessIdentifier == sourceProcessIdentifier,
              runningBundleIdentifier == source.bundleIdentifier
        else {
            return false
        }
        return true
    }
}

enum AccessibilityContextSecurityPolicy {
    static func isSecure(role: String?, subrole: String?) -> Bool {
        subrole == (kAXSecureTextFieldSubrole as String)
            || role?.localizedCaseInsensitiveContains("secure") == true
    }
}
