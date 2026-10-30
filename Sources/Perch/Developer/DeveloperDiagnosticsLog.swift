#if PERCH_DEVELOPER
import Foundation

/// A short, in-memory record of what Perch did recently, for the diagnostics HUD
/// and the copied diagnostics report. Developer builds only.
@MainActor
final class DeveloperDiagnosticsLog: ObservableObject {
    static let shared = DeveloperDiagnosticsLog()

    enum EventKind: String, Sendable {
        case memoryPressure = "memory"
        case renderer = "renderer"
        case webView = "webview"
        case navigation = "nav"
        case developer = "dev"
        case typing = "typing"
    }

    /// Where a key's time was spent.
    enum KeyDelayStage: String, Sendable {
        /// From the key press until Perch's main thread finished passing it on.
        /// Large values mean Perch itself was busy.
        case perch
        /// From the key event inside the page until the next frame after Notion
        /// handled it. Large values mean Notion or WebKit was busy.
        case page
    }

    struct KeyDelayStats: Equatable, Sendable {
        var count = 0
        var slowCount = 0
        var worst: Duration = .zero
        var last: Duration?
    }

    struct Event: Equatable, Identifiable, Sendable {
        let id: Int
        let date: Date
        let kind: EventKind
        let message: String
    }

    struct Interval: Equatable, Identifiable, Sendable {
        let id: Int
        let date: Date
        let operation: PerformanceOperation
        let duration: Duration
        let outcome: PerformanceOutcome
    }

    struct Counters: Equatable, Sendable {
        var memoryPressureWarnings = 0
        var memoryPressureCriticals = 0
        var rendererTerminations = 0
        var webViewConstructions = 0
        var webViewEvictions = 0
        var navigationFailures = 0
    }

    /// A key slower than this misses about three frames at 60 Hz, which is
    /// when a pause starts to be noticeable.
    static let slowKeyDelay: Duration = .milliseconds(50)

    let capacity: Int
    /// Not published: keys arrive faster than the HUD needs, and the HUD
    /// samples once a second anyway.
    private(set) var perchKeyDelay = KeyDelayStats()
    private(set) var pageKeyDelay = KeyDelayStats()
    @Published private(set) var events: [Event] = []
    @Published private(set) var intervals: [Interval] = []
    @Published private(set) var counters = Counters()
    private var nextID = 0
    private let now: @MainActor () -> Date

    init(capacity: Int = 40, now: @escaping @MainActor () -> Date = { Date() }) {
        self.capacity = max(1, capacity)
        self.now = now
    }

    func record(_ kind: EventKind, _ message: String) {
        events.append(Event(id: takeID(), date: now(), kind: kind, message: message))
        trim(&events)
    }

    func recordMemoryPressure(_ level: NotionMemoryPressureLevel) {
        switch level {
        case .warning:
            counters.memoryPressureWarnings += 1
            record(.memoryPressure, "Memory pressure: warning")
        case .critical:
            counters.memoryPressureCriticals += 1
            record(.memoryPressure, "Memory pressure: critical")
        }
    }

    func recordRendererTermination() {
        counters.rendererTerminations += 1
        record(.renderer, "Web content process exited")
    }

    func recordNavigationFailure(_ description: String) {
        counters.navigationFailures += 1
        record(.navigation, "Navigation failed: \(description)")
    }

    func recordInterval(
        _ operation: PerformanceOperation,
        duration: Duration,
        outcome: PerformanceOutcome
    ) {
        switch operation {
        case .webViewConstruction where outcome == .success:
            counters.webViewConstructions += 1
        case .webViewEviction where outcome == .success:
            counters.webViewEvictions += 1
        default:
            break
        }
        intervals.append(Interval(
            id: takeID(),
            date: now(),
            operation: operation,
            duration: duration,
            outcome: outcome
        ))
        trim(&intervals)
    }

    func recordKeyDelay(_ duration: Duration, stage: KeyDelayStage) {
        let duration = max(duration, .zero)
        var stats = keyDelayStats(for: stage)
        stats.count += 1
        stats.last = duration
        stats.worst = max(stats.worst, duration)
        let isSlow = duration >= Self.slowKeyDelay
        if isSlow {
            stats.slowCount += 1
        }
        switch stage {
        case .perch: perchKeyDelay = stats
        case .page: pageKeyDelay = stats
        }
        if isSlow {
            record(.typing, "Slow key (\(stage.rawValue)): \(duration.diagnosticsMilliseconds) ms")
        }
    }

    /// Records the delay for an AppKit key event, whose timestamp counts from
    /// system start like `ProcessInfo.systemUptime`.
    func recordKeyDelay(
        eventTimestamp: TimeInterval,
        stage: KeyDelayStage,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        recordKeyDelay(.seconds(uptime - eventTimestamp), stage: stage)
    }

    func keyDelayStats(for stage: KeyDelayStage) -> KeyDelayStats {
        switch stage {
        case .perch: perchKeyDelay
        case .page: pageKeyDelay
        }
    }

    /// The most recent interval for each operation, newest first.
    var latestIntervalPerOperation: [Interval] {
        var seen: Set<PerformanceOperation> = []
        return intervals.reversed().filter { seen.insert($0.operation).inserted }
    }

    func reset() {
        events = []
        intervals = []
        counters = Counters()
        perchKeyDelay = KeyDelayStats()
        pageKeyDelay = KeyDelayStats()
    }

    private func takeID() -> Int {
        nextID += 1
        return nextID
    }

    private func trim<Element>(_ buffer: inout [Element]) {
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
    }
}

extension Duration {
    /// Whole milliseconds, for compact display.
    var diagnosticsMilliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1_000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
#endif
