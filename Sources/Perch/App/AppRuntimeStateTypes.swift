import Foundation

struct ServiceHealthState: Equatable, Sendable {
    static let healthy = ServiceHealthState()

    private(set) var issues: [ServiceHealthIssue]

    var isHealthy: Bool {
        issues.isEmpty
    }

    init(issues: Set<ServiceHealthIssue> = []) {
        self.issues = issues.sorted()
    }

    mutating func report(_ issue: ServiceHealthIssue) {
        guard !issues.contains(issue) else { return }
        issues.append(issue)
        issues.sort()
    }

    mutating func resolve(_ issue: ServiceHealthIssue) {
        issues.removeAll { $0 == issue }
    }
}

enum ServiceHealthIssue: String, Comparable, Identifiable, Sendable {
    case persistentStoreUnavailable
    case pinnedPagePersistenceUnavailable
    case globalShortcutUnavailable

    var id: String {
        rawValue
    }

    static func < (lhs: ServiceHealthIssue, rhs: ServiceHealthIssue) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum PageActivationSource: Equatable, Sendable {
    case restored
    case typedURL
    case clipboard
    case externalRoute(ExternalURLSource)
    case notionWebSession
    case pagePicker
    case pageSwitcher
}

enum ShortcutPeekGestureState: Equatable, Sendable {
    case idle
    case peeking(generation: UInt, deadlineElapsed: Bool)
    case awaitingSecondPress(generation: UInt)
    case persistent(generation: UInt)
    case suppressingRelease(generation: UInt)
}

enum StatusItemPeekState: Equatable, Sendable {
    case idle
    case peeking(generation: UInt)
}
