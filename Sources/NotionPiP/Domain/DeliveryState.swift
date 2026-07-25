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
    case pageParent(pageID: String)
    case dataSource(dataSourceID: String)

    var identifier: String {
        switch self {
        case let .managed(databaseID): databaseID
        case let .manual(pageID): pageID
        case let .pageParent(pageID): pageID
        case let .dataSource(dataSourceID): dataSourceID
        }
    }

    var isManaged: Bool {
        switch self {
        case .managed:
            true
        case .manual, .pageParent, .dataSource:
            false
        }
    }

    var rawKind: String {
        switch self {
        case .managed:
            "managed"
        case .manual:
            "manual"
        case .pageParent:
            "page_parent"
        case .dataSource:
            "data_source"
        }
    }

    var isJournaledPageCreation: Bool {
        switch self {
        case .pageParent, .dataSource:
            true
        case .managed, .manual:
            false
        }
    }

    init?(rawKind: String, identifier: String) {
        switch rawKind {
        case "managed": self = .managed(databaseID: identifier)
        case "manual": self = .manual(pageID: identifier)
        case "page_parent": self = .pageParent(pageID: identifier)
        case "data_source": self = .dataSource(dataSourceID: identifier)
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
