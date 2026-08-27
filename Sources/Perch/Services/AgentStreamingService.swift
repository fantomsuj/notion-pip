import AppKit
import Combine
import Foundation
import OSLog

enum AgentStreamingServiceState: Equatable, Sendable {
    case disabled
    case starting
    case ready(baseURL: String)
    case failed(String)
}

@MainActor
final class AgentStreamingService: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var state: AgentStreamingServiceState = .disabled
    @Published private(set) var skillInstallMessage: String?

    let controller: AgentStreamController

    private let preferenceStore: any AgentStreamingPreferenceStoring
    private let server: AgentStreamHTTPServer
    private let skillInstaller: AgentStreamSkillInstaller
    private let logger = Logger(
        subsystem: "com.fantomsuj.Perch",
        category: "agent-streaming"
    )
    private var startTask: Task<Void, Never>?

    init(
        controller: AgentStreamController,
        preferenceStore: any AgentStreamingPreferenceStoring = AgentStreamingPreferenceStore(),
        server: AgentStreamHTTPServer? = nil,
        skillInstaller: AgentStreamSkillInstaller = AgentStreamSkillInstaller()
    ) {
        self.controller = controller
        self.preferenceStore = preferenceStore
        self.skillInstaller = skillInstaller
        let gateway = AgentStreamHTTPGateway(controller: controller)
        self.server = server ?? AgentStreamHTTPServer(gateway: gateway)
        isEnabled = preferenceStore.load()
    }

    func startIfPreferred() {
        guard isEnabled else {
            state = .disabled
            return
        }
        startServer()
    }

    func setEnabled(_ enabled: Bool) {
        preferenceStore.save(enabled)
        isEnabled = enabled
        if enabled {
            startServer()
        } else {
            stopServer()
            state = .disabled
            skillInstallMessage = nil
        }
    }

    func retry() {
        guard isEnabled else { return }
        startServer()
    }

    func copyConnectionDetails(
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard case let .ready(baseURL) = state else { return false }
        let details = Self.connectionDetailsText(baseURL: baseURL)
        pasteboard.clearContents()
        pasteboard.setString(details, forType: .string)
        return true
    }

    /// Pasteboard summary for agents. Intentionally omits the bearer token.
    static func connectionDetailsText(baseURL: String) -> String {
        """
        Perch local agent streaming is ready.
        Discovery file: \(AgentStreamDiscoveryStore.defaultFileURL.path)
        Base URL: \(baseURL)
        Use the discovery file token with Authorization: Bearer <token>.
        HTTP header Content-Type: application/json
        JSON body field contentType: text/markdown (payload format only).
        Commit mode: accept_to_paste (you Accept in Perch before paste).
        """
    }

    @discardableResult
    func installAgentSkill(for target: AgentSkillTarget) -> Bool {
        do {
            let destination = try skillInstaller.install(for: target)
            skillInstallMessage =
                "Installed \(target.displayName) skill at \(destination.path)"
            return true
        } catch {
            skillInstallMessage =
                "Couldn’t install the agent skill. Copy the skill from the repository instead."
            logger.error("Agent skill install failed")
            return false
        }
    }

    func prepareForTermination() async {
        startTask?.cancel()
        startTask = nil
        controller.prepareForTermination()
        await stopServerAsync()
        state = .disabled
    }

    private func startServer() {
        startTask?.cancel()
        state = .starting
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                if await server.isRunning {
                    await stopServerAsync()
                }
                let result = try await server.start()
                guard !Task.isCancelled else {
                    await stopServerAsync()
                    return
                }
                state = .ready(baseURL: result.record.baseURL)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(
                    "Couldn’t start the local agent listener. Retry, or turn the setting off."
                )
                logger.error("Agent stream HTTP server failed to start")
            }
        }
    }

    private func stopServer() {
        startTask?.cancel()
        startTask = nil
        Task { [weak self] in
            await self?.stopServerAsync()
        }
    }

    private func stopServerAsync() async {
        await server.stop()
    }
}

/// Coding agents that read skills from a well-known `~/.<tool>/skills/<name>/SKILL.md`
/// path on disk. All three follow the same Markdown + frontmatter convention, so the
/// installer writes the identical, agent-neutral document to each one's directory.
enum AgentSkillTarget: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    fileprivate var homeRelativeSkillsDirectory: String {
        switch self {
        case .claude: return ".claude"
        case .codex: return ".codex"
        case .cursor: return ".cursor"
        }
    }
}

struct AgentStreamSkillInstaller {
    static let skillFolderName = "stream-to-perch"
    static let skillFileName = "SKILL.md"

    private let homeDirectoryURL: URL
    private let bundledSkillProvider: () throws -> String

    init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundledSkillProvider: @escaping () throws -> String = {
            try AgentStreamSkillDocument.load()
        }
    ) {
        self.homeDirectoryURL = homeDirectoryURL
        self.bundledSkillProvider = bundledSkillProvider
    }

    func destinationDirectoryURL(for target: AgentSkillTarget) -> URL {
        homeDirectoryURL
            .appendingPathComponent(target.homeRelativeSkillsDirectory, isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent(Self.skillFolderName, isDirectory: true)
    }

    @discardableResult
    func install(for target: AgentSkillTarget) throws -> URL {
        let destinationDirectoryURL = destinationDirectoryURL(for: target)
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationDirectoryURL,
            withIntermediateDirectories: true
        )
        let destination = destinationDirectoryURL
            .appendingPathComponent(Self.skillFileName)
        let markdown = try bundledSkillProvider()
        let temporary = destinationDirectoryURL.appendingPathComponent(
            ".\(UUID().uuidString).skill.tmp"
        )
        try markdown.write(to: temporary, atomically: true, encoding: .utf8)
        _ = try fileManager.replaceItemAt(
            destination,
            withItemAt: temporary,
            backupItemName: nil,
            options: []
        )
        return destination
    }
}

enum AgentStreamSkillDocument {
    static func load() throws -> String {
        guard let url = Bundle.module.url(
            forResource: "SKILL",
            withExtension: "md",
            subdirectory: "stream-to-perch"
        ) else {
            throw AgentStreamError.invalidRequest("Bundled agent skill is missing.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
