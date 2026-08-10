import AppKit

@MainActor
struct StatusItemEventRouter {
    let onMenu: () -> Void

    func handle(eventType: NSEvent.EventType) {
        switch eventType {
        case .leftMouseUp, .rightMouseUp:
            onMenu()
        default:
            break
        }
    }
}
