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
        limits: AgentStreamLimits = .default
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
            tokenGenerator: { "test-bearer-token" }
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
