#if PERCH_DEVELOPER
import Foundation

/// The web view's state at one moment, as the diagnostics HUD shows it.
@MainActor
struct NotionWebDiagnosticsSnapshot {
    var state: NotionWebSessionState
    var retention: WebViewRetention
    var panelIsVisible: Bool
    var isTypingInPage: Bool
    var activePageID: String?
    var isShowingCustomURL: Bool
    var interactionStateCount: Int
    var webContentProcessID: pid_t?
}

/// Everything the HUD shows for one tick.
@MainActor
struct DiagnosticsSnapshot {
    var appVersion: String
    var appProcessID: pid_t
    var app: ProcessResourceSample?
    var webContent: ProcessResourceSample?
    var web: NotionWebDiagnosticsSnapshot
    var counters: DeveloperDiagnosticsLog.Counters
    var latestIntervals: [DeveloperDiagnosticsLog.Interval]
    var recentEvents: [DeveloperDiagnosticsLog.Event]

    /// Plain text for the clipboard, so a report can be pasted into an issue
    /// or a chat. It holds no page titles or URLs; page IDs are shortened.
    func report(generatedAt date: Date = Date()) -> String {
        var lines: [String] = []
        lines.append("Perch developer diagnostics")
        lines.append("Generated: \(Self.timestamp(date))")
        lines.append("Version: \(appVersion)")
        lines.append("")
        lines.append("Perch (pid \(appProcessID)): \(Self.describe(app))")
        let webPID = web.webContentProcessID.map { "pid \($0)" } ?? "no pid"
        lines.append("Web content (\(webPID)): \(Self.describe(webContent))")
        lines.append("")
        lines.append("Web view: \(Self.describe(web.state)), \(web.retention.rawValue)")
        lines.append("Panel: \(web.panelIsVisible ? "visible" : "hidden")")
        lines.append("Typing: \(web.isTypingInPage ? "yes" : "no")")
        lines.append("Page: \(Self.shortPageID(web.activePageID, isCustomURL: web.isShowingCustomURL))")
        lines.append("Saved page states: \(web.interactionStateCount)")
        lines.append("")
        lines.append(
            "Counters: pressure warn \(counters.memoryPressureWarnings), "
                + "critical \(counters.memoryPressureCriticals), "
                + "renderer exits \(counters.rendererTerminations), "
                + "web views built \(counters.webViewConstructions), "
                + "evicted \(counters.webViewEvictions), "
                + "nav failures \(counters.navigationFailures)"
        )
        lines.append("")
        lines.append("Latest timings:")
        if latestIntervals.isEmpty {
            lines.append("  none yet")
        }
        for interval in latestIntervals {
            lines.append(
                "  \(interval.operation.rawValue): "
                    + "\(interval.duration.diagnosticsMilliseconds) ms "
                    + "(\(interval.outcome.rawValue))"
            )
        }
        lines.append("")
        lines.append("Recent events:")
        if recentEvents.isEmpty {
            lines.append("  none yet")
        }
        for event in recentEvents {
            lines.append("  \(Self.timestamp(event.date)) [\(event.kind.rawValue)] \(event.message)")
        }
        return lines.joined(separator: "\n")
    }

    static func describe(_ sample: ProcessResourceSample?) -> String {
        guard let sample else { return "unavailable" }
        let memory = formatBytes(sample.footprintBytes)
        guard let cpu = sample.cpuPercent else { return "\(memory), CPU …" }
        return "\(memory), CPU \(String(format: "%.1f", cpu))%"
    }

    static func describe(_ state: NotionWebSessionState) -> String {
        switch state {
        case .unloaded: "unloaded"
        case .loading: "loading"
        case .active: "active"
        case .suspended: "suspended"
        case .offline: "offline"
        case .failed: "failed"
        }
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes >= 1_024 {
            return String(format: "%.2f GB", megabytes / 1_024)
        }
        return String(format: "%.0f MB", megabytes)
    }

    static func shortPageID(_ pageID: String?, isCustomURL: Bool) -> String {
        if isCustomURL { return "custom pin" }
        guard let pageID, !pageID.isEmpty else { return "none" }
        return "…" + String(pageID.suffix(6))
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
    }
}
#endif
