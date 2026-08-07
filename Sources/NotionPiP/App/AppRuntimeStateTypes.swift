import Foundation

struct ShortcutConfiguration: Equatable, Sendable {
    let panel: GlobalShortcut
    let quickCapture: GlobalShortcut

    var isValid: Bool {
        panel.isValid && quickCapture.isValid && panel != quickCapture
    }

    func replacingPanel(with shortcut: GlobalShortcut) -> ShortcutConfiguration {
        ShortcutConfiguration(panel: shortcut, quickCapture: quickCapture)
    }

    func replacingQuickCapture(with shortcut: GlobalShortcut) -> ShortcutConfiguration {
        ShortcutConfiguration(panel: panel, quickCapture: shortcut)
    }
}

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
    case quickCaptureShortcutUnavailable

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
    case notionSearch
    case notionWebSession
    case pagePicker
    case pageSwitcher
}

enum PersonalTokenConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(workspaceName: String)
    case failed(String)
}
