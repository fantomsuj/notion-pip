import Carbon.HIToolbox
import Foundation

enum FlipShortcutRegistrationError: Error, Equatable {
    case eventHandler(OSStatus)
    case hotKey(OSStatus)
}

@MainActor
protocol FlipShortcutRegistering: AnyObject {
    func register(shortcut: FlipShortcut, handler: @escaping @MainActor () -> Void) throws
    func unregister()
}

@MainActor
final class CarbonFlipShortcutRegistrar: FlipShortcutRegistering {
    private static let signature: OSType = 0x464C_4950
    private static var nextRegistrationID: UInt32 = 1

    private var eventHandlerReference: EventHandlerRef?
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandler: (@MainActor () -> Void)?
    private let registrationID: EventHotKeyID

    init() {
        registrationID = EventHotKeyID(
            signature: Self.signature,
            id: Self.nextRegistrationID
        )
        Self.nextRegistrationID &+= 1
        if Self.nextRegistrationID == 0 {
            Self.nextRegistrationID = 1
        }
    }

    func register(shortcut: FlipShortcut, handler: @escaping @MainActor () -> Void) throws {
        guard shortcut.isValid else {
            throw FlipShortcutRegistrationError.hotKey(OSStatus(paramErr))
        }
        unregister()
        eventHandler = handler
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
            eventHandler = nil
            throw FlipShortcutRegistrationError.eventHandler(eventHandlerStatus)
        }

        let hotKeyStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            registrationID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard hotKeyStatus == noErr else {
            unregister()
            throw FlipShortcutRegistrationError.hotKey(hotKeyStatus)
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
        eventHandler = nil
    }

    private func invokeHandler() {
        eventHandler?()
    }

    func accepts(eventHotKeyID: EventHotKeyID) -> Bool {
        eventHotKeyID.signature == registrationID.signature
            && eventHotKeyID.id == registrationID.id
    }

    private static let hotKeyEventHandler: EventHandlerUPP = { _, eventReference, userData in
        guard let eventReference, let userData else { return OSStatus(eventNotHandledErr) }
        let registrar = Unmanaged<CarbonFlipShortcutRegistrar>.fromOpaque(userData)
            .takeUnretainedValue()
        var eventHotKeyID = EventHotKeyID()
        let identityStatus = GetEventParameter(
            eventReference,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyID
        )
        guard identityStatus == noErr, registrar.accepts(eventHotKeyID: eventHotKeyID) else {
            return OSStatus(eventNotHandledErr)
        }
        Task { @MainActor in
            registrar.invokeHandler()
        }
        return noErr
    }
}
