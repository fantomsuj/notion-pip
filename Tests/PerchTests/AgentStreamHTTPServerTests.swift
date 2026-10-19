import Foundation
import XCTest
@testable import Perch

@MainActor
final class AgentStreamHTTPServerTests: XCTestCase {
    func testLoopbackServerCreateChunksCompleteAndGetFlows() async throws {
        try await withHarness { harness in
            let status = try await harness.getJSON(path: "/v1/status", method: "GET")
            XCTAssertEqual(status["ready"] as? Bool, true)

            let createBody =
                #"{"client":"cursor","label":"Cursor","commitMode":"accept_to_paste","contentType":"text/markdown"}"#
            let created = try await harness.getJSON(
                path: "/v1/streams",
                method: "POST",
                headers: ["Idempotency-Key": "create-1"],
                body: createBody,
                expectedStatus: 201
            )
            let streamID = try XCTUnwrap(created["id"] as? String)
            XCTAssertEqual(created["phase"] as? String, "receiving")
            XCTAssertEqual(created["nextSequence"] as? Int, 0)
            XCTAssertNil(created["assembledText"])
            XCTAssertNil(created["opaquePageID"])
            XCTAssertNil(created["canAccept"])
            XCTAssertNil(created["contentType"])
            XCTAssertNotNil(created["limits"])

            _ = try await harness.getJSON(
                path: "/v1/streams/\(streamID)/chunks",
                method: "POST",
                body: "{\"sequence\":0,\"text\":\"# Title\\n\"}"
            )
            let afterChunk = try await harness.getJSON(
                path: "/v1/streams/\(streamID)/chunks",
                method: "POST",
                body: "{\"sequence\":1,\"text\":\"body\"}"
            )
            XCTAssertEqual(afterChunk["nextSequence"] as? Int, 2)
            XCTAssertEqual(afterChunk["phase"] as? String, "receiving")
            XCTAssertNil(afterChunk["assembledText"])
            XCTAssertNil(afterChunk["opaquePageID"])

            let completed = try await harness.getJSON(
                path: "/v1/streams/\(streamID)/complete",
                method: "POST",
                body: "{}"
            )
            XCTAssertEqual(completed["phase"] as? String, "ready")
            XCTAssertNil(completed["canAccept"])
            XCTAssertNil(completed["assembledText"])
            XCTAssertEqual(harness.target.rememberCount, 0)
            XCTAssertEqual(harness.target.pasteCount, 0)

            let fetched = try await harness.getJSON(
                path: "/v1/streams/\(streamID)",
                method: "GET"
            )
            XCTAssertEqual(fetched["phase"] as? String, "ready")
            XCTAssertNil(fetched["assembledText"])
            XCTAssertNil(fetched["opaquePageID"])
        }
    }

    func testUnauthorizedAndOriginRejection() async throws {
        try await withHarness { harness in
            let unauthorized = try await harness.rawRequest(
                path: "/v1/status",
                method: "GET",
                token: "wrong-token"
            )
            XCTAssertEqual(unauthorized.status, 401)
            XCTAssertTrue(unauthorized.body.contains("unauthorized"))

            let origin = try await harness.rawRequest(
                path: "/v1/status",
                method: "GET",
                headers: ["Origin": "https://evil.example"]
            )
            XCTAssertEqual(origin.status, 403)
        }
    }

    func testSequenceMismatchReturnsExpectedSequence() async throws {
        try await withHarness { harness in
            let created = try await harness.getJSON(
                path: "/v1/streams",
                method: "POST",
                headers: ["Idempotency-Key": "seq-1"],
                body: #"{"client":"a","commitMode":"accept_to_paste","contentType":"text/markdown"}"#,
                expectedStatus: 201
            )
            let streamID = try XCTUnwrap(created["id"] as? String)

            let mismatch = try await harness.rawRequest(
                path: "/v1/streams/\(streamID)/chunks",
                method: "POST",
                body: #"{"sequence":2,"text":"nope"}"#
            )
            XCTAssertEqual(mismatch.status, 409)
            XCTAssertTrue(mismatch.body.contains("sequence_mismatch"))
            XCTAssertTrue(mismatch.body.contains("\"expectedSequence\":0"))
        }
    }

    func testCancelFlowAndDiscoveryCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let discoveryURL = directory.appendingPathComponent("agent-server.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let harness = try await makeHarness(discoveryURL: discoveryURL)
        do {
            let created = try await harness.getJSON(
                path: "/v1/streams",
                method: "POST",
                headers: ["Idempotency-Key": "cancel-1"],
                body: #"{"client":"a","commitMode":"accept_to_paste","contentType":"text/markdown"}"#,
                expectedStatus: 201
            )
            let streamID = try XCTUnwrap(created["id"] as? String)

            let cancelled = try await harness.getJSON(
                path: "/v1/streams/\(streamID)/cancel",
                method: "POST",
                body: "{}"
            )
            XCTAssertEqual(cancelled["phase"] as? String, "cancelled")
            XCTAssertTrue(FileManager.default.fileExists(atPath: discoveryURL.path))
        } catch {
            await harness.server.stop()
            throw error
        }
        await harness.server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: discoveryURL.path))
    }

    func testRateLimitReturns429() async throws {
        let limits = AgentStreamLimits(
            maxChunkUTF8Bytes: 32 * 1_024,
            maxAssembledUTF8Bytes: 512 * 1_024,
            maxHeaderUTF8Bytes: 16 * 1_024,
            maxBodyUTF8Bytes: 64 * 1_024,
            maxRequestsPerSecond: 3,
            inactiveExpiration: .seconds(600),
            terminalRetention: .seconds(600),
            readyRetention: .seconds(1_800)
        )
        try await withHarness(limits: limits) { harness in
            var sawRateLimit = false
            for _ in 0..<8 {
                let response = try await harness.rawRequest(
                    path: "/v1/status",
                    method: "GET"
                )
                if response.status == 429 {
                    sawRateLimit = true
                    XCTAssertTrue(response.body.contains("rate_limited"))
                    break
                }
            }
            XCTAssertTrue(sawRateLimit)
        }
    }

    func testStopReturnsPromptlyWithIdleConnection() async throws {
        // A long timeout proves stop() closes the socket itself instead of
        // waiting for the read timeout to fire.
        let harness = try await makeTemporaryHarness(connectionTimeout: .seconds(60))
        let socket = try RawSocket(port: harness.port)
        defer { socket.close() }
        try await waitForOpenConnections(1, on: harness.server)

        let started = ContinuousClock.now
        await harness.server.stop()
        let elapsed = ContinuousClock.now - started

        XCTAssertLessThan(elapsed, .seconds(2))
        let openAfterStop = await harness.server.openConnectionCount
        XCTAssertEqual(openAfterStop, 0)
        let running = await harness.server.isRunning
        XCTAssertFalse(running)
    }

    func testIdleConnectionGetsRequestTimeout() async throws {
        let harness = try await makeTemporaryHarness(connectionTimeout: .milliseconds(200))
        let socket = try RawSocket(port: harness.port)
        defer { socket.close() }

        let response = await socket.readUntilClosed()
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 408 "), response)
        XCTAssertTrue(response.contains("request_timeout"), response)
        try await waitForOpenConnections(0, on: harness.server)
        await harness.server.stop()
    }

    func testPartialRequestGetsRequestTimeout() async throws {
        let harness = try await makeTemporaryHarness(connectionTimeout: .milliseconds(200))
        let socket = try RawSocket(port: harness.port)
        defer { socket.close() }

        socket.send("GET /v1/status HTTP/1.1\r\nHost: 127.0.0.1:\(harness.port)\r\n")
        let response = await socket.readUntilClosed()
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 408 "), response)
        await harness.server.stop()
    }

    func testConnectionCapReturns503WithRetryAfter() async throws {
        let harness = try await makeTemporaryHarness(
            connectionTimeout: .seconds(60),
            maxConcurrentConnections: 1
        )
        let idle = try RawSocket(port: harness.port)
        defer { idle.close() }
        try await waitForOpenConnections(1, on: harness.server)

        let busy = try RawSocket(port: harness.port)
        defer { busy.close() }
        let response = await busy.readUntilClosed()
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 503 "), response)
        XCTAssertTrue(response.contains("Retry-After: 1"), response)
        XCTAssertTrue(response.contains("server_busy"), response)

        await harness.server.stop()
    }

    func testUnauthorizedRequestsDoNotSpendRateLimit() async throws {
        let limits = AgentStreamLimits(
            maxChunkUTF8Bytes: 32 * 1_024,
            maxAssembledUTF8Bytes: 512 * 1_024,
            maxHeaderUTF8Bytes: 16 * 1_024,
            maxBodyUTF8Bytes: 64 * 1_024,
            maxRequestsPerSecond: 3,
            inactiveExpiration: .seconds(600),
            terminalRetention: .seconds(600),
            readyRetention: .seconds(1_800)
        )
        try await withHarness(limits: limits) { harness in
            for _ in 0..<10 {
                let response = try await harness.rawRequest(
                    path: "/v1/status",
                    method: "GET",
                    token: "wrong-token"
                )
                XCTAssertEqual(response.status, 401)
            }
            let authorized = try await harness.rawRequest(
                path: "/v1/status",
                method: "GET"
            )
            XCTAssertEqual(authorized.status, 200, authorized.body)
        }
    }

    func testOversizedRequestReturns413() async throws {
        try await withHarness { harness in
            let socket = try RawSocket(port: harness.port)
            defer { socket.close() }
            // Headers only: the declared body is over the limit, so the server
            // answers without the client sending it.
            socket.send(
                "POST /v1/streams HTTP/1.1\r\n"
                    + "Host: 127.0.0.1:\(harness.port)\r\n"
                    + "Authorization: Bearer \(harness.token)\r\n"
                    + "Content-Type: application/json\r\n"
                    + "Content-Length: \(10 * 1_024 * 1_024)\r\n"
                    + "\r\n"
            )
            let response = await socket.readUntilClosed()
            XCTAssertTrue(response.hasPrefix("HTTP/1.1 413 "), response)
            XCTAssertTrue(response.contains("payload_too_large"), response)
        }
    }

    func testRestartIgnoresOldListenerCancellation() async throws {
        let harness = try await makeTemporaryHarness()
        await harness.server.stop()
        let restarted = try await harness.server.start()

        // Give the first listener's late `.cancelled` callback time to arrive.
        try await Task.sleep(for: .milliseconds(300))

        let running = await harness.server.isRunning
        XCTAssertTrue(running)
        let port = await harness.server.publishedPort
        XCTAssertEqual(port, restarted.port)
        let fresh = Harness(
            server: harness.server,
            port: restarted.port,
            token: restarted.record.token,
            discoveryURL: harness.discoveryURL,
            target: harness.target
        )
        let status = try await fresh.rawRequest(path: "/v1/status", method: "GET")
        XCTAssertEqual(status.status, 200, status.body)
        await harness.server.stop()
    }

    private struct Harness {
        let server: AgentStreamHTTPServer
        let port: UInt16
        let token: String
        let discoveryURL: URL
        let target: HTTPServerAgentStreamTargetSpy

        func getJSON(
            path: String,
            method: String,
            headers: [String: String] = [:],
            body: String? = nil,
            expectedStatus: Int = 200
        ) async throws -> [String: Any] {
            let raw = try await rawRequest(
                path: path,
                method: method,
                headers: headers,
                body: body
            )
            XCTAssertEqual(raw.status, expectedStatus, raw.body)
            let data = Data(raw.body.utf8)
            let object = try JSONSerialization.jsonObject(with: data)
            return try XCTUnwrap(object as? [String: Any])
        }

        func rawRequest(
            path: String,
            method: String,
            headers: [String: String] = [:],
            body: String? = nil,
            token: String? = nil
        ) async throws -> (status: Int, body: String) {
            let absolute = try XCTUnwrap(
                URL(string: "http://127.0.0.1:\(port)\(path)")
            )
            var request = URLRequest(url: absolute)
            request.httpMethod = method
            request.setValue(
                "Bearer \(token ?? self.token)",
                forHTTPHeaderField: "Authorization"
            )
            request.setValue("127.0.0.1:\(port)", forHTTPHeaderField: "Host")
            request.setValue("close", forHTTPHeaderField: "Connection")
            if let body {
                request.httpBody = Data(body.utf8)
                request.setValue(
                    "application/json",
                    forHTTPHeaderField: "Content-Type"
                )
                request.setValue(
                    String(body.utf8.count),
                    forHTTPHeaderField: "Content-Length"
                )
            }
            for (name, value) in headers {
                request.setValue(value, forHTTPHeaderField: name)
            }

            let session = URLSession(configuration: .ephemeral)
            let (data, response) = try await session.data(for: request)
            let http = try XCTUnwrap(response as? HTTPURLResponse)
            return (
                status: http.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }
    }

    /// A harness whose discovery directory is removed when the test ends.
    /// Callers stop the server themselves.
    private func makeTemporaryHarness(
        connectionTimeout: Duration = AgentStreamHTTPServer.defaultConnectionTimeout,
        maxConcurrentConnections: Int = AgentStreamHTTPServer.defaultMaxConcurrentConnections
    ) async throws -> Harness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return try await makeHarness(
            discoveryURL: directory.appendingPathComponent("agent-server.json"),
            connectionTimeout: connectionTimeout,
            maxConcurrentConnections: maxConcurrentConnections
        )
    }

    private func waitForOpenConnections(
        _ expected: Int,
        on server: AgentStreamHTTPServer
    ) async throws {
        for _ in 0..<500 {
            if await server.openConnectionCount == expected {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let actual = await server.openConnectionCount
        XCTFail("Expected \(expected) open connections, found \(actual)")
    }

    private func withHarness(
        limits: AgentStreamLimits = .default,
        _ body: (Harness) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let discoveryURL = directory.appendingPathComponent("agent-server.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let harness = try await makeHarness(
            discoveryURL: discoveryURL,
            limits: limits
        )
        do {
            try await body(harness)
        } catch {
            await harness.server.stop()
            throw error
        }
        await harness.server.stop()
    }

    private func makeHarness(
        discoveryURL: URL,
        limits: AgentStreamLimits = .default,
        connectionTimeout: Duration = AgentStreamHTTPServer.defaultConnectionTimeout,
        maxConcurrentConnections: Int = AgentStreamHTTPServer.defaultMaxConcurrentConnections
    ) async throws -> Harness {
        let store = AgentStreamDiscoveryStore(fileURL: discoveryURL)
        let target = HTTPServerAgentStreamTargetSpy()
        let controller = AgentStreamController(
            target: target,
            notifier: HTTPServerAgentStreamNotifierSpy()
        )
        let gateway = AgentStreamHTTPGateway(controller: controller)
        let server = AgentStreamHTTPServer(
            gateway: gateway,
            discoveryStore: store,
            limits: limits,
            processIdentifier: 55_555,
            tokenGenerator: { "test-bearer-token" },
            connectionTimeout: connectionTimeout,
            maxConcurrentConnections: maxConcurrentConnections
        )
        let started = try await server.start()
        return Harness(
            server: server,
            port: started.port,
            token: started.record.token,
            discoveryURL: discoveryURL,
            target: target
        )
    }
}

/// A plain loopback TCP client, so tests can open a socket and send nothing
/// (or a partial request), which `URLSession` can't do.
private final class RawSocket: Sendable {
    private let descriptor: Int32

    init(port: UInt16) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw POSIXError(.EIO)
        }
        var noSigPipe: Int32 = 1
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )
        // Bound every read so a regression fails the test instead of hanging it.
        var receiveTimeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.ECONNREFUSED)
        }
        self.descriptor = descriptor
    }

    func send(_ text: String) {
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes {
            Darwin.send(descriptor, $0.baseAddress, $0.count, 0)
        }
    }

    /// Reads until the server closes the connection (or the read times out).
    @concurrent
    func readUntilClosed() async -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = recv(descriptor, &buffer, buffer.count, 0)
            if count <= 0 {
                break
            }
            data.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: data, as: UTF8.self)
    }

    func close() {
        Darwin.close(descriptor)
    }
}

@MainActor
private final class HTTPServerAgentStreamTargetSpy: AgentStreamTarget {
    var isAgentStreamTargetAvailable: Bool = true
    var agentStreamOpaquePageID: String? = "page"
    private(set) var rememberCount = 0
    private(set) var pasteCount = 0

    func rememberCurrentEditorCursor(
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        rememberCount += 1
        completion(true)
    }

    func pasteMarkdownAtSavedEditorCursor(
        _ markdown: String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        pasteCount += 1
        completion(true)
    }
}

@MainActor
private final class HTTPServerAgentStreamNotifierSpy: AgentStreamNotifying {
    func notifyStreamReady(label: String, streamID: UUID) {}
    func clearStreamNotifications() {}
}
