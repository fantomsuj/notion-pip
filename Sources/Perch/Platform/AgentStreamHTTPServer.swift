import Foundation
import Network
import OSLog
import Security
import os

final class AgentStreamHTTPServer: @unchecked Sendable {
    struct StartResult: Equatable, Sendable {
        let record: AgentStreamDiscoveryRecord
        let port: UInt16
    }

    private struct State {
        var listener: NWListener?
        var port: UInt16?
        var token: String?
        var startedAt: Date?
        var isStopping = false
        var connectionTasks: [UUID: Task<Void, Never>] = [:]
        var recentRequestTimestamps: [ContinuousClock.Instant] = []
        var startContinuation: CheckedContinuation<StartResult, Error>?
    }

    private let gateway: any AgentStreamHTTPServing
    private let discoveryStore: AgentStreamDiscoveryStore
    private let limits: AgentStreamLimits
    private let processIdentifier: pid_t
    private let clock: @Sendable () -> Date
    private let tokenGenerator: @Sendable () -> String
    private let logger = Logger(
        subsystem: "com.fantomsuj.Perch",
        category: "agent-stream-http"
    )
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        gateway: any AgentStreamHTTPServing,
        discoveryStore: AgentStreamDiscoveryStore = AgentStreamDiscoveryStore(),
        limits: AgentStreamLimits = .default,
        processIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        clock: @escaping @Sendable () -> Date = { Date() },
        tokenGenerator: @escaping @Sendable () -> String = {
            AgentStreamHTTPServer.makeToken()
        }
    ) {
        self.gateway = gateway
        self.discoveryStore = discoveryStore
        self.limits = limits
        self.processIdentifier = processIdentifier
        self.clock = clock
        self.tokenGenerator = tokenGenerator
    }

    var isRunning: Bool {
        state.withLock { state in
            state.listener != nil && state.token != nil && state.port != nil
        }
    }

    var publishedPort: UInt16? {
        state.withLock { $0.port }
    }

    func start() async throws -> StartResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StartResult, Error>) in
            let token = tokenGenerator()
            let startedAt = clock()

            let shouldStart: Bool = state.withLock { state in
                if state.listener != nil || state.startContinuation != nil {
                    return false
                }
                state.isStopping = false
                state.token = token
                state.startedAt = startedAt
                state.startContinuation = continuation
                return true
            }

            guard shouldStart else {
                continuation.resume(
                    throwing: AgentStreamError.invalidRequest(
                        "Agent stream HTTP server is already running."
                    )
                )
                return
            }

            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host("127.0.0.1"),
                    port: .any
                )
                parameters.acceptLocalOnly = true

                let newListener = try NWListener(using: parameters, on: .any)
                state.withLock { state in
                    state.listener = newListener
                }

                newListener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }

                newListener.stateUpdateHandler = { [weak self] listenerState in
                    guard let self else { return }
                    self.handleListenerState(
                        listenerState,
                        listener: newListener,
                        token: token,
                        startedAt: startedAt
                    )
                }

                newListener.start(queue: DispatchQueue(
                    label: "com.fantomsuj.Perch.agent-stream-http",
                    qos: .userInitiated
                ))
            } catch {
                resumeStart(.failure(error))
                clearListenerState()
            }
        }
    }

    func stop() async {
        let snapshot: (
            token: String?,
            listener: NWListener?,
            tasks: [Task<Void, Never>]
        ) = state.withLock { state in
            state.isStopping = true
            let token = state.token
            let listener = state.listener
            let tasks = Array(state.connectionTasks.values)
            state.connectionTasks.removeAll()
            state.listener = nil
            state.port = nil
            state.token = nil
            state.startedAt = nil
            if let continuation = state.startContinuation {
                state.startContinuation = nil
                continuation.resume(
                    throwing: CancellationError()
                )
            }
            return (token, listener, tasks)
        }

        snapshot.listener?.cancel()
        for task in snapshot.tasks {
            task.cancel()
        }
        for task in snapshot.tasks {
            _ = await task.result
        }

        if let token = snapshot.token {
            do {
                try discoveryStore.removeIfMatches(
                    pid: processIdentifier,
                    token: token
                )
            } catch {
                logger.error("Failed to remove agent stream discovery file")
            }
        }
    }

    // MARK: - Listener lifecycle

    private func handleListenerState(
        _ listenerState: NWListener.State,
        listener: NWListener,
        token: String,
        startedAt: Date
    ) {
        switch listenerState {
        case .ready:
            guard let nwPort = listener.port else {
                resumeStart(
                    .failure(
                        AgentStreamError.invalidRequest(
                            "Listener became ready without a port."
                        )
                    )
                )
                clearListenerState()
                return
            }
            let boundPort = nwPort.rawValue
            do {
                let record = AgentStreamDiscoveryRecord(
                    baseURL: "http://127.0.0.1:\(boundPort)/v1",
                    token: token,
                    pid: processIdentifier,
                    startedAt: startedAt
                )
                try discoveryStore.publish(record)
                state.withLock { state in
                    state.port = boundPort
                }
                logger.info(
                    "Agent stream listener ready on loopback port \(boundPort, privacy: .public)"
                )
                resumeStart(.success(StartResult(record: record, port: boundPort)))
            } catch {
                logger.error("Failed to publish agent stream discovery file")
                listener.cancel()
                clearListenerState()
                resumeStart(.failure(error))
            }
        case .failed(let error):
            logger.error("Agent stream listener failed")
            clearListenerState()
            resumeStart(.failure(error))
        case .cancelled:
            clearListenerState()
            resumeStart(.failure(CancellationError()))
        default:
            break
        }
    }

    private func resumeStart(_ result: Result<StartResult, Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<StartResult, Error>? in
            let value = state.startContinuation
            state.startContinuation = nil
            return value
        }
        continuation?.resume(with: result)
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let credentials: (port: UInt16, token: String)? = state.withLock { state in
            guard !state.isStopping,
                  let port = state.port,
                  let token = state.token
            else {
                return nil
            }
            return (port, token)
        }

        guard let credentials else {
            connection.cancel()
            return
        }

        guard isLoopbackConnection(connection) else {
            connection.cancel()
            return
        }

        let taskID = UUID()
        let task = Task { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }
            await self.handleConnection(
                connection,
                expectedPort: credentials.port,
                expectedToken: credentials.token
            )
            self.state.withLock { state in
                state.connectionTasks[taskID] = nil
            }
        }
        state.withLock { state in
            state.connectionTasks[taskID] = task
        }
    }

    private func handleConnection(
        _ connection: NWConnection,
        expectedPort: UInt16,
        expectedToken: String
    ) async {
        connection.start(queue: DispatchQueue(
            label: "com.fantomsuj.Perch.agent-stream-http.connection",
            qos: .userInitiated
        ))

        defer {
            connection.cancel()
        }

        do {
            if !consumeRateLimitSlot() {
                let response = AgentStreamHTTPCodec.encodeErrorResponse(.rateLimited())
                try await send(response, on: connection)
                return
            }

            let buffer = try await readRequestBuffer(from: connection)
            let outcome = AgentStreamHTTPCodec.decodeRequest(
                from: buffer,
                limits: limits,
                expectedHostPort: expectedPort
            )

            let responseData: Data
            switch outcome {
            case .needMoreData:
                responseData = AgentStreamHTTPCodec.encodeErrorResponse(
                    .invalidRequest("Incomplete HTTP request.")
                )
            case .failure(_, let error):
                responseData = AgentStreamHTTPCodec.encodeErrorResponse(error)
            case .request(let request):
                responseData = await dispatch(
                    request,
                    expectedToken: expectedToken
                )
            }
            try await send(responseData, on: connection)
        } catch {
            // Connection dropped or timed out; never log request bodies or tokens.
            logger.debug("Agent stream connection closed before completion")
        }
    }

    private func dispatch(
        _ request: AgentStreamHTTPParsedRequest,
        expectedToken: String
    ) async -> Data {
        guard let bearer = request.authorizationBearer,
              AgentStreamHTTPCodec.tokensMatch(bearer, expectedToken)
        else {
            return AgentStreamHTTPCodec.encodeErrorResponse(.unauthorized())
        }

        do {
            switch request.route {
            case .status:
                let status = await gateway.status()
                return try AgentStreamHTTPCodec.encodeJSONResponse(
                    status: 200,
                    reason: "OK",
                    object: AgentStreamHTTPCodec.StatusDTO(status)
                )

            case .createStream:
                guard let idempotencyKey = request.idempotencyKey?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !idempotencyKey.isEmpty
                else {
                    throw AgentStreamError.invalidRequest("Idempotency-Key is required.")
                }
                let decoded = try AgentStreamHTTPCodec.decodeCreateBody(request.body)
                let createRequest = AgentStreamCreateRequest(
                    client: decoded.client,
                    label: decoded.label,
                    commitMode: decoded.commitMode,
                    contentType: decoded.contentType,
                    idempotencyKey: idempotencyKey
                )
                let result = try await gateway.create(createRequest)
                return try AgentStreamHTTPCodec.encodeJSONResponse(
                    status: 201,
                    reason: "Created",
                    object: AgentStreamHTTPCodec.StreamDTO(
                        result.snapshot,
                        limits: result.limits
                    )
                )

            case .appendChunk(let id):
                let chunk = try AgentStreamHTTPCodec.decodeChunkBody(request.body)
                let snapshot = try await gateway.append(streamID: id, chunk: chunk)
                return try AgentStreamHTTPCodec.encodeJSONResponse(
                    status: 200,
                    reason: "OK",
                    object: AgentStreamHTTPCodec.StreamDTO(snapshot)
                )

            case .complete(let id):
                let snapshot = try await gateway.complete(streamID: id)
                return try AgentStreamHTTPCodec.encodeJSONResponse(
                    status: 200,
                    reason: "OK",
                    object: AgentStreamHTTPCodec.StreamDTO(snapshot)
                )

            case .cancel(let id):
                let snapshot = try await gateway.cancel(streamID: id)
                return try AgentStreamHTTPCodec.encodeJSONResponse(
                    status: 200,
                    reason: "OK",
                    object: AgentStreamHTTPCodec.StreamDTO(snapshot)
                )

            case .getStream(let id):
                let snapshot = try await gateway.stream(id: id)
                return try AgentStreamHTTPCodec.encodeJSONResponse(
                    status: 200,
                    reason: "OK",
                    object: AgentStreamHTTPCodec.StreamDTO(snapshot)
                )
            }
        } catch let error as AgentStreamError {
            return AgentStreamHTTPCodec.encodeErrorResponse(error)
        } catch {
            return AgentStreamHTTPCodec.encodeErrorResponse(
                .invalidRequest("Request failed.")
            )
        }
    }

    // MARK: - IO

    private func readRequestBuffer(from connection: NWConnection) async throws -> Data {
        var buffer = Data()
        let deadline = ContinuousClock.now + Duration.seconds(5)

        while ContinuousClock.now < deadline {
            if Task.isCancelled {
                throw CancellationError()
            }

            let chunk = try await receiveChunk(from: connection, maximumLength: 8 * 1_024)
            if chunk.isEmpty {
                break
            }
            buffer.append(chunk)

            if buffer.count > limits.maxHeaderUTF8Bytes + limits.maxBodyUTF8Bytes {
                throw AgentStreamError.payloadTooLarge("Request exceeds size limits.")
            }

            let outcome = AgentStreamHTTPCodec.decodeRequest(
                from: buffer,
                limits: limits,
                expectedHostPort: nil
            )
            switch outcome {
            case .needMoreData:
                continue
            case .request, .failure:
                return buffer
            }
        }

        if buffer.isEmpty {
            throw AgentStreamError.invalidRequest("Empty request.")
        }
        return buffer
    }

    private func receiveChunk(
        from connection: NWConnection,
        maximumLength: Int
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: maximumLength
            ) { content, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let content {
                    continuation.resume(returning: Data(content))
                    return
                }
                if isComplete {
                    continuation.resume(returning: Data())
                    return
                }
                continuation.resume(returning: Data())
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    // MARK: - Helpers

    private func consumeRateLimitSlot() -> Bool {
        state.withLock { state in
            let now = ContinuousClock.now
            let window = Duration.seconds(1)
            state.recentRequestTimestamps.removeAll { now - $0 >= window }
            if state.recentRequestTimestamps.count >= limits.maxRequestsPerSecond {
                return false
            }
            state.recentRequestTimestamps.append(now)
            return true
        }
    }

    private func isLoopbackConnection(_ connection: NWConnection) -> Bool {
        switch connection.endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let address):
                return address == IPv4Address.loopback
            case .ipv6(let address):
                return address == IPv6Address.loopback
            case .name(let name, _):
                return name == "localhost" || name == "127.0.0.1" || name == "::1"
            @unknown default:
                return false
            }
        default:
            return false
        }
    }

    private func clearListenerState() {
        state.withLock { state in
            state.listener = nil
            state.port = nil
            state.token = nil
            state.startedAt = nil
        }
    }

    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Failed to generate agent stream token")
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
