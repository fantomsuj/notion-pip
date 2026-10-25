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

    let capacity: Int
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

    /// The most recent interval for each operation, newest first.
    var latestIntervalPerOperation: [Interval] {
        var seen: Set<PerformanceOperation> = []
        return intervals.reversed().filter { seen.insert($0.operation).inserted }
    }

    func reset() {
        events = []
        intervals = []
        counters = Counters()
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
