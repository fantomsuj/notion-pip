import Foundation

enum QuickCaptureDestination: Codable, Equatable, Sendable {
    case pageParent(pageID: String, title: String)
    case dataSource(dataSourceID: String, title: String)

    var identifier: String {
        switch self {
        case let .pageParent(pageID, _):
            pageID
        case let .dataSource(dataSourceID, _):
            dataSourceID
        }
    }

    var title: String {
        switch self {
        case let .pageParent(_, title), let .dataSource(_, title):
            title
        }
    }

    var rawKind: String {
        switch self {
        case .pageParent:
            "page_parent"
        case .dataSource:
            "data_source"
        }
    }

    init?(rawKind: String, identifier: String, title: String) {
        guard !identifier.isEmpty else { return nil }
        switch rawKind {
        case "page_parent":
            self = .pageParent(pageID: identifier, title: title)
        case "data_source":
            self = .dataSource(dataSourceID: identifier, title: title)
        default:
            return nil
        }
    }

    var captureDestination: CaptureDestination {
        switch self {
        case let .pageParent(pageID, _):
            .pageParent(pageID: pageID)
        case let .dataSource(dataSourceID, _):
            .dataSource(dataSourceID: dataSourceID)
        }
    }
}
