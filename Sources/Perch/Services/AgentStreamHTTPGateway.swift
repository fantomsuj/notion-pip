import Foundation

/// Async MainActor bridge so the loopback HTTP server never touches
/// `AgentStreamController` types from Network.framework queues directly.
protocol AgentStreamHTTPServing: Sendable {
    func status() async -> AgentStreamServerStatus
    func create(_ request: AgentStreamCreateRequest) async throws -> AgentStreamCreateResult
    func append(streamID: UUID, chunk: AgentStreamChunk) async throws -> AgentStreamSnapshot
    func complete(streamID: UUID) async throws -> AgentStreamSnapshot
    func cancel(streamID: UUID) async throws -> AgentStreamSnapshot
    func stream(id: UUID) async throws -> AgentStreamSnapshot
}

actor AgentStreamHTTPGateway: AgentStreamHTTPServing {
    private let controller: AgentStreamController

    init(controller: AgentStreamController) {
        self.controller = controller
    }

    func status() async -> AgentStreamServerStatus {
        await MainActor.run {
            controller.status()
        }
    }

    func create(_ request: AgentStreamCreateRequest) async throws -> AgentStreamCreateResult {
        try await MainActor.run {
            try controller.create(request)
        }
    }

    func append(
        streamID: UUID,
        chunk: AgentStreamChunk
    ) async throws -> AgentStreamSnapshot {
        try await MainActor.run {
            try controller.append(streamID: streamID, chunk: chunk)
        }
    }

    func complete(streamID: UUID) async throws -> AgentStreamSnapshot {
        try await MainActor.run {
            try controller.complete(streamID: streamID)
        }
    }

    func cancel(streamID: UUID) async throws -> AgentStreamSnapshot {
        try await MainActor.run {
            try controller.cancel(streamID: streamID)
        }
    }

    func stream(id: UUID) async throws -> AgentStreamSnapshot {
        try await MainActor.run {
            try controller.stream(id: id)
        }
    }
}
