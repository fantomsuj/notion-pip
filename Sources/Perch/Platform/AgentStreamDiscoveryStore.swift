import Foundation

struct AgentStreamDiscoveryRecord: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let baseURL: String
    let token: String
    let pid: Int32
    let startedAt: Date

    init(
        schemaVersion: Int = 1,
        baseURL: String,
        token: String,
        pid: Int32,
        startedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.baseURL = baseURL
        self.token = token
        self.pid = pid
        self.startedAt = startedAt
    }
}

final class AgentStreamDiscoveryStore: Sendable {
    static var defaultFileURL: URL {
        ApplicationInstanceCoordinator.defaultApplicationSupportDirectoryURL
            .appendingPathComponent("agent-server.json")
    }

    private let fileURL: URL

    init(fileURL: URL = AgentStreamDiscoveryStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    var url: URL { fileURL }

    func publish(_ record: AgentStreamDiscoveryRecord) throws {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let temporaryURL = directory.appendingPathComponent(
            ".\(UUID().uuidString).agent-server.tmp"
        )
        do {
            try data.write(to: temporaryURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: temporaryURL.path
            )
            _ = try fileManager.replaceItemAt(
                fileURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: fileURL.path
            )
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    func load() throws -> AgentStreamDiscoveryRecord? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentStreamDiscoveryRecord.self, from: data)
    }

    /// Removes the discovery file only when it still identifies this server.
    func removeIfMatches(pid: Int32, token: String) throws {
        guard let existing = try load() else { return }
        guard existing.pid == pid,
              AgentStreamHTTPCodec.tokensMatch(existing.token, token)
        else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    func removeFileIfPresent() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
