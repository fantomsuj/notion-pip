import XCTest
@testable import Perch

final class AgentStreamHTTPCodecTests: XCTestCase {
    private let limits = AgentStreamLimits.default

    func testParsesStatusRouteAndBearer() {
        let raw = request(
            method: "GET",
            path: "/v1/status",
            headers: [
                "Host: 127.0.0.1:49152",
                "Authorization: Bearer secret-token",
            ]
        )

        let outcome = AgentStreamHTTPCodec.decodeRequest(
            from: raw,
            limits: limits,
            expectedHostPort: 49152
        )

        guard case .request(let parsed) = outcome else {
            return XCTFail("Expected parsed request, got \(outcome)")
        }
        XCTAssertEqual(parsed.method, .get)
        XCTAssertEqual(parsed.route, .status)
        XCTAssertEqual(parsed.authorizationBearer, "secret-token")
        XCTAssertEqual(parsed.contentLength, 0)
    }

    func testRejectsBrowserOrigin() {
        let raw = request(
            method: "GET",
            path: "/v1/status",
            headers: [
                "Host: 127.0.0.1:9",
                "Authorization: Bearer t",
                "Origin: https://example.com",
            ]
        )
        let outcome = AgentStreamHTTPCodec.decodeRequest(
            from: raw,
            limits: limits,
            expectedHostPort: 9
        )
        guard case .failure(_, let error) = outcome else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(error.code, .invalidRequest)
        XCTAssertEqual(error.httpStatus, 403)
    }

    func testRejectsInvalidHost() {
        let raw = request(
            method: "GET",
            path: "/v1/status",
            headers: [
                "Host: evil.example",
                "Authorization: Bearer t",
            ]
        )
        let outcome = AgentStreamHTTPCodec.decodeRequest(
            from: raw,
            limits: limits,
            expectedHostPort: 9
        )
        guard case .failure(_, let error) = outcome else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(error.code, .invalidRequest)
    }

    func testRejectsChunkedTransferEncoding() {
        let raw = request(
            method: "POST",
            path: "/v1/streams",
            headers: [
                "Host: 127.0.0.1:9",
                "Authorization: Bearer t",
                "Content-Type: application/json",
                "Transfer-Encoding: chunked",
                "Content-Length: 2",
            ],
            body: "{}"
        )
        let outcome = AgentStreamHTTPCodec.decodeRequest(
            from: raw,
            limits: limits,
            expectedHostPort: 9
        )
        guard case .failure(_, let error) = outcome else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(error.code, .invalidRequest)
    }

    func testRejectsOversizedBodyLength() {
        let raw = request(
            method: "POST",
            path: "/v1/streams",
            headers: [
                "Host: 127.0.0.1:9",
                "Authorization: Bearer t",
                "Content-Type: application/json",
                "Content-Length: \(limits.maxBodyUTF8Bytes + 1)",
            ],
            body: ""
        )
        let outcome = AgentStreamHTTPCodec.decodeRequest(
            from: raw,
            limits: limits,
            expectedHostPort: 9
        )
        guard case .failure(let status, let error) = outcome else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(status, 413)
        XCTAssertEqual(error.code, .payloadTooLarge)
    }

    func testNeedMoreDataUntilHeadersComplete() {
        let partial = Data("GET /v1/status HTTP/1.1\r\nHost: 127.0.0.1:9\r\n".utf8)
        let outcome = AgentStreamHTTPCodec.decodeRequest(
            from: partial,
            limits: limits,
            expectedHostPort: 9
        )
        XCTAssertEqual(outcome, .needMoreData)
    }

    func testParsesCreateChunkCompleteCancelAndGetRoutes() throws {
        let streamID = UUID()
        let cases: [(String, String, AgentStreamHTTPRoute)] = [
            ("POST", "/v1/streams", .createStream),
            ("POST", "/v1/streams/\(streamID.uuidString)/chunks", .appendChunk(streamID)),
            ("POST", "/v1/streams/\(streamID.uuidString)/complete", .complete(streamID)),
            ("POST", "/v1/streams/\(streamID.uuidString)/cancel", .cancel(streamID)),
            ("GET", "/v1/streams/\(streamID.uuidString)", .getStream(streamID)),
        ]

        for (method, path, expectedRoute) in cases {
            let body = method == "POST" ? #"{}"# : ""
            var headers = [
                "Host: localhost:9",
                "Authorization: Bearer t",
            ]
            if method == "POST" {
                headers.append("Content-Type: application/json")
                headers.append("Content-Length: \(body.utf8.count)")
                headers.append("Idempotency-Key: key-1")
            }
            let raw = request(method: method, path: path, headers: headers, body: body)
            let outcome = AgentStreamHTTPCodec.decodeRequest(
                from: raw,
                limits: limits,
                expectedHostPort: 9
            )
            guard case .request(let parsed) = outcome else {
                return XCTFail("Failed for \(method) \(path): \(outcome)")
            }
            XCTAssertEqual(parsed.route, expectedRoute)
        }
    }

    func testDecodeCreateAndChunkBodies() throws {
        let createData = Data(
            #"{"client":"cursor","label":"Cursor","commitMode":"accept_to_paste","contentType":"text/markdown"}"#
                .utf8
        )
        let create = try AgentStreamHTTPCodec.decodeCreateBody(createData)
        XCTAssertEqual(create.client, "cursor")
        XCTAssertEqual(create.label, "Cursor")
        XCTAssertEqual(create.commitMode, .acceptToPaste)
        XCTAssertEqual(create.contentType, .markdown)

        let chunkData = Data("{\"sequence\":2,\"text\":\"## Hello\"}".utf8)
        let chunk = try AgentStreamHTTPCodec.decodeChunkBody(chunkData)
        XCTAssertEqual(chunk.sequence, 2)
        XCTAssertEqual(chunk.text, "## Hello")
    }

    func testEncodeErrorIncludesOptionalExpectedSequence() throws {
        let data = AgentStreamHTTPCodec.encodeErrorResponse(
            .sequenceMismatch(expected: 3)
        )
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("HTTP/1.1 409 Conflict"))
        XCTAssertTrue(text.contains("Connection: close"))
        XCTAssertTrue(text.contains("\"code\":\"sequence_mismatch\""))
        XCTAssertTrue(text.contains("\"expectedSequence\":3"))
    }

    func testConstantTimeTokenCompare() {
        XCTAssertTrue(AgentStreamHTTPCodec.tokensMatch("abc", "abc"))
        XCTAssertFalse(AgentStreamHTTPCodec.tokensMatch("abc", "abd"))
        XCTAssertFalse(AgentStreamHTTPCodec.tokensMatch("abc", "abcd"))
    }

    private func request(
        method: String,
        path: String,
        headers: [String],
        body: String = ""
    ) -> Data {
        var lines = ["\(method) \(path) HTTP/1.1"]
        lines.append(contentsOf: headers)
        if !headers.contains(where: { $0.lowercased().hasPrefix("content-length:") }),
           !body.isEmpty
        {
            lines.append("Content-Length: \(body.utf8.count)")
        }
        lines.append("")
        lines.append(body)
        return Data(lines.joined(separator: "\r\n").utf8)
    }
}
