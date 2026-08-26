import Foundation

@MainActor
final class AgentStreamNotifierNoOp: AgentStreamNotifying {
    func notifyStreamReady(label: String, streamID: UUID) {}
    func clearStreamNotifications() {}
}
