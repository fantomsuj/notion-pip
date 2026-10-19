import Foundation
import Network
import OSLog
import Security

actor AgentStreamHTTPServer {
    struct StartResult: Equatable, Sendable {
        let record: AgentStreamDiscoveryRecord
        let port: UInt16
    }

    /// How long a client has to send a full request, and to accept the response.
    static let defaultConnectionTimeout: Duration = .seconds(5)
    /// Open connections allowed at once. Agents send one request per connection,
    /// so a handful is plenty; more are answered with 503 and closed.
    static let defaultMaxConcurrentConnections = 8

    private struct OpenConnection {
        let connection: NWConnection
        let task: Task<Void, Never>
    }

    private let gateway: any AgentStreamHTTPServing
    private let discoveryStore: AgentStreamDiscoveryStore
    private let limits: AgentStreamLimits
    private let processIdentifier: pid_t
    private let clock: @Sendable () -> Date
    private let tokenGenerator: @Sendable () -> String
    private let connectionTimeout: Duration
    private let maxConcurrentConnections: Int
    private let logger = Logger(
        subsystem: "com.fantomsuj.Perch",
        category: "agent-stream-http"
    )

    private var listener: NWListener?
    private var port: UInt16?
    private var token: String?
    private var startedAt: Date?
    private var isStopping = false
    private var openConnections: [UUID: OpenConnection] = [:]
    private var recentRequestTimestamps: [ContinuousClock.Instant] = []
    private var startContinuation: CheckedContinuation<StartResult, Error>?

    init(
        gateway: any AgentStreamHTTPServing,
        discoveryStore: AgentStreamDiscoveryStore = AgentStreamDiscoveryStore(),
        limits: AgentStreamLimits = .default,
        processIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        clock: @escaping @Sendable () -> Date = { Date() },
        tokenGenerator: @escaping @Sendable () -> String = {
            AgentStreamHTTPServer.makeToken()
        },
        connectionTimeout: Duration = AgentStreamHTTPServer.defaultConnectionTimeout,
        maxConcurrentConnections: Int = AgentStreamHTTPServer.defaultMaxConcurrentConnections
    ) {
        self.gateway = gateway
        self.discoveryStore = discoveryStore
        self.limits = limits
        self.processIdentifier = processIdentifier
        self.clock = clock
        self.tokenGenerator = tokenGenerator
        self.connectionTimeout = connectionTimeout
        self.maxConcurrentConnections = max(1, maxConcurrentConnections)
    }

    var isRunning: Bool {
        listener != nil && token != nil && port != nil
    }

    var publishedPort: UInt16? {
        port
    }

    /// Number of connections currently being served. Exposed for tests.
    var openConnectionCount: Int {
        openConnections.count
    }

    func start() async throws -> StartResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StartResult, Error>) in
            let token = tokenGenerator()
            let startedAt = clock()

            if listener != nil || startContinuation != nil {
                continuation.resume(
                    throwing: AgentStreamError.invalidRequest(
                        "Agent stream HTTP server is already running."
                    )
                )
                return
            }

            isStopping = false
            self.token = token
            self.startedAt = startedAt
            startContinuation = continuation

            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host("127.0.0.1"),
                    port: .any
                )
                parameters.acceptLocalOnly = true

                let newListener = try NWListener(using: parameters, on: .any)
                listener = newListener

                newListener.newConnectionHandler = { connection in
                    Task { await self.accept(connection) }
                }

                newListener.stateUpdateHandler = { listenerState in
                    Task {
                        await self.handleListenerState(
                            listenerState,
                            listener: newListener,
                            token: token,
                            startedAt: startedAt
                        )
                    }
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

    /// Stops the listener and closes every open connection.
    ///
    /// Returns promptly even when a client holds a socket open without sending
    /// anything: each connection is cancelled directly, which wakes any
    /// `receive` or `send` parked on it. Cancelling the Swift task alone would
    /// not, because `NWConnection` callbacks ignore task cancellation.
    func stop() async {
        isStopping = true
        let token = self.token
        let listener = self.listener
        let open = Array(openConnections.values)
        openConnections.removeAll()
        self.listener = nil
        port = nil
        self.token = nil
        startedAt = nil
        if let continuation = startContinuation {
            startContinuation = nil
            continuation.resume(throwing: CancellationError())
        }

        listener?.cancel()
        for entry in open {
            entry.connection.cancel()
            entry.task.cancel()
        }
        for entry in open {
            _ = await entry.task.result
        }

        if let token {
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
        // A stopped listener reports `.cancelled` asynchronously. If the server
        // was restarted in the meantime, that late callback belongs to the old
        // listener and must not clear the new one's port and token.
        guard listener === self.listener else { return }

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
                port = boundPort
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
        case .failed:
            logger.error("Agent stream listener failed")
            clearListenerState()
            resumeStart(.failure(AgentStreamError.invalidRequest("Listener failed.")))
        case .cancelled:
            clearListenerState()
            resumeStart(.failure(CancellationError()))
        default:
            break
        }
    }

    private func resumeStart(_ result: Result<StartResult, Error>) {
        let continuation = startContinuation
        startContinuation = nil
        continuation?.resume(with: result)
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        guard !isStopping,
              let port,
              let token
        else {
            connection.cancel()
            return
        }

        guard isLoopbackConnection(connection) else {
            connection.cancel()
            return
        }

        guard openConnections.count < maxConcurrentConnections else {
            connection.start(queue: Self.connectionQueue())
            Self.closeConnection(
                connection,
                replyingWith: AgentStreamHTTPCodec.encodeErrorResponse(.serverBusy())
            )
            return
        }

        let connectionID = UUID()
        let task = Task {
            await self.handleConnection(
                connection,
                expectedPort: port,
                expectedToken: token
            )
            self.openConnections[connectionID] = nil
        }
        openConnections[connectionID] = OpenConnection(
            connection: connection,
            task: task
        )
    }

    private func handleConnection(
        _ connection: NWConnection,
        expectedPort: UInt16,
        expectedToken: String
    ) async {
        connection.start(queue: Self.connectionQueue())

        defer {
            connection.cancel()
        }

        do {
            let buffer: Data
            do {
                // A client that connects and goes quiet gets a 408 and is closed.
                let timeout = Self.scheduleTimeout(
                    for: connection,
                    after: connectionTimeout,
                    replyingWith: AgentStreamHTTPCodec.encodeErrorResponse(.requestTimeout())
                )
                defer { timeout.cancel() }
                buffer = try await readRequestBuffer(from: connection)
            }

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
                responseData = await respond(
                    to: request,
                    expectedToken: expectedToken
                )
            }
            try await sendWithTimeout(responseData, on: connection)
        } catch let error as AgentStreamError {
            // Rejected while reading (for example, too large): answer before closing.
            try? await sendWithTimeout(
                AgentStreamHTTPCodec.encodeErrorResponse(error),
                on: connection
            )
        } catch {
            // Connection dropped, timed out, or the server stopped.
            // Never log request bodies or tokens.
            logger.debug("Agent stream connection closed before completion")
        }
    }

    /// Checks the token first, so only callers that hold it spend the shared
    /// rate limit. Unauthenticated noise from other local processes can't push
    /// the real agent into 429s.
    private func respond(
        to request: AgentStreamHTTPParsedRequest,
        expectedToken: String
    ) async -> Data {
        guard let bearer = request.authorizationBearer,
              AgentStreamHTTPCodec.tokensMatch(bearer, expectedToken)
        else {
            return AgentStreamHTTPCodec.encodeErrorResponse(.unauthorized())
        }

        guard consumeRateLimitSlot() else {
            return AgentStreamHTTPCodec.encodeErrorResponse(.rateLimited())
        }

        return await dispatch(request)
    }

    private func dispatch(_ request: AgentStreamHTTPParsedRequest) async -> Data {
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
                    object: AgentStreamHTTPCodec.StreamAckDTO(
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
                    object: AgentStreamHTTPCodec.StreamAckDTO(snapshot)
                )

            case .complete(let id):
                let snapshot = try await gateway.complete(streamID: id)
                return try AgentStreamHTTPCodec.encodeJSONResponse(
                    status: 200,
                    reason: "OK",
                    object: AgentStreamHTTPCodec.StreamAckDTO(snapshot)
                )

            case .cancel(let id):
                let snapshot = try await gateway.cancel(streamID: id)
                return try AgentStreamHTTPCodec.encodeJSONResponse(
                    status: 200,
                    reason: "OK",
                    object: AgentStreamHTTPCodec.StreamAckDTO(snapshot)
                )

            case .getStream(let id):
                let snapshot = try await gateway.stream(id: id)
                return try AgentStreamHTTPCodec.encodeJSONResponse(
                    status: 200,
                    reason: "OK",
                    object: AgentStreamHTTPCodec.StreamAckDTO(snapshot)
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

    /// Reads until a full request is buffered, the peer closes, or the request
    /// fails to decode. The caller bounds how long this may take.
    private func readRequestBuffer(from connection: NWConnection) async throws -> Data {
        var buffer = Data()

        while true {
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

    private func sendWithTimeout(_ data: Data, on connection: NWConnection) async throws {
        // A client that stops reading can't hold the connection open forever.
        let timeout = Self.scheduleTimeout(
            for: connection,
            after: connectionTimeout,
            replyingWith: nil
        )
        defer { timeout.cancel() }
        try await send(data, on: connection)
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

    /// Closes `connection` once `timeout` passes, unless the returned task is
    /// cancelled first. Cancelling the connection is what wakes a pending
    /// `receive` or `send`; task cancellation alone does not.
    private nonisolated static func scheduleTimeout(
        for connection: NWConnection,
        after timeout: Duration,
        replyingWith reply: Data?
    ) -> Task<Void, Never> {
        Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            closeConnection(connection, replyingWith: reply)
        }
    }

    /// Sends `reply` (if any) and then cancels the connection. The connection
    /// is cancelled within a second even if the reply never drains.
    private nonisolated static func closeConnection(
        _ connection: NWConnection,
        replyingWith reply: Data?
    ) {
        guard let reply else {
            connection.cancel()
            return
        }
        connection.send(
            content: reply,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            connection.cancel()
        }
    }

    private nonisolated static func connectionQueue() -> DispatchQueue {
        DispatchQueue(
            label: "com.fantomsuj.Perch.agent-stream-http.connection",
            qos: .userInitiated
        )
    }

    // MARK: - Helpers

    private func consumeRateLimitSlot() -> Bool {
        let now = ContinuousClock.now
        let window = Duration.seconds(1)
        recentRequestTimestamps.removeAll { now - $0 >= window }
        if recentRequestTimestamps.count >= limits.maxRequestsPerSecond {
            return false
        }
        recentRequestTimestamps.append(now)
        return true
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
        listener = nil
        port = nil
        token = nil
        startedAt = nil
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
