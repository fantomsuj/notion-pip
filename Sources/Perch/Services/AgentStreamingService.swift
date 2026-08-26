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
    private var publishedBaseURL: String?

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
        // Intentionally omit the bearer token from the pasteboard summary.
        // Agents should read the discovery file for authentication.
        let details = """
        Perch local agent streaming is ready.
        Discovery file: \(AgentStreamDiscoveryStore.defaultFileURL.path)
        Base URL: \(baseURL)
        Use the discovery file token with Authorization: Bearer <token>.
        Content-Type: text/markdown
        Commit mode: accept_to_paste (you Accept in Perch before paste).
        """
        pasteboard.clearContents()
        pasteboard.setString(details, forType: .string)
        return true
    }

    @discardableResult
    func installAgentSkill() -> Bool {
        do {
            let destination = try skillInstaller.install()
            skillInstallMessage =
                "Installed Cursor skill at \(destination.path)"
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
        state = isEnabled ? .disabled : .disabled
    }

    private func startServer() {
        startTask?.cancel()
        state = .starting
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                if server.isRunning {
                    await stopServerAsync()
                }
                let result = try await server.start()
                guard !Task.isCancelled else {
                    await stopServerAsync()
                    return
                }
                publishedBaseURL = result.record.baseURL
                state = .ready(baseURL: result.record.baseURL)
            } catch {
                guard !Task.isCancelled else { return }
                publishedBaseURL = nil
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
        publishedBaseURL = nil
    }

    private func stopServerAsync() async {
        await server.stop()
        publishedBaseURL = nil
    }
}

struct AgentStreamSkillInstaller {
    static let skillFolderName = "stream-to-perch"
    static let skillFileName = "SKILL.md"

    private let destinationDirectoryURL: URL
    private let bundledSkillProvider: () throws -> String

    init(
        destinationDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent(AgentStreamSkillInstaller.skillFolderName, isDirectory: true),
        bundledSkillProvider: @escaping () throws -> String = {
            AgentStreamSkillDocument.markdown
        }
    ) {
        self.destinationDirectoryURL = destinationDirectoryURL
        self.bundledSkillProvider = bundledSkillProvider
    }

    func install() throws -> URL {
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
    static let markdown = #"""
    ---
    name: stream-to-perch
    description: >-
      Streams Markdown agent output into Perch's local accept-to-paste API so the
      user can review, place the Notion cursor, and Accept. Use when the user asks
      to send a response to Perch, Notion via Perch, or to stream notes into their
      floating Notion panel.
    ---

    # Stream Markdown to Perch

    ## When to use

    Use this skill when the user wants your finished Markdown answer pasted into
    Notion through Perch. Perch never auto-inserts. The user clicks a location in
    the Notion page and presses **Accept**.

    ## Prerequisites

    1. Perch is running on this Mac.
    2. Settings → Local Agents → **Allow local agents** is enabled.
    3. Discovery file exists at:
       `~/Library/Application Support/com.fantomsuj.Perch/agent-server.json`

    ## Protocol (accept_to_paste)

    1. Read the discovery JSON (`schemaVersion`, `baseURL`, `token`). Never print
       the token to chat, logs, or commits.
    2. `GET {baseURL}/status` with `Authorization: Bearer <token>`.
    3. `POST {baseURL}/streams` with headers:
       - `Authorization: Bearer <token>`
       - `Content-Type: application/json`
       - `Idempotency-Key: <unique key>`
       Body:
       ```json
       {
         "client": "cursor",
         "label": "Cursor",
         "commitMode": "accept_to_paste",
         "contentType": "text/markdown"
       }
       ```
    4. Stream UTF-8 Markdown chunks with increasing `sequence` starting at `0`:
       `POST {baseURL}/streams/{id}/chunks` body `{"sequence":n,"text":"..."}`.
       Cap each chunk at 32 KiB. Retry the exact previous sequence if a response
       is lost.
    5. `POST {baseURL}/streams/{id}/complete` when finished. This only marks the
       stream **ready** in Perch. Do **not** expect Notion to change yet.
    6. Tell the user: click in Notion where the note should go, then press
       **Accept** in Perch (or the notification action).

    ## Rules

    - One active stream at a time. `409 stream_active` means wait or cancel.
    - `410 stream_gone` means stop forwarding.
    - Prefer Markdown (headings, lists, fenced code). Perch renders it live and
      pastes so Notion can convert structure.
    - Never call remote Notion APIs or ask for integration tokens.
    - If discovery is missing, ask the user to enable Local Agents in Perch.

    ## Optional helper

    Repository script `script/perch_agent_client.swift` can `pipe` stdin as chunks.
    """#
}
