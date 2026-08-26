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

    func testSkillDocumentDoesNotFavorAnySingleAgent() {
        XCTAssertFalse(AgentStreamSkillDocument.markdown.contains("\"client\": \"cursor\""))
        XCTAssertFalse(AgentStreamSkillDocument.markdown.contains("\"label\": \"Cursor\""))
    }

    func testSkillDocumentMentionsAcceptToPaste() {
        XCTAssertTrue(
            AgentStreamSkillDocument.markdown.contains("accept_to_paste")
        )
        XCTAssertTrue(
            AgentStreamSkillDocument.markdown.contains("text/markdown")
        )
        XCTAssertTrue(
            AgentStreamSkillDocument.markdown.contains("Accept")
        )
    }

    func testSkillDocumentCoversProtocolFrictionPoints() {
        let markdown = AgentStreamSkillDocument.markdown
        XCTAssertTrue(markdown.contains("Content-Type: application/json"))
        XCTAssertTrue(markdown.contains("JSON body field"))
        XCTAssertTrue(markdown.contains("Do not send `Content-Type: text/markdown`"))
        XCTAssertTrue(markdown.contains("targetAvailable"))
        XCTAssertTrue(markdown.contains("/streams/{id}/cancel"))
        XCTAssertTrue(markdown.contains("GET` | `/streams/{id}`"))
        XCTAssertTrue(markdown.contains(#""error":{"#))
        XCTAssertTrue(markdown.contains("Branch on `error.code`"))
        XCTAssertTrue(markdown.contains("required **only** on create"))
        XCTAssertTrue(markdown.contains("assembledText"))
        XCTAssertTrue(markdown.contains("Unknown route."))
    }

    func testBundledSkillMatchesRepositorySkillFile() throws {
        let repoSkillURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("agent-skills/stream-to-perch/SKILL.md")
        let repoSkill = try String(contentsOf: repoSkillURL, encoding: .utf8)
        XCTAssertEqual(
            AgentStreamSkillDocument.markdown.trimmingCharacters(in: .whitespacesAndNewlines),
            repoSkill.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
