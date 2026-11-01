#if PERCH_DEVELOPER
import Darwin
import WebKit
import XCTest
@testable import Perch

@MainActor
final class DeveloperDiagnosticsTests: XCTestCase {
    func testDebugBuildsAreDeveloperBuilds() {
        XCTAssertTrue(DeveloperBuild.isEnabled)
    }

    func testReadsThisProcessFootprintAndCPUTime() throws {
        let reading = try XCTUnwrap(ProcessResourceReader.read(pid: getpid()))

        XCTAssertGreaterThan(reading.footprintBytes, 0)
        XCTAssertGreaterThan(reading.cpuTimeNanoseconds, 0)
    }

    func testMissingProcessHasNoReading() {
        XCTAssertNil(ProcessResourceReader.read(pid: -1))
    }

    func testCPUPercentIsCPUTimeOverWallTime() throws {
        let previous = reading(cpu: 1_000_000_000, uptime: 10_000_000_000)
        let current = reading(cpu: 1_250_000_000, uptime: 11_000_000_000)

        let percent = try XCTUnwrap(ProcessResourceReader.cpuPercent(from: previous, to: current))

        XCTAssertEqual(percent, 25, accuracy: 0.001)
    }

    func testCPUPercentIsUnknownWhenTheClockOrCountersGoBackwards() {
        let base = reading(cpu: 2_000, uptime: 2_000)

        XCTAssertNil(ProcessResourceReader.cpuPercent(from: base, to: reading(cpu: 3_000, uptime: 2_000)))
        XCTAssertNil(ProcessResourceReader.cpuPercent(from: base, to: reading(cpu: 1_000, uptime: 3_000)))
    }

    func testTrackerNeedsTwoReadingsAndForgetsProcessesThatDisappear() throws {
        var tracker = ProcessResourceTracker()

        let first = tracker.sample([42: reading(cpu: 0, uptime: 1_000, footprint: 10)])
        XCTAssertEqual(first[42], ProcessResourceSample(footprintBytes: 10, cpuPercent: nil))

        let second = tracker.sample([42: reading(cpu: 500, uptime: 2_000, footprint: 20)])
        XCTAssertEqual(try XCTUnwrap(second[42]?.cpuPercent), 50, accuracy: 0.001)

        _ = tracker.sample([:])
        let afterGap = tracker.sample([42: reading(cpu: 900, uptime: 3_000, footprint: 30)])
        XCTAssertNil(afterGap[42]?.cpuPercent)
    }

    func testLogKeepsOnlyTheNewestEntries() {
        let log = DeveloperDiagnosticsLog(capacity: 3)

        for index in 1 ... 5 {
            log.record(.developer, "event \(index)")
        }

        XCTAssertEqual(log.events.map(\.message), ["event 3", "event 4", "event 5"])
    }

    func testLogCountsPressureRendererExitsAndWebViewLifecycle() {
        let log = DeveloperDiagnosticsLog()

        log.recordMemoryPressure(.warning)
        log.recordMemoryPressure(.critical)
        log.recordMemoryPressure(.critical)
        log.recordRendererTermination()
        log.recordNavigationFailure("NSURLErrorDomain -1009")
        log.recordInterval(.webViewConstruction, duration: .milliseconds(30), outcome: .success)
        log.recordInterval(.webViewEviction, duration: .milliseconds(5), outcome: .success)
        log.recordInterval(.webViewEviction, duration: .milliseconds(5), outcome: .cancelled)

        XCTAssertEqual(log.counters.memoryPressureWarnings, 1)
        XCTAssertEqual(log.counters.memoryPressureCriticals, 2)
        XCTAssertEqual(log.counters.rendererTerminations, 1)
        XCTAssertEqual(log.counters.navigationFailures, 1)
        XCTAssertEqual(log.counters.webViewConstructions, 1)
        XCTAssertEqual(log.counters.webViewEvictions, 1)

        log.reset()
        XCTAssertEqual(log.counters, DeveloperDiagnosticsLog.Counters())
        XCTAssertTrue(log.events.isEmpty)
        XCTAssertTrue(log.intervals.isEmpty)
    }

    func testLatestIntervalPerOperationIsNewestFirst() {
        let log = DeveloperDiagnosticsLog()

        log.recordInterval(.navigationRequestToCommit, duration: .milliseconds(400), outcome: .success)
        log.recordInterval(.commitToUsefulContent, duration: .milliseconds(200), outcome: .success)
        log.recordInterval(.navigationRequestToCommit, duration: .milliseconds(120), outcome: .failure)

        let latest = log.latestIntervalPerOperation

        XCTAssertEqual(latest.map(\.operation), [.navigationRequestToCommit, .commitToUsefulContent])
        XCTAssertEqual(latest.first?.duration.diagnosticsMilliseconds, 120)
        XCTAssertEqual(latest.first?.outcome, .failure)
    }

    func testReportShortensPageIDsAndListsTimings() {
        let log = DeveloperDiagnosticsLog()
        log.recordInterval(.webViewConstruction, duration: .milliseconds(42), outcome: .success)
        log.recordRendererTermination()
        let snapshot = DiagnosticsSnapshot(
            appVersion: "0.1.4 (7)",
            appProcessID: 100,
            app: ProcessResourceSample(footprintBytes: 150 * 1_048_576, cpuPercent: 3.31),
            webContent: nil,
            web: NotionWebDiagnosticsSnapshot(
                state: .active,
                retention: .warm,
                panelIsVisible: true,
                isTypingInPage: false,
                activePageID: "0123456789abcdef0123456789abcdef",
                isShowingCustomURL: false,
                interactionStateCount: 2,
                webContentProcessID: nil
            ),
            counters: log.counters,
            latestIntervals: log.latestIntervalPerOperation,
            recentEvents: log.events
        )

        let report = snapshot.report()

        XCTAssertTrue(report.contains("Perch (pid 100): 150 MB, CPU 3.3%"), report)
        XCTAssertTrue(report.contains("Web content (no pid): unavailable"), report)
        XCTAssertTrue(report.contains("Page: …abcdef"), report)
        XCTAssertFalse(report.contains("0123456789abcdef0123456789abcdef"), report)
        XCTAssertTrue(report.contains("WebViewConstruction: 42 ms (success)"), report)
        XCTAssertTrue(report.contains("renderer exits 1"), report)
    }

    func testKeyDelaysAreTrackedPerStageAndSlowKeysAreLogged() {
        let log = DeveloperDiagnosticsLog()

        log.recordKeyDelay(.milliseconds(8), stage: .perch)
        log.recordKeyDelay(.milliseconds(120), stage: .perch)
        log.recordKeyDelay(.milliseconds(30), stage: .perch)
        log.recordKeyDelay(eventTimestamp: 10.0, stage: .page, uptime: 10.25)

        XCTAssertEqual(log.perchKeyDelay.count, 3)
        XCTAssertEqual(log.perchKeyDelay.slowCount, 1)
        XCTAssertEqual(log.perchKeyDelay.worst, .milliseconds(120))
        XCTAssertEqual(log.perchKeyDelay.last, .milliseconds(30))
        XCTAssertEqual(log.pageKeyDelay.count, 1)
        XCTAssertEqual(log.pageKeyDelay.slowCount, 1)
        XCTAssertEqual(log.pageKeyDelay.worst, .milliseconds(250))
        XCTAssertEqual(
            log.events.map(\.message),
            ["Slow key (perch): 120 ms", "Slow key (page): 250 ms"]
        )
        XCTAssertEqual(
            DiagnosticsSnapshot.describe(log.perchKeyDelay),
            "last 30 ms, worst 120 ms, slow 1 of 3"
        )

        log.reset()
        XCTAssertEqual(log.perchKeyDelay, DeveloperDiagnosticsLog.KeyDelayStats())
        XCTAssertEqual(log.pageKeyDelay, DeveloperDiagnosticsLog.KeyDelayStats())
        XCTAssertEqual(DiagnosticsSnapshot.describe(log.pageKeyDelay), "no keys yet")
    }

    func testKeyDelayClockGoingBackwardsCountsAsZero() {
        let log = DeveloperDiagnosticsLog()

        log.recordKeyDelay(eventTimestamp: 12, stage: .perch, uptime: 11)

        XCTAssertEqual(log.perchKeyDelay.last, .zero)
        XCTAssertEqual(log.perchKeyDelay.slowCount, 0)
    }

    func testKeyDelayBridgeAcceptsOnlyTrustedFiniteReadings() {
        func reading(_ body: Any, host: String = "www.notion.so", isMainFrame: Bool = true) -> Double? {
            NotionKeyDelayBridge.milliseconds(
                from: body,
                isMainFrame: isMainFrame,
                scheme: "https",
                host: host
            )
        }

        XCTAssertEqual(reading(NSNumber(value: 42.5)), 42.5)
        XCTAssertNil(reading(NSNumber(value: 42.5), host: "evil.example"))
        XCTAssertNil(reading(NSNumber(value: 42.5), isMainFrame: false))
        XCTAssertNil(reading(NSNumber(value: -1)))
        XCTAssertNil(reading(NSNumber(value: Double.nan)))
        XCTAssertNil(reading(NSNumber(value: 120_000)))
        XCTAssertNil(reading("42"))
    }

    func testDeveloperBuildsShipTheKeyDelayProbeInsideTheEditorScript() {
        let controller = WKUserContentController()
        let coordinator = NotionWebScriptMessageCoordinator()

        coordinator.install(in: controller)
        defer { coordinator.remove(from: controller) }

        XCTAssertEqual(controller.userScripts.count, 3)
        XCTAssertTrue(controller.userScripts[0].source.contains("perchKeyDelay"))
        XCTAssertTrue(
            NotionWebScriptMessageCoordinator.handlerNames.contains(NotionKeyDelayBridge.handlerName)
        )
    }

    func testFormatsLargeFootprintsInGigabytes() {
        XCTAssertEqual(DiagnosticsSnapshot.formatBytes(512 * 1_048_576), "512 MB")
        XCTAssertEqual(DiagnosticsSnapshot.formatBytes(1_536 * 1_048_576), "1.50 GB")
    }

    private func reading(
        cpu: UInt64,
        uptime: UInt64,
        footprint: UInt64 = 1
    ) -> ProcessResourceReading {
        ProcessResourceReading(
            footprintBytes: footprint,
            cpuTimeNanoseconds: cpu,
            uptimeNanoseconds: uptime
        )
    }
}
#endif
