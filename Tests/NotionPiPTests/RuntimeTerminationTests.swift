import AppKit
import XCTest
@testable import NotionPiP

@MainActor
final class RuntimeTerminationTests: XCTestCase {
    func testTerminationStopsQuickCopyBeforeWaitingForOtherWork() async {
        let runtime = makeRuntime(panel: RuntimePanelCoordinator())
        let participant = RuntimeTerminationParticipant()
        var quickCopyStopCount = 0
        var terminationReplies: [Bool] = []
        let appDelegate = AppDelegate { _, shouldTerminate in
            terminationReplies.append(shouldTerminate)
        }
        AppStartup.start(
            runtime: runtime,
            appDelegate: appDelegate,
            quickCopyTerminationAction: { quickCopyStopCount += 1 },
            terminationParticipantProvider: { participant }
        )

        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        try? await participant.waitUntilCallCount(1)

        XCTAssertEqual(quickCopyStopCount, 1)
        XCTAssertTrue(terminationReplies.isEmpty)
        participant.finish(with: true)
        await waitUntilRuntimeCondition { terminationReplies == [true] }
    }

    func testTerminationWaitsForPendingAndNewerPageSavesBeforeReplying() async throws {
        let repository = RuntimePinnedPageRepository(delaySaves: true)
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            pageRepository: repository
        )
        var terminationReplies: [Bool] = []
        let appDelegate = AppDelegate { _, shouldTerminate in
            terminationReplies.append(shouldTerminate)
        }
        let first = try makePage(id: firstPageID, title: "First")
        let second = try makePage(id: secondPageID, title: "Second")

        AppStartup.start(runtime: runtime, appDelegate: appDelegate)
        runtime.activate(page: first, source: .typedURL)
        try await repository.waitUntilSaveCount(1)

        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        for _ in 0 ..< 3 {
            await Task.yield()
        }
        XCTAssertTrue(terminationReplies.isEmpty)

        runtime.activate(page: second, source: .notionSearch)
        await repository.finishSave(pageID: firstPageID)
        try await repository.waitUntilSaveCount(2)
        for _ in 0 ..< 3 {
            await Task.yield()
        }
        XCTAssertTrue(terminationReplies.isEmpty)

        await repository.finishSave(pageID: secondPageID)
        await waitUntilRuntimeCondition { terminationReplies == [true] }
        let savedPageIDs = await repository.savedPageIDs()
        XCTAssertEqual(savedPageIDs, [firstPageID, secondPageID])
    }

    func testTerminationRepliesAfterPendingPageSaveFails() async throws {
        let repository = RuntimePinnedPageRepository(
            delaySaves: true,
            failingPageIDs: [firstPageID]
        )
        let runtime = makeRuntime(
            panel: RuntimePanelCoordinator(),
            pageRepository: repository
        )
        var terminationReplies: [Bool] = []
        let appDelegate = AppDelegate { _, shouldTerminate in
            terminationReplies.append(shouldTerminate)
        }
        let page = try makePage(id: firstPageID, title: "Failure")

        AppStartup.start(runtime: runtime, appDelegate: appDelegate)
        runtime.activate(page: page, source: .typedURL)
        try await repository.waitUntilSaveCount(1)

        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        for _ in 0 ..< 3 {
            await Task.yield()
        }
        XCTAssertTrue(terminationReplies.isEmpty)

        await repository.finishSave(pageID: firstPageID)
        await waitUntilRuntimeCondition { terminationReplies == [true] }
    }

    func testRepeatedTerminationRequestsShareOneLiveCaptureFlush() async throws {
        let runtime = makeRuntime(panel: RuntimePanelCoordinator())
        let participant = RuntimeTerminationParticipant()
        var terminationReplies: [Bool] = []
        let appDelegate = AppDelegate { _, shouldTerminate in
            terminationReplies.append(shouldTerminate)
        }
        AppStartup.start(
            runtime: runtime,
            appDelegate: appDelegate,
            terminationParticipantProvider: { participant }
        )

        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        try await participant.waitUntilCallCount(1)
        XCTAssertTrue(terminationReplies.isEmpty)

        participant.finish(with: true)
        await waitUntilRuntimeCondition { terminationReplies == [true] }
        XCTAssertEqual(participant.callCount, 1)
    }

    func testCaptureFlushFailureCancelsTerminationAndAllowsRetry() async {
        let runtime = makeRuntime(panel: RuntimePanelCoordinator())
        let participant = RuntimeImmediateTerminationParticipant(
            results: [false, true]
        )
        var terminationReplies: [Bool] = []
        let appDelegate = AppDelegate { _, shouldTerminate in
            terminationReplies.append(shouldTerminate)
        }
        AppStartup.start(
            runtime: runtime,
            appDelegate: appDelegate,
            terminationParticipantProvider: { participant }
        )

        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        await waitUntilRuntimeCondition { terminationReplies == [false] }

        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        await waitUntilRuntimeCondition { terminationReplies == [false, true] }
        XCTAssertEqual(participant.callCount, 2)
    }
}

@MainActor
private final class RuntimeTerminationParticipant: ApplicationTerminationParticipating {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<Bool, Never>?

    func prepareForTermination() async -> Bool {
        callCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilCallCount(_ count: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while callCount < count {
            guard clock.now < deadline else {
                throw RuntimeTestWaitError.timedOut("termination participant call")
            }
            await Task.yield()
        }
    }

    func finish(with result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
private final class RuntimeImmediateTerminationParticipant:
    ApplicationTerminationParticipating {
    private var results: [Bool]
    private(set) var callCount = 0

    init(results: [Bool]) {
        self.results = results
    }

    func prepareForTermination() async -> Bool {
        callCount += 1
        return results.removeFirst()
    }
}
