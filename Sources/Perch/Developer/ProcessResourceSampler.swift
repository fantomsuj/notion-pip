#if PERCH_DEVELOPER
import Darwin
import Foundation
import WebKit

/// One raw reading of a process's memory and CPU counters.
struct ProcessResourceReading: Equatable, Sendable {
    /// The same "Memory" figure Activity Monitor shows (physical footprint).
    let footprintBytes: UInt64
    /// User plus system CPU time used since the process started.
    let cpuTimeNanoseconds: UInt64
    /// When the reading was taken, on the monotonic uptime clock.
    let uptimeNanoseconds: UInt64
}

/// A process's memory and its CPU use since the previous reading.
struct ProcessResourceSample: Equatable, Sendable {
    let footprintBytes: UInt64
    /// Percent of one core, so 100 means one core fully busy. `nil` until the
    /// process has been read twice.
    let cpuPercent: Double?
}

enum ProcessResourceReader {
    /// Reads `pid`'s counters, or returns `nil` when the process is gone or macOS
    /// refuses the request.
    static func read(pid: pid_t) -> ProcessResourceReading? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard status == 0 else { return nil }
        // rusage CPU times are in Mach absolute-time units, which are not
        // nanoseconds on Apple silicon.
        let cpuTicks = info.ri_user_time &+ info.ri_system_time
        return ProcessResourceReading(
            footprintBytes: info.ri_phys_footprint,
            cpuTimeNanoseconds: nanoseconds(fromMachTicks: cpuTicks),
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
    }

    static func cpuPercent(
        from previous: ProcessResourceReading,
        to current: ProcessResourceReading
    ) -> Double? {
        guard current.uptimeNanoseconds > previous.uptimeNanoseconds,
              current.cpuTimeNanoseconds >= previous.cpuTimeNanoseconds
        else {
            return nil
        }
        let wall = Double(current.uptimeNanoseconds - previous.uptimeNanoseconds)
        let cpu = Double(current.cpuTimeNanoseconds - previous.cpuTimeNanoseconds)
        return cpu / wall * 100
    }

    private static let timebase: (numerator: UInt64, denominator: UInt64) = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else {
            return (1, 1)
        }
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    static func nanoseconds(fromMachTicks ticks: UInt64) -> UInt64 {
        let (high, low) = ticks.multipliedFullWidth(by: timebase.numerator)
        guard high < timebase.denominator else { return UInt64.max }
        return timebase.denominator.dividingFullWidth((high, low)).quotient
    }
}

/// Turns successive readings into samples with a CPU percentage.
struct ProcessResourceTracker {
    private var previousReadings: [pid_t: ProcessResourceReading] = [:]

    /// Records `reading` for `pid`. Readings for processes not passed in this
    /// round are dropped, so a recycled pid never borrows an old baseline.
    mutating func sample(
        _ readings: [pid_t: ProcessResourceReading]
    ) -> [pid_t: ProcessResourceSample] {
        var samples: [pid_t: ProcessResourceSample] = [:]
        for (pid, reading) in readings {
            let cpuPercent = previousReadings[pid].flatMap {
                ProcessResourceReader.cpuPercent(from: $0, to: reading)
            }
            samples[pid] = ProcessResourceSample(
                footprintBytes: reading.footprintBytes,
                cpuPercent: cpuPercent
            )
        }
        previousReadings = readings
        return samples
    }
}

@MainActor
enum WebContentProcessIdentifier {
    /// The pid of the WebKit content process that renders `webView`.
    ///
    /// `_webProcessIdentifier` is WebKit SPI. Only developer builds compile this,
    /// and it checks that WebKit still responds before asking.
    static func read(from webView: WKWebView) -> pid_t? {
        let key = "_webProcessIdentifier"
        guard webView.responds(to: NSSelectorFromString(key)),
              let value = webView.value(forKey: key) as? NSNumber
        else {
            return nil
        }
        let pid = value.int32Value
        return pid > 0 ? pid : nil
    }
}
#endif
