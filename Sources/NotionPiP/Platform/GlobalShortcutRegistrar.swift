import Carbon.HIToolbox

enum GlobalShortcutRegistrationError: Error, Equatable {
    case eventHandler(OSStatus)
    case hotKey(OSStatus)
}

@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    func register(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws
    func unregister()
}

@MainActor
protocol GlobalShortcutRegistrationEngine: AnyObject {
    func install(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws
    func uninstall()
}

@MainActor
final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {
    private let engine: any GlobalShortcutRegistrationEngine
    private var registeredShortcut: GlobalShortcut?
    private var handler: (@MainActor () -> Void)?

    init(engine: any GlobalShortcutRegistrationEngine = CarbonEventHotKeyEngine()) {
        self.engine = engine
    }

    func register(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        guard shortcut.isValid else {
            throw GlobalShortcutRegistrationError.hotKey(OSStatus(paramErr))
        }
        if registeredShortcut == shortcut {
            self.handler = handler
            return
        }

        let previousShortcut = registeredShortcut
        let previousHandler = self.handler
        unregister()

        do {
            try engine.install(shortcut: shortcut, handler: handler)
            registeredShortcut = shortcut
            self.handler = handler
        } catch {
            if let previousShortcut, let previousHandler {
                try? engine.install(shortcut: previousShortcut, handler: previousHandler)
                registeredShortcut = previousShortcut
                self.handler = previousHandler
            }
            throw error
        }
    }

    func unregister() {
        guard registeredShortcut != nil else { return }
        engine.uninstall()
        registeredShortcut = nil
        handler = nil
    }
}

@MainActor
private final class CarbonEventHotKeyEngine: GlobalShortcutRegistrationEngine {
    private var eventHandlerReference: EventHandlerRef?
    private var hotKeyReference: EventHotKeyRef?
    private var handler: (@MainActor () -> Void)?

    func install(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        self.handler = handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let eventHandlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard eventHandlerStatus == noErr else {
            self.handler = nil
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
        handler = nil
    }

    private func invokeHandler() {
        handler?()
    }

    private static let hotKeyEventHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let engine = Unmanaged<CarbonEventHotKeyEngine>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in
            engine.invokeHandler()
        }
        return noErr
    }
}
