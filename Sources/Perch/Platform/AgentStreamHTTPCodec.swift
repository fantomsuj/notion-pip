import Foundation

enum AgentStreamHTTPMethod: String, Equatable, Sendable {
    case get = "GET"
    case post = "POST"
}

enum AgentStreamHTTPRoute: Equatable, Sendable {
    case status
    case createStream
    case appendChunk(UUID)
    case complete(UUID)
    case cancel(UUID)
    case getStream(UUID)
}

struct AgentStreamHTTPParsedRequest: Equatable, Sendable {
    let method: AgentStreamHTTPMethod
    let route: AgentStreamHTTPRoute
    let headers: [String: String]
    let body: Data
    let authorizationBearer: String?
    let idempotencyKey: String?
    let contentLength: Int
}

enum AgentStreamHTTPDecodeOutcome: Equatable, Sendable {
    case needMoreData
    case request(AgentStreamHTTPParsedRequest)
    case failure(status: Int, error: AgentStreamError)
}

enum AgentStreamHTTPCodec {
    static let protocolVersion = "HTTP/1.1"
    static let jsonContentType = "application/json"

    static func decodeRequest(
        from buffer: Data,
        limits: AgentStreamLimits,
        expectedHostPort: UInt16?
    ) -> AgentStreamHTTPDecodeOutcome {
        guard let headerEnd = findHeaderTerminator(in: buffer) else {
            if buffer.count > limits.maxHeaderUTF8Bytes {
                return .failure(
                    status: 431,
                    error: .payloadTooLarge("Request headers exceed the size limit.")
                )
            }
            return .needMoreData
        }

        let headerData = buffer.subdata(in: 0..<headerEnd)
        if headerData.count > limits.maxHeaderUTF8Bytes {
            return .failure(
                status: 431,
                error: .payloadTooLarge("Request headers exceed the size limit.")
            )
        }

        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .failure(
                status: 400,
                error: .invalidRequest("Request headers must be valid UTF-8.")
            )
        }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return .failure(
                status: 400,
                error: .invalidRequest("Missing request line.")
            )
        }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard requestParts.count == 3 else {
            return .failure(
                status: 400,
                error: .invalidRequest("Malformed request line.")
            )
        }

        let methodRaw = String(requestParts[0])
        let target = String(requestParts[1])
        let version = String(requestParts[2])
        guard version == protocolVersion else {
            return .failure(
                status: 505,
                error: .invalidRequest("Only HTTP/1.1 is supported.")
            )
        }

        guard let method = AgentStreamHTTPMethod(rawValue: methodRaw) else {
            return .failure(
                status: 405,
                error: .invalidRequest("Unsupported method.")
            )
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            guard let separator = line.firstIndex(of: ":") else {
                return .failure(
                    status: 400,
                    error: .invalidRequest("Malformed header line.")
                )
            }
            let name = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let valueStart = line.index(after: separator)
            let value = line[valueStart...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                return .failure(
                    status: 400,
                    error: .invalidRequest("Malformed header name.")
                )
            }
            // First occurrence wins; duplicates of security-sensitive headers are rejected later.
            if headers[name] == nil {
                headers[name] = value
            } else if name == "host"
                || name == "authorization"
                || name == "content-length"
                || name == "transfer-encoding"
                || name == "origin"
            {
                return .failure(
                    status: 400,
                    error: .invalidRequest("Duplicate \(name) header.")
                )
            }
        }

        if headers["origin"] != nil {
            return .failure(
                status: 403,
                error: AgentStreamError(
                    code: .invalidRequest,
                    message: "Browser Origin headers are not allowed.",
                    httpStatus: 403
                )
            )
        }

        if let transferEncoding = headers["transfer-encoding"],
           transferEncoding.lowercased().contains("chunked")
        {
            return .failure(
                status: 400,
                error: .invalidRequest("Chunked transfer encoding is not supported.")
            )
        }

        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsed = Int(rawLength), parsed >= 0 else {
                return .failure(
                    status: 400,
                    error: .invalidRequest("Invalid Content-Length.")
                )
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }

        if contentLength > limits.maxBodyUTF8Bytes {
            return .failure(
                status: 413,
                error: .payloadTooLarge("Request body exceeds the size limit.")
            )
        }

        let bodyStart = headerEnd + 4
        let availableBody = buffer.count - bodyStart
        if availableBody < contentLength {
            let projectedHeadersAndBody = headerData.count + contentLength
            if projectedHeadersAndBody > limits.maxHeaderUTF8Bytes + limits.maxBodyUTF8Bytes {
                return .failure(
                    status: 413,
                    error: .payloadTooLarge("Request exceeds size limits.")
                )
            }
            return .needMoreData
        }

        let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))

        guard let route = parseRoute(method: method, target: target) else {
            return .failure(
                status: 404,
                error: .invalidRequest("Unknown route.")
            )
        }

        if let expectedHostPort,
           !isValidHost(headers["host"], port: expectedHostPort)
        {
            return .failure(
                status: 400,
                error: .invalidRequest("Invalid Host header.")
            )
        }

        let authorizationBearer = parseBearerToken(headers["authorization"])
        let contentType = headers["content-type"]
        if method == .post {
            guard isJSONContentType(contentType) else {
                return .failure(
                    status: 415,
                    error: .invalidRequest("Content-Type must be application/json.")
                )
            }
        }

        return .request(
            AgentStreamHTTPParsedRequest(
                method: method,
                route: route,
                headers: headers,
                body: body,
                authorizationBearer: authorizationBearer,
                idempotencyKey: headers["idempotency-key"],
                contentLength: contentLength
            )
        )
    }

    static func encodeResponse(
        status: Int,
        reason: String,
        headers: [(String, String)] = [],
        body: Data = Data()
    ) -> Data {
        var text = "\(protocolVersion) \(status) \(reason)\r\n"
        text += "Content-Length: \(body.count)\r\n"
        text += "Connection: close\r\n"
        var hasContentType = false
        for (name, value) in headers {
            if name.lowercased() == "content-type" {
                hasContentType = true
            }
            text += "\(name): \(value)\r\n"
        }
        if !body.isEmpty && !hasContentType {
            text += "Content-Type: \(jsonContentType); charset=utf-8\r\n"
        }
        text += "\r\n"
        var data = Data(text.utf8)
        data.append(body)
        return data
    }

    static func encodeJSONResponse(
        status: Int,
        reason: String,
        object: some Encodable
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(object)
        return encodeResponse(status: status, reason: reason, body: body)
    }

    static func encodeErrorResponse(_ error: AgentStreamError) -> Data {
        struct ErrorBody: Encodable {
            struct Payload: Encodable {
                let code: String
                let message: String
                let expectedSequence: Int?
            }

            let error: Payload
        }

        let body = ErrorBody(
            error: .init(
                code: error.code.rawValue,
                message: error.message,
                expectedSequence: error.expectedSequence
            )
        )
        let data = (try? JSONEncoder().encode(body)) ?? Data(
            #"{"error":{"code":"invalid_request","message":"Unable to encode error."}}"#.utf8
        )
        return encodeResponse(
            status: error.httpStatus,
            reason: reasonPhrase(for: error.httpStatus),
            body: data
        )
    }

    static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 410: "Gone"
        case 413: "Payload Too Large"
        case 415: "Unsupported Media Type"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 505: "HTTP Version Not Supported"
        default: "Error"
        }
    }

    static func parseBearerToken(_ value: String?) -> String? {
        guard let value else { return nil }
        let prefix = "Bearer "
        guard value.count >= prefix.count,
              value.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame
        else {
            return nil
        }
        let token = String(value.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func tokensMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        let maxCount = max(left.count, right.count)
        var difference: UInt8 = left.count == right.count ? 0 : 1
        for index in 0..<maxCount {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= leftByte ^ rightByte
        }
        return difference == 0
    }

    static func isJSONContentType(_ value: String?) -> Bool {
        guard let value else { return false }
        let mediaType = value.split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return mediaType == jsonContentType
    }

    static func isValidHost(_ host: String?, port: UInt16) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let allowed = [
            "127.0.0.1",
            "127.0.0.1:\(port)",
            "localhost",
            "localhost:\(port)",
            "[::1]",
            "[::1]:\(port)",
            "::1",
            "::1:\(port)",
        ]
        return allowed.contains { $0.caseInsensitiveCompare(host) == .orderedSame }
    }

    // MARK: - JSON bodies

    struct CreateBody: Decodable, Equatable, Sendable {
        let client: String
        let label: String?
        let commitMode: String
        let contentType: String
    }

    struct ChunkBody: Decodable, Equatable, Sendable {
        let sequence: Int
        let text: String
    }

    struct LimitsDTO: Encodable, Equatable, Sendable {
        let maxChunkUTF8Bytes: Int
        let maxAssembledUTF8Bytes: Int
        let maxHeaderUTF8Bytes: Int
        let maxBodyUTF8Bytes: Int
        let maxRequestsPerSecond: Int
        let inactiveExpirationSeconds: Int
        let terminalRetentionSeconds: Int
        let readyRetentionSeconds: Int

        init(_ limits: AgentStreamLimits) {
            maxChunkUTF8Bytes = limits.maxChunkUTF8Bytes
            maxAssembledUTF8Bytes = limits.maxAssembledUTF8Bytes
            maxHeaderUTF8Bytes = limits.maxHeaderUTF8Bytes
            maxBodyUTF8Bytes = limits.maxBodyUTF8Bytes
            maxRequestsPerSecond = limits.maxRequestsPerSecond
            inactiveExpirationSeconds = Int(durationSeconds(limits.inactiveExpiration))
            terminalRetentionSeconds = Int(durationSeconds(limits.terminalRetention))
            readyRetentionSeconds = Int(durationSeconds(limits.readyRetention))
        }
    }

    struct StatusDTO: Encodable, Equatable, Sendable {
        let ready: Bool
        let targetAvailable: Bool
        let limits: LimitsDTO
        let activeStreamID: String?
        let activeStreamPhase: String?

        init(_ status: AgentStreamServerStatus) {
            ready = status.ready
            targetAvailable = status.targetAvailable
            limits = LimitsDTO(status.limits)
            activeStreamID = status.activeStreamID?.uuidString
            activeStreamPhase = status.activeStreamPhase?.rawValue
        }
    }

    /// Public stream acknowledgment. Content and page identity stay internal.
    struct StreamAckDTO: Encodable, Equatable, Sendable {
        let id: String
        let phase: String
        let nextSequence: Int
        let error: String?
        let limits: LimitsDTO?

        init(_ snapshot: AgentStreamSnapshot, limits: AgentStreamLimits? = nil) {
            id = snapshot.id.uuidString
            phase = snapshot.phase.rawValue
            nextSequence = snapshot.nextSequence
            error = snapshot.errorMessage
            self.limits = limits.map(LimitsDTO.init)
        }
    }

    static func decodeCreateBody(_ data: Data) throws -> AgentStreamCreateRequest {
        let body: CreateBody
        do {
            body = try JSONDecoder().decode(CreateBody.self, from: data)
        } catch {
            throw AgentStreamError.invalidRequest("Malformed create body.")
        }
        guard let commitMode = AgentStreamCommitMode(rawValue: body.commitMode) else {
            throw AgentStreamError.invalidRequest(
                "Unsupported commitMode. Use accept_to_paste."
            )
        }
        guard let contentType = AgentStreamContentType(rawValue: body.contentType) else {
            throw AgentStreamError.invalidRequest(
                "Unsupported contentType. Use text/markdown."
            )
        }
        return AgentStreamCreateRequest(
            client: body.client,
            label: body.label,
            commitMode: commitMode,
            contentType: contentType,
            idempotencyKey: ""
        )
    }

    static func decodeChunkBody(_ data: Data) throws -> AgentStreamChunk {
        do {
            let body = try JSONDecoder().decode(ChunkBody.self, from: data)
            return AgentStreamChunk(sequence: body.sequence, text: body.text)
        } catch {
            throw AgentStreamError.invalidRequest("Malformed chunk body.")
        }
    }

    // MARK: - Private

    private static func findHeaderTerminator(in buffer: Data) -> Int? {
        let pattern: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        guard buffer.count >= pattern.count else { return nil }
        for index in 0...(buffer.count - pattern.count) {
            if buffer[index] == pattern[0],
               buffer[index + 1] == pattern[1],
               buffer[index + 2] == pattern[2],
               buffer[index + 3] == pattern[3]
            {
                return index
            }
        }
        return nil
    }

    private static func parseRoute(
        method: AgentStreamHTTPMethod,
        target: String
    ) -> AgentStreamHTTPRoute? {
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? target

        switch (method, path) {
        case (.get, "/v1/status"):
            return .status
        case (.post, "/v1/streams"):
            return .createStream
        case (.post, let value) where value.hasPrefix("/v1/streams/") && value.hasSuffix("/chunks"):
            let idPart = String(
                value.dropFirst("/v1/streams/".count).dropLast("/chunks".count)
            )
            guard let id = UUID(uuidString: idPart) else { return nil }
            return .appendChunk(id)
        case (.post, let value) where value.hasPrefix("/v1/streams/") && value.hasSuffix("/complete"):
            let idPart = String(
                value.dropFirst("/v1/streams/".count).dropLast("/complete".count)
            )
            guard let id = UUID(uuidString: idPart) else { return nil }
            return .complete(id)
        case (.post, let value) where value.hasPrefix("/v1/streams/") && value.hasSuffix("/cancel"):
            let idPart = String(
                value.dropFirst("/v1/streams/".count).dropLast("/cancel".count)
            )
            guard let id = UUID(uuidString: idPart) else { return nil }
            return .cancel(id)
        case (.get, let value) where value.hasPrefix("/v1/streams/"):
            let idPart = String(value.dropFirst("/v1/streams/".count))
            guard !idPart.contains("/"), let id = UUID(uuidString: idPart) else { return nil }
            return .getStream(id)
        default:
            return nil
        }
    }

    private static func durationSeconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds
    }
}
