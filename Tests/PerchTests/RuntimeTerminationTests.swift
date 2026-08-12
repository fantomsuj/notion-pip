import AppKit
import XCTest
@testable import Perch

@MainActor
final class RuntimeTerminationTests: XCTestCase {
    func testTerminationStopsQuickCopy() async {
        let runtime = makeRuntime(panel: RuntimePanelCoordinator())
        var quickCopyStopCount = 0
        var terminationReplies: [Bool] = []
        let appDelegate = AppDelegate { _, shouldTerminate in
            terminationReplies.append(shouldTerminate)
        }
        AppStartup.start(
            runtime: runtime,
            appDelegate: appDelegate,
            quickCopyTerminationAction: { quickCopyStopCount += 1 }
        )

        XCTAssertEqual(
            appDelegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        await waitUntilRuntimeCondition { terminationReplies == [true] }
        XCTAssertEqual(quickCopyStopCount, 1)
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

        runtime.activate(page: second, source: .pagePicker)
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

}
