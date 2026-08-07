import WebKit
import XCTest
@testable import NotionPiP

@MainActor
final class NotionWebScriptMessageCoordinatorTests: XCTestCase {
    func testInstallAndRemovalAdvanceGenerationAndOwnAllThreeBridges() {
        var removedControllers: [WKUserContentController] = []
        let coordinator = NotionWebScriptMessageCoordinator { controller in
            removedControllers.append(controller)
            controller.removeScriptMessageHandler(
                forName: NotionEditorActivityBridge.handlerName,
                contentWorld: .page
            )
            controller.removeScriptMessageHandler(
                forName: NotionScrollBridge.handlerName,
                contentWorld: .page
            )
            controller.removeScriptMessageHandler(
                forName: NotionEditorCaretBridge.handlerName,
                contentWorld: .page
            )
            controller.removeAllUserScripts()
        }
        let firstController = WKUserContentController()
        let secondController = WKUserContentController()

        let firstGeneration = coordinator.install(in: firstController)

        XCTAssertEqual(firstGeneration, 1)
        XCTAssertEqual(coordinator.generation, 1)
        XCTAssertEqual(firstController.userScripts.count, 3)
        XCTAssertTrue(
            firstController.userScripts.allSatisfy {
                $0.injectionTime == .atDocumentStart && $0.isForMainFrameOnly
            }
        )
        XCTAssertTrue(firstController.userScripts[0].source.contains("beforeinput"))
        XCTAssertTrue(firstController.userScripts[1].source.contains("pagehide"))
        XCTAssertEqual(firstController.userScripts[2].source, NotionEditorCaretBridge.script)

        coordinator.remove(from: firstController)

        XCTAssertEqual(coordinator.generation, 2)
        XCTAssertTrue(firstController.userScripts.isEmpty)
        XCTAssertEqual(removedControllers.count, 1)
        XCTAssertTrue(removedControllers[0] === firstController)

        let secondGeneration = coordinator.install(in: secondController)

        XCTAssertEqual(secondGeneration, 3)
        XCTAssertEqual(coordinator.generation, 3)
        XCTAssertEqual(secondController.userScripts.count, 3)
    }
}
