import XCTest
@testable import Perch

@MainActor
final class AgentStreamingServiceTests: XCTestCase {
    func testDisabledByDefaultAndDoesNotStartServer() {
        let defaults = UserDefaults(suiteName: "AgentStreamingServiceTests.\(UUID().uuidString)")!
        let store = AgentStreamingPreferenceStore(defaults: defaults)
        let controller = AgentStreamController(
            target: AgentStreamingServiceTargetSpy(),
            notifier: AgentStreamNotifierNoOp()
        )
        let service = AgentStreamingService(
            controller: controller,
            preferenceStore: store
        )

        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(service.state, .disabled)
        service.startIfPreferred()
        XCTAssertEqual(service.state, .disabled)
    }

    func testSkillInstallerWritesSameSkillForEveryTarget() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-skill-home-\(UUID().uuidString)", isDirectory: true)
        let installer = AgentStreamSkillInstaller(
            homeDirectoryURL: home,
            bundledSkillProvider: { "# skill\n" }
        )
        for target in AgentSkillTarget.allCases {
            let destination = try installer.install(for: target)
            let contents = try String(contentsOf: destination, encoding: .utf8)
            XCTAssertEqual(contents, "# skill\n")
            XCTAssertEqual(destination.lastPathComponent, "SKILL.md")
            XCTAssertTrue(
                destination.path.contains("/skills/stream-to-perch/"),
                "expected \(target) destination under a skills/stream-to-perch directory, got \(destination.path)"
            )
        }
        try? FileManager.default.removeItem(at: home)
    }

    func testBundledSkillDoesNotFavorAnySingleAgent() throws {
        let markdown = try AgentStreamSkillDocument.load()
        XCTAssertFalse(markdown.contains("\"client\": \"cursor\""))
        XCTAssertFalse(markdown.contains("\"label\": \"Cursor\""))
    }

    func testBundledSkillMentionsAcceptToPaste() throws {
        let markdown = try AgentStreamSkillDocument.load()
        XCTAssertTrue(markdown.contains("accept_to_paste"))
        XCTAssertTrue(markdown.contains("text/markdown"))
        XCTAssertTrue(markdown.contains("Accept"))
    }

    func testBundledSkillCoversProtocolFrictionPoints() throws {
        let markdown = try AgentStreamSkillDocument.load()
        XCTAssertTrue(markdown.contains("Content-Type: application/json"))
        XCTAssertTrue(markdown.contains("JSON body field"))
        XCTAssertTrue(markdown.contains("Do not send `Content-Type: text/markdown`"))
        XCTAssertTrue(markdown.contains("targetAvailable"))
        XCTAssertTrue(markdown.contains("/streams/{id}/cancel"))
        XCTAssertTrue(markdown.contains("GET` | `/streams/{id}`"))
        XCTAssertTrue(markdown.contains(#""error":{"#))
        XCTAssertTrue(markdown.contains("Branch on `error.code`"))
        XCTAssertTrue(markdown.contains("required **only** on create"))
        XCTAssertTrue(markdown.contains("nextSequence"))
        XCTAssertFalse(markdown.contains("assembledText"))
        XCTAssertTrue(markdown.contains("Unknown route."))
    }

    func testBundledSkillMatchesRepositorySkillFile() throws {
        let repoSkillURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("agent-skills/stream-to-perch/SKILL.md")
        let repoSkill = try String(contentsOf: repoSkillURL, encoding: .utf8)
        let bundled = try AgentStreamSkillDocument.load()
        XCTAssertEqual(
            bundled.trimmingCharacters(in: .whitespacesAndNewlines),
            repoSkill.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testCopyConnectionDetailsUsesJSONContentTypeHeader() {
        let details = AgentStreamingService.connectionDetailsText(
            baseURL: "http://127.0.0.1:9/v1"
        )
        XCTAssertTrue(details.contains("HTTP header Content-Type: application/json"))
        XCTAssertTrue(details.contains("JSON body field contentType: text/markdown"))
        XCTAssertFalse(details.contains("Content-Type: text/markdown\n"))
        XCTAssertFalse(details.contains("Bearer ey"))
    }

    func testQuickOffOnToggleLeavesListenerRunning() async throws {
        let defaults = UserDefaults(suiteName: "AgentStreamingServiceTests.\(UUID().uuidString)")!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let discoveryURL = directory.appendingPathComponent("agent-server.json")
        let controller = AgentStreamController(
            target: AgentStreamingServiceTargetSpy(),
            notifier: AgentStreamNotifierNoOp()
        )
        let server = AgentStreamHTTPServer(
            gateway: AgentStreamHTTPGateway(controller: controller),
            discoveryStore: AgentStreamDiscoveryStore(fileURL: discoveryURL),
            processIdentifier: 55_556
        )
        let service = AgentStreamingService(
            controller: controller,
            preferenceStore: AgentStreamingPreferenceStore(defaults: defaults),
            server: server
        )

        service.setEnabled(true)
        service.setEnabled(false)
        service.setEnabled(true)

        for _ in 0..<500 {
            if case .ready = service.state { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .ready = service.state else {
            XCTFail("Expected the listener to be ready, got \(service.state)")
            await service.prepareForTermination()
            return
        }
        // Let any stop left over from the toggle land if it was going to.
        try await Task.sleep(for: .milliseconds(300))

        let running = await server.isRunning
        XCTAssertTrue(running)
        XCTAssertTrue(FileManager.default.fileExists(atPath: discoveryURL.path))

        await service.prepareForTermination()
        let runningAfterQuit = await server.isRunning
        XCTAssertFalse(runningAfterQuit)
        XCTAssertFalse(FileManager.default.fileExists(atPath: discoveryURL.path))
    }
}

@MainActor
private final class AgentStreamingServiceTargetSpy: AgentStreamTarget {
    var isAgentStreamTargetAvailable = true
    var agentStreamOpaquePageID: String? = "page"

    func rememberCurrentEditorCursor(
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        completion(false)
    }

    func pasteMarkdownAtSavedEditorCursor(
        _ markdown: String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        completion(false)
    }
}
