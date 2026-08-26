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

    func testSkillInstallerWritesCursorSkill() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-skill-\(UUID().uuidString)", isDirectory: true)
        let installer = AgentStreamSkillInstaller(
            destinationDirectoryURL: temp,
            bundledSkillProvider: { "# skill\n" }
        )
        let destination = try installer.install()
        let contents = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertEqual(contents, "# skill\n")
        XCTAssertEqual(destination.lastPathComponent, "SKILL.md")
        try? FileManager.default.removeItem(at: temp)
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
