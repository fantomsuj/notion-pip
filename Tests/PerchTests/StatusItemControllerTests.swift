import AppKit
import XCTest
@testable import Perch

@MainActor
final class StatusItemControllerTests: XCTestCase {
    func testGlyphChangePreservesHoverSeparation() throws {
        let harness = try makeHarness()

        harness.controller.mouseEntered(with: NSEvent())
        harness.runtime.publishStatusItemSession(sessionState: .loading, loginState: .idle)

        try assertImage(
            harness.image,
            equals: StatusItemGlyphPolicy.makeImage(
                for: .loading,
                separation: StatusItemMotionPolicy.markHoverSeparation
            )
        )
    }

    func testSummonNodComposesWithExistingHoverSeparation() throws {
        let harness = try makeHarness()

        harness.controller.mouseEntered(with: NSEvent())
        harness.runtime.acknowledgeSummon()

        try assertImage(
            harness.image,
            equals: StatusItemGlyphPolicy.makeImage(
                for: .visible,
                separation: StatusItemMotionPolicy.markHoverSeparation,
                verticalOffset: StatusItemMotionPolicy.nodTranslation
            )
        )
    }

    func testHoverDuringNodPersistsAfterNodRestoration() async throws {
        let harness = try makeHarness()

        harness.runtime.acknowledgeSummon()
        harness.controller.mouseEntered(with: NSEvent())

        try assertImage(
            harness.image,
            equals: StatusItemGlyphPolicy.makeImage(
                for: .visible,
                separation: StatusItemMotionPolicy.markHoverSeparation,
                verticalOffset: StatusItemMotionPolicy.nodTranslation
            )
        )

        let restoredImage = StatusItemGlyphPolicy.makeImage(
            for: .visible,
            separation: StatusItemMotionPolicy.markHoverSeparation
        )
        try await waitForImage({ harness.image }, equals: restoredImage)

        try assertImage(
            harness.image,
            equals: restoredImage
        )
    }

    private func makeHarness() throws -> StatusItemControllerHarness {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        runtime.activate(
            page: try makePage(id: firstPageID, title: "Status Item"),
            source: .typedURL
        )
        let statusBar = CapturingStatusBar()
        let controller = StatusItemController(
            runtime: runtime,
            commandModel: .noOp,
            statusBar: statusBar,
            reducesMotion: { false }
        )
        return StatusItemControllerHarness(
            runtime: runtime,
            statusBar: statusBar,
            controller: controller
        )
    }

    private func assertImage(
        _ image: NSImage?,
        equals expectedImage: NSImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let image = try XCTUnwrap(image, file: file, line: line)
        let actual = rasterizeStatusItemImage(image, file: file, line: line)
        let expected = rasterizeStatusItemImage(expectedImage, file: file, line: line)
        XCTAssertEqual(
            actual.differingPixelCount(from: expected),
            0,
            "Expected status-item images to have identical visible pixels",
            file: file,
            line: line
        )
    }

    private func waitForImage(
        _ image: @escaping @MainActor () -> NSImage?,
        equals expectedImage: NSImage,
        timeout: Duration = .seconds(1)
    ) async throws {
        let expected = rasterizeStatusItemImage(expectedImage)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var finalDifferingPixelCount: Int?

        while true {
            if let actualImage = image() {
                let actual = rasterizeStatusItemImage(actualImage)
                finalDifferingPixelCount = actual.differingPixelCount(from: expected)
                if finalDifferingPixelCount == 0 {
                    return
                }
            }

            guard clock.now < deadline else {
                let finalState = finalDifferingPixelCount.map(String.init) ?? "no image"
                XCTFail(
                    "Timed out after 1 second waiting for the status-item image to restore after nod; final differing pixel count: \(finalState)"
                )
                return
            }

            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private struct StatusItemControllerHarness {
    let runtime: AppRuntime
    let statusBar: CapturingStatusBar
    let controller: StatusItemController

    var image: NSImage? {
        statusBar.capturedStatusItem?.button?.image
    }
}

private final class CapturingStatusBar: NSStatusBar {
    private(set) var capturedStatusItem: NSStatusItem?

    override func statusItem(withLength length: CGFloat) -> NSStatusItem {
        let item = super.statusItem(withLength: length)
        capturedStatusItem = item
        return item
    }
}
