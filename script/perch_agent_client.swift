#!/usr/bin/env swift
import Darwin
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Dependency-free reference client for Perch local agent streaming.
// Reads the discovery file; never prints the bearer token.

enum ClientError: Error, CustomStringConvertible {
    case usage(String)
    case discoveryMissing(String)
    case discoveryInvalid(String)
    case http(status: Int, code: String?, message: String?)
    case transport(String)
    case cancelled

    var description: String {
        switch self {
        case .usage(let text):
            return text
        case .discoveryMissing(let path):
            return "Discovery file missing at \(path). Enable Settings → Local Agents → Allow local agents."
        case .discoveryInvalid(let detail):
            return "Invalid discovery file: \(detail)"
        case .http(_, let code, let message):
            let codePart = code.map { " [\($0)]" } ?? ""
            let messagePart = message.map { ": \($0)" } ?? ""
            return "HTTP error\(codePart)\(messagePart)"
        case .transport(let detail):
            return detail
        case .cancelled:
            return "Cancelled."
        }
    }

    var exitCode: Int32 {
        switch self {
        case .usage: return 2
        case .cancelled: return 130
        default: return 1
        }
    }
}

struct DiscoveryRecord: Decodable {
    let schemaVersion: Int
    let baseURL: String
    let token: String
    let pid: Int?
    let startedAt: String?
}

struct CLIOptions {
    var discoveryPath: String
    var client = "perch-agent-client"
    var label: String?
    var streamID: String?
    var sequence: Int?
    var text: String?
    var command: String?
    var remaining: [String] = []
}

final class TokenRedactor {
    private let token: String

    init(token: String) {
        self.token = token
    }

    func redact(_ text: String) -> String {
        guard !token.isEmpty else { return text }
        return text.replacingOccurrences(of: token, with: "<redacted-token>")
    }
}

enum InterruptFlag {
    // sig_atomic_t-safe flag; only set from signal handlers, read from main.
    nonisolated(unsafe) static var value: Int32 = 0

    static var interrupted: Bool { value != 0 }

    static func install() {
        signal(SIGINT) { _ in InterruptFlag.value = 1 }
        signal(SIGTERM) { _ in InterruptFlag.value = 1 }
    }
}

struct PerchClient {
    let baseURL: URL
    let token: String
    let redactor: TokenRedactor
    let session: URLSession

    init(discovery: DiscoveryRecord, session: URLSession = .shared) throws {
        guard let url = URL(string: discovery.baseURL) else {
            throw ClientError.discoveryInvalid("baseURL is not a valid URL.")
        }
        self.baseURL = url
        self.token = discovery.token
        self.redactor = TokenRedactor(token: discovery.token)
        self.session = session
    }

    func status() throws -> String {
        try perform(method: "GET", path: "/status")
    }

    func start(client: String, label: String?) throws -> String {
        var body: [String: Any] = [
            "client": client,
            "commitMode": "accept_to_paste",
            "contentType": "text/markdown",
        ]
        if let label, !label.isEmpty {
            body["label"] = label
        }
        return try perform(
            method: "POST",
            path: "/streams",
            idempotencyKey: UUID().uuidString,
            jsonObject: body,
            expectedStatus: 201
        )
    }

    func append(streamID: String, sequence: Int, text: String) throws -> String {
        let body: [String: Any] = [
            "sequence": sequence,
            "text": text,
        ]
        return try perform(
            method: "POST",
            path: "/streams/\(streamID)/chunks",
            jsonObject: body
        )
    }

    func complete(streamID: String) throws -> String {
        try perform(
            method: "POST",
            path: "/streams/\(streamID)/complete",
            jsonObject: [:]
        )
    }

    func cancel(streamID: String) throws -> String {
        try perform(
            method: "POST",
            path: "/streams/\(streamID)/cancel",
            jsonObject: [:]
        )
    }

    private func perform(
        method: String,
        path: String,
        idempotencyKey: String? = nil,
        jsonObject: [String: Any]? = nil,
        expectedStatus: Int? = nil
    ) throws -> String {
        // Preserve `/v1` in baseURL; do not use appendingPathComponent.
        let absolute = trimTrailingSlash(baseURL.absoluteString) + path
        guard let requestURL = URL(string: absolute) else {
            throw ClientError.transport("Could not build request URL.")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("close", forHTTPHeaderField: "Connection")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let jsonObject {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: jsonObject,
                options: []
            )
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
        }

        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultResponse: URLResponse?
        var resultError: Error?

        session.dataTask(with: request) { data, response, error in
            resultData = data
            resultResponse = response
            resultError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let resultError {
            throw ClientError.transport(
                redactor.redact("Request failed: \(resultError.localizedDescription)")
            )
        }
        guard let http = resultResponse as? HTTPURLResponse else {
            throw ClientError.transport("Missing HTTP response.")
        }
        let bodyText = String(data: resultData ?? Data(), encoding: .utf8) ?? ""
        let safeBody = redactor.redact(bodyText)
        let okStatuses = expectedStatus.map { Set([$0]) } ?? Set(200...299)
        if !okStatuses.contains(http.statusCode) {
            let parsed = parseError(safeBody)
            throw ClientError.http(
                status: http.statusCode,
                code: parsed.code,
                message: parsed.message
            )
        }
        return safeBody
    }

    private func parseError(_ body: String) -> (code: String?, message: String?) {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any]
        else {
            return (nil, body.isEmpty ? nil : body)
        }
        return (error["code"] as? String, error["message"] as? String)
    }

    private func trimTrailingSlash(_ value: String) -> String {
        if value.hasSuffix("/") {
            return String(value.dropLast())
        }
        return value
    }
}

func defaultDiscoveryPath() -> String {
    if let env = ProcessInfo.processInfo.environment["PERCH_AGENT_DISCOVERY"],
       !env.isEmpty
    {
        return env
    }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/Library/Application Support/com.fantomsuj.Perch/agent-server.json"
}

func usageText() -> String {
    """
    usage: perch_agent_client.swift <command> [options]

    commands:
      status
      start   [--client NAME] [--label LABEL]
      append  --stream-id ID --sequence N --text TEXT
      complete --stream-id ID
      cancel  --stream-id ID
      pipe    [--client NAME] [--label LABEL]

    options:
      --discovery PATH   Discovery JSON (default: Application Support path,
                         or PERCH_AGENT_DISCOVERY)

    pipe mirrors stdin to stdout, forwards UTF-8 Markdown chunks to Perch,
    completes on clean EOF, and cancels on interruption.
    commitMode=accept_to_paste contentType=text/markdown
    Never prints the bearer token.
    """
}

func parseArguments(_ args: [String]) throws -> CLIOptions {
    var options = CLIOptions(discoveryPath: defaultDiscoveryPath())
    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--discovery":
            index += 1
            guard index < args.count else {
                throw ClientError.usage("--discovery requires a path")
            }
            options.discoveryPath = args[index]
        case "--client":
            index += 1
            guard index < args.count else {
                throw ClientError.usage("--client requires a value")
            }
            options.client = args[index]
        case "--label":
            index += 1
            guard index < args.count else {
                throw ClientError.usage("--label requires a value")
            }
            options.label = args[index]
        case "--stream-id":
            index += 1
            guard index < args.count else {
                throw ClientError.usage("--stream-id requires a value")
            }
            options.streamID = args[index]
        case "--sequence":
            index += 1
            guard index < args.count, let value = Int(args[index]) else {
                throw ClientError.usage("--sequence requires an integer")
            }
            options.sequence = value
        case "--text":
            index += 1
            guard index < args.count else {
                throw ClientError.usage("--text requires a value")
            }
            options.text = args[index]
        case "--help", "-h":
            throw ClientError.usage(usageText())
        default:
            if arg.hasPrefix("-") {
                throw ClientError.usage("Unknown option: \(arg)\n\n\(usageText())")
            }
            if options.command == nil {
                options.command = arg
            } else {
                options.remaining.append(arg)
            }
        }
        index += 1
    }
    guard let command = options.command else {
        throw ClientError.usage(usageText())
    }
    options.command = command
    return options
}

func loadDiscovery(path: String) throws -> DiscoveryRecord {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ClientError.discoveryMissing(path)
    }
    do {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let record = try decoder.decode(DiscoveryRecord.self, from: data)
        guard record.schemaVersion == 1 else {
            throw ClientError.discoveryInvalid(
                "unsupported schemaVersion \(record.schemaVersion)"
            )
        }
        guard !record.baseURL.isEmpty, !record.token.isEmpty else {
            throw ClientError.discoveryInvalid("baseURL and token are required")
        }
        return record
    } catch let error as ClientError {
        throw error
    } catch {
        throw ClientError.discoveryInvalid(error.localizedDescription)
    }
}

func extractStreamID(from json: String) throws -> String {
    guard let data = json.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = object["id"] as? String,
          !id.isEmpty
    else {
        throw ClientError.transport("Create response missing stream id.")
    }
    return id
}

func printJSON(_ text: String) {
    if let data = text.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data),
       let pretty = try? JSONSerialization.data(
           withJSONObject: object,
           options: [.prettyPrinted, .sortedKeys]
       ),
       let prettyText = String(data: pretty, encoding: .utf8)
    {
        FileHandle.standardOutput.write(Data((prettyText + "\n").utf8))
    } else {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }
}

func flushUTF8Chunks(
    buffer: inout Data,
    maxBytes: Int,
    keepRemainder: Bool,
    emit: (Data) throws -> Void
) throws {
    guard !buffer.isEmpty else { return }
    if !keepRemainder {
        var start = 0
        while start < buffer.count {
            var end = min(start + maxBytes, buffer.count)
            if end < buffer.count {
                while end > start {
                    let byte = buffer[end]
                    if byte & 0b1100_0000 != 0b1000_0000 {
                        break
                    }
                    end -= 1
                }
                if end == start {
                    end = min(start + maxBytes, buffer.count)
                }
            }
            try emit(buffer.subdata(in: start..<end))
            start = end
        }
        buffer.removeAll(keepingCapacity: true)
        return
    }

    while buffer.count >= maxBytes {
        var end = maxBytes
        if end < buffer.count {
            while end > 0 {
                let byte = buffer[end]
                if byte & 0b1100_0000 != 0b1000_0000 {
                    break
                }
                end -= 1
            }
            if end == 0 {
                end = maxBytes
            }
        }
        try emit(buffer.subdata(in: 0..<end))
        buffer.removeSubrange(0..<end)
    }
}

func runPipe(client: PerchClient, options: CLIOptions) throws {
    InterruptFlag.install()
    let createJSON = try client.start(client: options.client, label: options.label)
    let streamID = try extractStreamID(from: createJSON)

    let maxChunk = 32 * 1024
    var sequence = 0
    var pending = Data()
    let stdin = FileHandle.standardInput
    let stdout = FileHandle.standardOutput

    func cancelIfNeeded() {
        _ = try? client.cancel(streamID: streamID)
    }

    func sendChunk(_ data: Data) throws {
        if InterruptFlag.interrupted {
            cancelIfNeeded()
            throw ClientError.cancelled
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ClientError.transport("Chunk is not valid UTF-8.")
        }
        // Retry the exact sequence once if the first attempt fails transiently.
        do {
            _ = try client.append(streamID: streamID, sequence: sequence, text: text)
        } catch {
            if InterruptFlag.interrupted {
                cancelIfNeeded()
                throw ClientError.cancelled
            }
            _ = try client.append(streamID: streamID, sequence: sequence, text: text)
        }
        sequence += 1
    }

    while true {
        if InterruptFlag.interrupted {
            cancelIfNeeded()
            throw ClientError.cancelled
        }
        let chunk = stdin.readData(ofLength: 16 * 1024)
        if chunk.isEmpty {
            break
        }
        stdout.write(chunk)
        pending.append(chunk)
        try flushUTF8Chunks(
            buffer: &pending,
            maxBytes: maxChunk,
            keepRemainder: true,
            emit: sendChunk
        )
    }

    try flushUTF8Chunks(
        buffer: &pending,
        maxBytes: maxChunk,
        keepRemainder: false,
        emit: sendChunk
    )

    if InterruptFlag.interrupted {
        cancelIfNeeded()
        throw ClientError.cancelled
    }

    _ = try client.complete(streamID: streamID)
    let message =
        "Stream \(streamID) ready in Perch. Click in Notion, then Accept.\n"
    FileHandle.standardError.write(Data(message.utf8))
}

func main() {
    do {
        let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
        let discovery = try loadDiscovery(path: options.discoveryPath)
        let client = try PerchClient(discovery: discovery)
        // Ensure accidental dumps never include the raw token.
        let redactor = TokenRedactor(token: discovery.token)

        switch options.command {
        case "status":
            printJSON(try client.status())
        case "start":
            printJSON(try client.start(client: options.client, label: options.label))
        case "append":
            guard let streamID = options.streamID else {
                throw ClientError.usage("append requires --stream-id")
            }
            guard let sequence = options.sequence else {
                throw ClientError.usage("append requires --sequence")
            }
            guard let text = options.text else {
                throw ClientError.usage("append requires --text")
            }
            printJSON(try client.append(streamID: streamID, sequence: sequence, text: text))
        case "complete":
            guard let streamID = options.streamID else {
                throw ClientError.usage("complete requires --stream-id")
            }
            printJSON(try client.complete(streamID: streamID))
        case "cancel":
            guard let streamID = options.streamID else {
                throw ClientError.usage("cancel requires --stream-id")
            }
            printJSON(try client.cancel(streamID: streamID))
        case "pipe":
            try runPipe(client: client, options: options)
        default:
            throw ClientError.usage(
                redactor.redact("Unknown command: \(options.command ?? "")\n\n\(usageText())")
            )
        }
    } catch let error as ClientError {
        let message = "error: \(error)\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(error.exitCode)
    } catch {
        FileHandle.standardError.write(
            Data("error: \(error.localizedDescription)\n".utf8)
        )
        exit(1)
    }
}

main()
