import Carbon.HIToolbox

enum GlobalShortcutRegistrationError: Error, Equatable {
    case eventHandler(OSStatus)
    case hotKey(OSStatus)
}

enum GlobalShortcutEvent: Equatable, Sendable {
    case pressed
    case released
}

@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    func register(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws
    func register(
        shortcut: GlobalShortcut,
        eventHandler: @escaping @MainActor (GlobalShortcutEvent) -> Void
    ) throws
    func unregister()
}

extension GlobalShortcutRegistering {
    func register(
        shortcut: GlobalShortcut,
        eventHandler: @escaping @MainActor (GlobalShortcutEvent) -> Void
    ) throws {
        try register(shortcut: shortcut) {
            eventHandler(.pressed)
            eventHandler(.released)
        }
    }
}

@MainActor
protocol GlobalShortcutRegistrationEngine: AnyObject {
    func install(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws
    func install(
        shortcut: GlobalShortcut,
        handler: @escaping @MainActor (GlobalShortcutEvent) -> Void
    ) throws
    func uninstall()
}

extension GlobalShortcutRegistrationEngine {
    func install(
        shortcut: GlobalShortcut,
        handler: @escaping @MainActor (GlobalShortcutEvent) -> Void
    ) throws {
        try install(shortcut: shortcut) { handler(.pressed) }
    }
}

@MainActor
final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {
    private let engine: any GlobalShortcutRegistrationEngine
    private var registeredShortcut: GlobalShortcut?
    private var eventHandler: (@MainActor (GlobalShortcutEvent) -> Void)?

    init(engine: any GlobalShortcutRegistrationEngine = CarbonEventHotKeyEngine()) {
        self.engine = engine
    }

    func register(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        try register(shortcut: shortcut) { event in
            guard event == .pressed else { return }
            handler()
        }
    }

    func register(
        shortcut: GlobalShortcut,
        eventHandler: @escaping @MainActor (GlobalShortcutEvent) -> Void
    ) throws {
        guard shortcut.isValid else {
            throw GlobalShortcutRegistrationError.hotKey(OSStatus(paramErr))
        }
        if registeredShortcut == shortcut {
            self.eventHandler = eventHandler
            return
        }

        let previousShortcut = registeredShortcut
        let previousHandler = self.eventHandler
        unregister()

        do {
            self.eventHandler = eventHandler
            try installEngine(shortcut: shortcut)
            registeredShortcut = shortcut
        } catch {
            if let previousShortcut, let previousHandler {
                self.eventHandler = previousHandler
                try? installEngine(shortcut: previousShortcut)
                registeredShortcut = previousShortcut
            }
            throw error
        }
    }

    func unregister() {
        guard registeredShortcut != nil else { return }
        engine.uninstall()
        registeredShortcut = nil
        eventHandler = nil
    }

    private func installEngine(shortcut: GlobalShortcut) throws {
        try engine.install(shortcut: shortcut) { [weak self] event in
            self?.eventHandler?(event)
        }
    }
}

@MainActor
private final class CarbonEventHotKeyEngine: GlobalShortcutRegistrationEngine {
    private var eventHandlerReference: EventHandlerRef?
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandler: (@MainActor (GlobalShortcutEvent) -> Void)?

    func install(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        try install(shortcut: shortcut) { event in
            guard event == .pressed else { return }
            handler()
        }
    }

    func install(
        shortcut: GlobalShortcut,
        handler: @escaping @MainActor (GlobalShortcutEvent) -> Void
    ) throws {
        eventHandler = handler
        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let eventHandlerStatus = eventTypes.withUnsafeBufferPointer { eventTypes in
            InstallEventHandler(
                GetApplicationEventTarget(),
                Self.hotKeyEventHandler,
                eventTypes.count,
                eventTypes.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerReference
            )
        }
        guard eventHandlerStatus == noErr else {
            eventHandler = nil
            throw GlobalShortcutRegistrationError.eventHandler(eventHandlerStatus)
        }

        let hotKeyID = EventHotKeyID(signature: 0x4E50_4950, id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard hotKeyStatus == noErr else {
            uninstall()
            throw GlobalShortcutRegistrationError.hotKey(hotKeyStatus)
        }
    }

    func uninstall() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
        hotKeyReference = nil
        eventHandlerReference = nil
        eventHandler = nil
    }

    private func invokeHandler(for event: GlobalShortcutEvent) {
        eventHandler?(event)
    }

    private static let hotKeyEventHandler: EventHandlerUPP = { _, eventReference, userData in
        guard let eventReference, let userData else { return OSStatus(eventNotHandledErr) }
        let engine = Unmanaged<CarbonEventHotKeyEngine>.fromOpaque(userData).takeUnretainedValue()
        let event: GlobalShortcutEvent
        switch GetEventKind(eventReference) {
        case UInt32(kEventHotKeyPressed): event = .pressed
        case UInt32(kEventHotKeyReleased): event = .released
        default: return OSStatus(eventNotHandledErr)
        }
        Task { @MainActor in
            engine.invokeHandler(for: event)
        }
        return noErr
    }
}
