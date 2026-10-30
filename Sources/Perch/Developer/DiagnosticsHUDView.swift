#if PERCH_DEVELOPER
import SwiftUI

@MainActor
final class DiagnosticsHUDModel: ObservableObject {
    @Published var snapshot: DiagnosticsSnapshot?
}

/// The live diagnostics panel shown by developer builds.
struct DiagnosticsHUDView: View {
    @ObservedObject var model: DiagnosticsHUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = model.snapshot {
                content(snapshot)
            } else {
                Text("Sampling…")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func content(_ snapshot: DiagnosticsSnapshot) -> some View {
        section("Processes") {
            row("Perch", DiagnosticsSnapshot.describe(snapshot.app))
            row(
                "WebContent",
                DiagnosticsSnapshot.describe(snapshot.webContent),
                warning: snapshot.web.webContentProcessID == nil && snapshot.web.retention == .warm
            )
        }
        section("Web view") {
            row("State", "\(DiagnosticsSnapshot.describe(snapshot.web.state)) · \(snapshot.web.retention.rawValue)",
                warning: isProblem(snapshot.web.state))
            row("Panel", snapshot.web.panelIsVisible ? "visible" : "hidden")
            row("Typing", snapshot.web.isTypingInPage ? "yes" : "no")
            row(
                "Page",
                DiagnosticsSnapshot.shortPageID(
                    snapshot.web.activePageID,
                    isCustomURL: snapshot.web.isShowingCustomURL
                )
            )
            row("Saved states", "\(snapshot.web.interactionStateCount)")
        }
        section("Key delay") {
            keyDelayRow("Waiting on Perch", snapshot.perchKeyDelay)
            keyDelayRow("Notion page", snapshot.pageKeyDelay)
        }
        section("Counters") {
            row("Pressure", "warn \(snapshot.counters.memoryPressureWarnings) · crit \(snapshot.counters.memoryPressureCriticals)")
            row("Renderer exits", "\(snapshot.counters.rendererTerminations)",
                warning: snapshot.counters.rendererTerminations > 0)
            row("Views built", "\(snapshot.counters.webViewConstructions) · evicted \(snapshot.counters.webViewEvictions)")
            row("Nav failures", "\(snapshot.counters.navigationFailures)",
                warning: snapshot.counters.navigationFailures > 0)
        }
        section("Latest timings") {
            if snapshot.latestIntervals.isEmpty {
                Text("none yet").foregroundStyle(.secondary)
            }
            ForEach(snapshot.latestIntervals.prefix(8)) { interval in
                row(
                    interval.operation.rawValue,
                    "\(interval.duration.diagnosticsMilliseconds) ms",
                    warning: interval.outcome == .failure
                )
            }
        }
        section("Recent events") {
            if snapshot.recentEvents.isEmpty {
                Text("none yet").foregroundStyle(.secondary)
            }
            ForEach(snapshot.recentEvents.suffix(6).reversed()) { event in
                Text("\(DiagnosticsSnapshot.timestamp(event.date)) \(event.message)")
                    .lineLimit(2)
            }
        }
        Text("Perch \(snapshot.appVersion) · pid \(snapshot.appProcessID)")
            .foregroundStyle(.tertiary)
    }

    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String, warning: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(warning ? Color.orange : Color.primary)
                .lineLimit(1)
        }
    }

    private func keyDelayRow(
        _ label: String,
        _ stats: DeveloperDiagnosticsLog.KeyDelayStats
    ) -> some View {
        row(
            label,
            stats.last == nil
                ? "no keys yet"
                : "\(stats.last?.diagnosticsMilliseconds ?? 0) ms · worst "
                    + "\(stats.worst.diagnosticsMilliseconds) · slow \(stats.slowCount)/\(stats.count)",
            warning: stats.slowCount > 0
        )
    }

    private func isProblem(_ state: NotionWebSessionState) -> Bool {
        switch state {
        case .failed, .offline: true
        case .unloaded, .loading, .active, .suspended: false
        }
    }
}
#endif
