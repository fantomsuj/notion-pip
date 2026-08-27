import Foundation

enum AgentStreamPhase: String, Equatable, Sendable {
    /// Agent is still sending chunks.
    case receiving
    /// Agent finished; waiting for the user to Accept and choose a paste location.
    case ready
    /// User accepted; inserting at the freshly captured Notion cursor.
    case inserting
    case inserted
    case failed
    case cancelled
    case expired
}

enum AgentStreamErrorCode: String, Equatable, Sendable {
    case unauthorized
    case streamActive = "stream_active"
    case cursorUnavailable = "cursor_unavailable"
    case targetChanged = "target_changed"
    case sequenceMismatch = "sequence_mismatch"
    case payloadTooLarge = "payload_too_large"
    case rateLimited = "rate_limited"
    case streamGone = "stream_gone"
    case invalidRequest = "invalid_request"
}

struct AgentStreamError: Error, Equatable, Sendable {
    let code: AgentStreamErrorCode
    let message: String
    let expectedSequence: Int?
    let httpStatus: Int

    init(
        code: AgentStreamErrorCode,
        message: String,
        expectedSequence: Int? = nil,
        httpStatus: Int
    ) {
        self.code = code
        self.message = message
        self.expectedSequence = expectedSequence
        self.httpStatus = httpStatus
    }

    static func unauthorized() -> AgentStreamError {
        AgentStreamError(
            code: .unauthorized,
            message: "Authorization required.",
            httpStatus: 401
        )
    }

    static func streamActive() -> AgentStreamError {
        AgentStreamError(
            code: .streamActive,
            message: "Another local agent stream is already active.",
            httpStatus: 409
        )
    }

    static func cursorUnavailable() -> AgentStreamError {
        AgentStreamError(
            code: .cursorUnavailable,
            message: "Click in the Notion page where you want to paste, then Accept.",
            httpStatus: 409
        )
    }

    static func targetChanged() -> AgentStreamError {
        AgentStreamError(
            code: .targetChanged,
            message: "The Notion page changed before paste finished. Click again and Accept.",
            httpStatus: 409
        )
    }

    static func sequenceMismatch(expected: Int) -> AgentStreamError {
        AgentStreamError(
            code: .sequenceMismatch,
            message: "Chunk sequence does not match the next expected value.",
            expectedSequence: expected,
            httpStatus: 409
        )
    }

    static func payloadTooLarge(_ message: String) -> AgentStreamError {
        AgentStreamError(
            code: .payloadTooLarge,
            message: message,
            httpStatus: 413
        )
    }

    static func rateLimited() -> AgentStreamError {
        AgentStreamError(
            code: .rateLimited,
            message: "Too many requests.",
            httpStatus: 429
        )
    }

    static func streamGone() -> AgentStreamError {
        AgentStreamError(
            code: .streamGone,
            message: "The stream is no longer available.",
            httpStatus: 410
        )
    }

    static func invalidRequest(_ message: String) -> AgentStreamError {
        AgentStreamError(
            code: .invalidRequest,
            message: message,
            httpStatus: 400
        )
    }
}

struct AgentStreamLimits: Equatable, Sendable {
    static let `default` = AgentStreamLimits(
        maxChunkUTF8Bytes: 32 * 1_024,
        maxAssembledUTF8Bytes: 512 * 1_024,
        maxHeaderUTF8Bytes: 16 * 1_024,
        maxBodyUTF8Bytes: 64 * 1_024,
        maxRequestsPerSecond: 30,
        inactiveExpiration: .seconds(10 * 60),
        terminalRetention: .seconds(10 * 60),
        readyRetention: .seconds(30 * 60)
    )

    let maxChunkUTF8Bytes: Int
    let maxAssembledUTF8Bytes: Int
    let maxHeaderUTF8Bytes: Int
    let maxBodyUTF8Bytes: Int
    let maxRequestsPerSecond: Int
    let inactiveExpiration: Duration
    let terminalRetention: Duration
    /// How long a completed stream waits for user Accept before expiring.
    let readyRetention: Duration
}

enum AgentStreamContentType: String, Equatable, Sendable {
    /// UTF-8 Markdown source. Overlay renders Markdown; Accept pastes into Notion
    /// so headings, lists, and code fences convert.
    case markdown = "text/markdown"
}

/// Version 1 commit mode: agent completion never writes to Notion.
/// The user must Accept after placing the editor cursor.
enum AgentStreamCommitMode: String, Equatable, Sendable {
    case acceptToPaste = "accept_to_paste"
}

struct AgentStreamCreateRequest: Equatable, Sendable {
    let client: String
    let label: String?
    let commitMode: AgentStreamCommitMode
    let contentType: AgentStreamContentType
    let idempotencyKey: String

    init(
        client: String,
        label: String? = nil,
        commitMode: AgentStreamCommitMode = .acceptToPaste,
        contentType: AgentStreamContentType = .markdown,
        idempotencyKey: String
    ) {
        self.client = client
        self.label = label
        self.commitMode = commitMode
        self.contentType = contentType
        self.idempotencyKey = idempotencyKey
    }
}

struct AgentStreamChunk: Equatable, Sendable {
    let sequence: Int
    let text: String
}

struct AgentStreamSnapshot: Equatable, Sendable {
    let id: UUID
    let label: String
    let client: String
    let contentType: AgentStreamContentType
    let phase: AgentStreamPhase
    let assembledText: String
    let nextSequence: Int
    let opaquePageID: String?
    let errorMessage: String?
    let canAccept: Bool
    let showsOverlay: Bool

    var isTerminal: Bool {
        switch phase {
        case .inserted, .cancelled, .expired:
            true
        case .receiving, .ready, .inserting, .failed:
            false
        }
    }

    /// Occupies the single active stream slot (blocks a second create).
    var occupiesActiveSlot: Bool {
        switch phase {
        case .receiving, .ready, .inserting, .failed:
            true
        case .inserted, .cancelled, .expired:
            false
        }
    }

    var isActivelyReceiving: Bool {
        phase == .receiving
    }
}

struct AgentStreamCreateResult: Equatable, Sendable {
    let snapshot: AgentStreamSnapshot
    let limits: AgentStreamLimits
}

struct AgentStreamServerStatus: Equatable, Sendable {
    let ready: Bool
    let targetAvailable: Bool
    let limits: AgentStreamLimits
    let activeStreamID: UUID?
    let activeStreamPhase: AgentStreamPhase?
}

enum AgentStreamOverlayPresentation: Equatable, Sendable {
    case hidden
    case receiving(
        label: String,
        text: String,
        contentType: AgentStreamContentType,
        isStreaming: Bool
    )
    case ready(
        label: String,
        text: String,
        contentType: AgentStreamContentType
    )
    case inserting(label: String, text: String, contentType: AgentStreamContentType)
    case success(label: String)
    case failed(
        label: String,
        text: String,
        contentType: AgentStreamContentType,
        message: String?
    )
    case cancelled

    static func from(snapshot: AgentStreamSnapshot?) -> AgentStreamOverlayPresentation {
        guard let snapshot, snapshot.showsOverlay else {
            return .hidden
        }
        switch snapshot.phase {
        case .receiving:
            return .receiving(
                label: snapshot.label,
                text: snapshot.assembledText,
                contentType: snapshot.contentType,
                isStreaming: true
            )
        case .ready:
            return .ready(
                label: snapshot.label,
                text: snapshot.assembledText,
                contentType: snapshot.contentType
            )
        case .inserting:
            return .inserting(
                label: snapshot.label,
                text: snapshot.assembledText,
                contentType: snapshot.contentType
            )
        case .inserted:
            return .success(label: snapshot.label)
        case .failed:
            return .failed(
                label: snapshot.label,
                text: snapshot.assembledText,
                contentType: snapshot.contentType,
                message: snapshot.errorMessage
            )
        case .cancelled, .expired:
            return .cancelled
        }
    }
}

enum AgentStreamAccessibilityLabels {
    static let card = "Local agent stream"
    static let agentLabel = "Agent name"
    static let state = "Stream state"
    static let output = "Stream output"
    static let stop = "Stop streaming"
    static let copy = "Copy stream output"
    static let accept = "Accept and paste into Notion"
    static let dismiss = "Dismiss stream"
    static let expandDetails = "Show stream details"
    static let collapseDetails = "Hide stream details"
}

enum AgentStreamUserFacingCopy {
    static let readyTitle = "Agent response ready"
    static let readyBodyPrefix = "Click in Notion where it should go, then Accept"
    static let acceptButton = "Accept"
    static let stopButton = "Stop"
    static let copyButton = "Copy"
    static let dismissButton = "Dismiss"
    static let addedReceipt = "Added to Notion"
    static let clickFirstHint = "Click in the Notion page where you want this, then Accept."
    static let failedTitle = "Couldn’t paste"
}
