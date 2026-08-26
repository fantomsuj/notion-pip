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
            AgentStreamSkillDocument.markdown
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

    ## Discovery

    Read the discovery JSON. Fields: `schemaVersion`, `baseURL`, `token`, `pid`,
    `startedAt`. Never print the token to chat, logs, or commits.

    `baseURL` already includes `/v1` (example shape:
    `http://127.0.0.1:<port>/v1`). All routes below are relative to that base.

    Unknown paths return the same envelope
    `{"error":{"code":"invalid_request","message":"Unknown route."}}` — do not
    guess. Use only the routes in this skill.

    ## Important: Content-Type

    - Every POST uses the **HTTP header** `Content-Type: application/json`.
    - `"contentType": "text/markdown"` is a **JSON body field** describing the
      payload format. It is not the HTTP Content-Type header.
    - Do not send `Content-Type: text/markdown` on requests.

    ## Routes

    | Method | Path | Purpose |
    |---|---|---|
    | `GET` | `/status` | Readiness, target hint, limits, active stream |
    | `POST` | `/streams` | Create the single active stream (`Idempotency-Key` required) |
    | `POST` | `/streams/{id}/chunks` | Append `{ "sequence": n, "text": "..." }` |
    | `POST` | `/streams/{id}/complete` | Finish input → phase `ready` (does not paste) |
    | `POST` | `/streams/{id}/cancel` | Cancel without pasting; frees the active slot |
    | `GET` | `/streams/{id}` | Recover / poll phase after timeouts or Accept |

    All requests need `Authorization: Bearer <token>`.

    ## Protocol (accept_to_paste)

    1. Read discovery (`baseURL`, `token`).
    2. `GET {baseURL}/status`. Example fields:
       ```json
       {
         "ready": true,
         "targetAvailable": true,
         "limits": { "...": "..." },
         "activeStreamID": null,
         "activeStreamPhase": null
       }
       ```
       - `ready: true` means the listener is up.
       - `targetAvailable: false` means no Notion page is loaded/focused in Perch
         yet. You may still create and stream; the user must open/focus a page
         before Accept can paste. Do not treat it as a hard failure to start.
       - If `activeStreamID` is set, another stream occupies the slot — wait, or
         `POST .../cancel` that id, then create.
    3. `POST {baseURL}/streams` with headers:
       - `Authorization: Bearer <token>`
       - `Content-Type: application/json`
       - `Idempotency-Key: <unique key>` (required **only** on create)
       Body:
       ```json
       {
         "client": "<your-agent-id>",
         "label": "<Your Agent>",
         "commitMode": "accept_to_paste",
         "contentType": "text/markdown"
       }
       ```
       Set `client`/`label` to identify yourself (e.g. `"claude-code"`/`"Claude Code"`,
       `"codex"`/`"Codex"`, `"cursor"`/`"Cursor"`). The protocol does not treat any
       agent specially.

       **Idempotency:** Retrying create with the **same** `Idempotency-Key` returns
       the same stream (safe retry). A new key while a stream is active →
       `409 stream_active`. Do **not** send `Idempotency-Key` on chunks, complete,
       cancel, or GET — chunk retries are keyed by `sequence` instead.
    4. Stream UTF-8 Markdown chunks with increasing `sequence` starting at `0`:
       `POST {baseURL}/streams/{id}/chunks` body `{"sequence":n,"text":"..."}`.
       Cap each chunk at 32 KiB. Retry the exact previous sequence if a response
       is lost. Responses echo `phase`, `nextSequence`, and `assembledText` — use
       `assembledText` to verify what Perch has so far.
    5. `POST {baseURL}/streams/{id}/complete` when finished. This only marks the
       stream **ready** in Perch. Do **not** expect Notion to change yet.
    6. Tell the user: click in Notion where the note should go, then press
       **Accept** in Perch (or the notification action).
    7. Optional close-the-loop: `GET {baseURL}/streams/{id}` and watch `phase`:
       - `ready` — waiting for the user
       - `inserting` — Accept in progress
       - `inserted` — paste succeeded
       - `failed` — paste failed; user can retry Accept or Copy
       - `expired` / `cancelled` — no paste; stop waiting

    ## Errors

    Failures use:

    ```json
    {
      "error": {
        "code": "stream_active",
        "message": "Another local agent stream is already active."
      }
    }
    ```

    Branch on `error.code`, not the message string. Common codes:

    | Code | Status | What to do |
    |---|---|---|
    | `unauthorized` | 401 | Re-read discovery; Perch may have restarted |
    | `invalid_request` | 4xx | Fix method/path/JSON/headers; do not invent routes |
    | `stream_active` | 409 | Wait, or `POST /streams/{activeId}/cancel`, then create |
    | `sequence_mismatch` | 409 | Resend with `expectedSequence` from the error if present |
    | `payload_too_large` | 413 | Smaller chunks; total assembled cap is 512 KiB |
    | `rate_limited` | 429 | Back off and retry |
    | `stream_gone` | 410 | Stop forwarding; stream cancelled/expired/unknown |

    ## Rules

    - One active stream at a time.
    - Prefer Markdown (headings, lists, fenced code). Perch renders it live and
      pastes so Notion can convert structure.
    - Never call remote Notion APIs or ask for integration tokens.
    - If discovery is missing, ask the user to enable Local Agents in Perch.

    ## Optional helper

    Repository script `script/perch_agent_client.swift` can `pipe` stdin as chunks.
    """#
}
