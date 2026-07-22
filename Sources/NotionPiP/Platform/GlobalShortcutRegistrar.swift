import Carbon.HIToolbox

enum GlobalShortcutRegistrationError: Error, Equatable {
    case eventHandler(OSStatus)
    case hotKey(OSStatus)
}

@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    func register(handler: @escaping @MainActor () -> Void) throws
    func unregister()
}

@MainActor
final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private var eventHandlerReference: EventHandlerRef?
    private var hotKeyReference: EventHotKeyRef?
    private var handler: (@MainActor () -> Void)?

    init(
        keyCode: UInt32 = UInt32(kVK_ANSI_P),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey)
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    func register(handler: @escaping @MainActor () -> Void) throws {
        guard hotKeyReference == nil else {
            return
        }

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
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard hotKeyStatus == noErr else {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
            }
            eventHandlerReference = nil
            self.handler = nil
            throw GlobalShortcutRegistrationError.hotKey(hotKeyStatus)
        }
    }

    func unregister() {
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
        guard let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let registrar = Unmanaged<CarbonGlobalShortcutRegistrar>
            .fromOpaque(userData)
            .takeUnretainedValue()
        Task { @MainActor in
            registrar.invokeHandler()
        }
        return noErr
    }
}
