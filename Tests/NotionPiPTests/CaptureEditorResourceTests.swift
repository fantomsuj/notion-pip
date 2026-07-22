import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class CaptureEditorResourceTests: XCTestCase {
    func testPackagedAppEditorWinsWithoutEvaluatingSwiftPMFallback() throws {
        let fixture = try ResourceFixture()
        defer { fixture.remove() }
        let packagedEditor = try fixture.createPackagedEditor()
        let swiftPMEditor = try fixture.createSwiftPMEditor()
        var evaluatedSwiftPMFallback = false

        let resolved = CaptureEditorResources.editorURL(
            appResourceRoot: fixture.appResourceRoot,
            swiftPMResourceRoot: evaluatedRoot(
                fixture.swiftPMResourceRoot,
                didEvaluate: &evaluatedSwiftPMFallback
            )
        )

        XCTAssertEqual(resolved, packagedEditor)
        XCTAssertNotEqual(resolved, swiftPMEditor)
        XCTAssertFalse(evaluatedSwiftPMFallback)
    }

    func testSwiftPMEditorIsUsedWhenPackagedResourceIsAbsent() throws {
        let fixture = try ResourceFixture()
        defer { fixture.remove() }
        let swiftPMEditor = try fixture.createSwiftPMEditor()

        let resolved = CaptureEditorResources.editorURL(
            appResourceRoot: fixture.appResourceRoot,
            swiftPMResourceRoot: fixture.swiftPMResourceRoot
        )

        XCTAssertEqual(resolved, swiftPMEditor)
    }

    func testMissingEditorResourcesLeaveCaptureSafelyUnavailable() throws {
        let fixture = try ResourceFixture()
        defer { fixture.remove() }
        let repository = try CaptureRepository(inMemory: true)

        let session = CaptureEditorSession(
            repository: repository,
            editorResourceRoots: CaptureEditorResourceRoots(
                packagedApp: fixture.appResourceRoot,
                swiftPMBundle: fixture.swiftPMResourceRoot
            )
        )

        XCTAssertEqual(session.status, .failed("The bundled editor could not be loaded."))
        XCTAssertFalse(session.webView.isLoading)
    }
}

private func evaluatedRoot(_ root: URL, didEvaluate: inout Bool) -> URL {
    didEvaluate = true
    return root
}

private final class ResourceFixture {
    let root: URL
    let appResourceRoot: URL
    let swiftPMResourceRoot: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        appResourceRoot = root.appendingPathComponent("AppResources", isDirectory: true)
        swiftPMResourceRoot = root.appendingPathComponent("SwiftPMResources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appResourceRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: swiftPMResourceRoot,
            withIntermediateDirectories: true
        )
    }

    func createPackagedEditor() throws -> URL {
        let url = appResourceRoot
            .appendingPathComponent("NotionPiP_NotionPiP.bundle", isDirectory: true)
            .appendingPathComponent("QuickCapture", isDirectory: true)
            .appendingPathComponent("index.html", isDirectory: false)
        try createFile(at: url)
        return url
    }

    func createSwiftPMEditor() throws -> URL {
        let url = swiftPMResourceRoot
            .appendingPathComponent("QuickCapture", isDirectory: true)
            .appendingPathComponent("index.html", isDirectory: false)
        try createFile(at: url)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func createFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("<!doctype html>".utf8).write(to: url)
    }
}
