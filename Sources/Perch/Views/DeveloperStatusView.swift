import Foundation
import SwiftUI

struct DeveloperStatusView: View {
    private let metrics = ProcessMetrics.current

    var body: some View {
        LabeledContent("Process ID", value: "\(ProcessInfo.processInfo.processIdentifier)")
        LabeledContent("CPU time", value: metrics.cpuTime)
        LabeledContent("Peak resident memory", value: metrics.peakResidentMemory)
        LabeledContent("Available processors", value: "\(ProcessInfo.processInfo.activeProcessorCount)")
        LabeledContent("System uptime", value: metrics.systemUptime)
    }
}

private struct ProcessMetrics {
    let cpuTime: String
    let peakResidentMemory: String
    let systemUptime: String

    static var current: ProcessMetrics {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpuSeconds = TimeInterval(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + TimeInterval(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let uptimeFormatter = DateComponentsFormatter()
        uptimeFormatter.allowedUnits = [.day, .hour, .minute]
        uptimeFormatter.unitsStyle = .abbreviated
        return ProcessMetrics(
            cpuTime: String(format: "%.2f seconds", cpuSeconds),
            peakResidentMemory: ByteCountFormatter.string(fromByteCount: Int64(usage.ru_maxrss), countStyle: .memory),
            systemUptime: uptimeFormatter.string(from: ProcessInfo.processInfo.systemUptime) ?? "Unavailable"
        )
    }
}
