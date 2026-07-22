import AppKit

@MainActor
struct StatusItemEventRouter {
    let onRegularClick: () -> Void
    let onMenu: () -> Void

    func handle(eventType: NSEvent.EventType) {
        switch eventType {
        case .leftMouseUp:
            onRegularClick()
        case .rightMouseUp:
            onMenu()
        default:
            break
        }
    }
}
