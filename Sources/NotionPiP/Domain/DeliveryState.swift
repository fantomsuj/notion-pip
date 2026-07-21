import Foundation

enum DeliveryState: String, Codable, CaseIterable, Sendable {
    case queued
    case inFlight
    case delivered
    case retrying
    case blockedConflict
    case uncertain
}

enum DraftDisposition: String, Codable, Sendable {
    case active
    case stashed
    case abandoned
}

enum CaptureDestination: Codable, Equatable, Sendable {
    case managed(databaseID: String)
    case manual(pageID: String)

    var identifier: String {
        switch self {
        case let .managed(databaseID): databaseID
        case let .manual(pageID): pageID
        }
    }

    var isManaged: Bool {
        if case .managed = self { true } else { false }
    }

    var rawKind: String {
        if isManaged { "managed" } else { "manual" }
    }

    init?(rawKind: String, identifier: String) {
        switch rawKind {
        case "managed": self = .managed(databaseID: identifier)
        case "manual": self = .manual(pageID: identifier)
        default: return nil
        }
    }
}

struct SafeDeliveryError: Codable, Equatable, Sendable {
    let code: String
    let message: String?
    let statusCode: Int?
    let retryAfter: TimeInterval?
}
