import AppKit
import XCTest
@testable import NotionPiP

@MainActor
final class AppCommandTests: XCTestCase {
    func testSharedCommandsHaveStableGroupsLabelsAndShortcuts() {
        let model = makeModel(events: { _ in })

        XCTAssertEqual(model.groups.map { $0.commands.map(\.id) }, [
            [.quickCapture],
            [.settings],
            [.quit],
        ])
        XCTAssertEqual(model.commands.map(\.title), [
            "Quick Capture",
            "Settings…",
            "Quit Notion PiP",
        ])
        XCTAssertEqual(model.command(for: .quickCapture)?.keyEquivalent, "n")
        XCTAssertEqual(model.command(for: .settings)?.keyEquivalent, ",")
        XCTAssertEqual(model.command(for: .quit)?.keyEquivalent, "q")
        XCTAssertTrue(model.commands.allSatisfy(\.isEnabled))
    }

    func testSharedCommandsInvokeEachActionExactlyOnce() {
        var events: [AppCommandID] = []
        let model = makeModel { events.append($0) }

        AppCommandID.allCases.forEach(model.perform)

        XCTAssertEqual(events, AppCommandID.allCases)
    }

    func testAppKitMenuRendersTheSharedCommandDefinition() {
        let model = makeModel(events: { _ in })

        let menu = AppKitCommandMenuFactory.make(commandModel: model)
        let commandItems = menu.items.filter { !$0.isSeparatorItem }

        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertEqual(commandItems.map(\.title), model.commands.map(\.title))
        XCTAssertEqual(commandItems.map(\.keyEquivalent), model.commands.map(\.keyEquivalent))
        XCTAssertEqual(menu.items.filter(\.isSeparatorItem).count, model.groups.count - 1)
    }

    func testPiPToolbarMenuRendersEverySharedCommand() {
        let model = makeModel(events: { _ in })
        let toolbarMenu = PiPAppCommandMenu(commandModel: model)

        XCTAssertEqual(toolbarMenu.commandIDs, AppCommandID.allCases)
        XCTAssertEqual(toolbarMenu.symbolName, "ellipsis.circle")
        XCTAssertEqual(PiPChromeView.primaryActionID, .quickCapture)
        XCTAssertEqual(PiPChromeView.primaryActionAccessibilityLabel, "Quick Capture")
    }

    func testStatusItemRouterUsesExplicitMouseEventType() {
        var regularClickCount = 0
        var menuCount = 0
        let router = StatusItemEventRouter(
            onRegularClick: { regularClickCount += 1 },
            onMenu: { menuCount += 1 }
        )

        router.handle(eventType: .rightMouseUp)
        XCTAssertEqual(regularClickCount, 0)
        XCTAssertEqual(menuCount, 1)

        router.handle(eventType: .leftMouseUp)
        XCTAssertEqual(regularClickCount, 1)
        XCTAssertEqual(menuCount, 1)
    }

    private func makeModel(events: @escaping (AppCommandID) -> Void) -> AppCommandModel {
        AppCommandModel(
            quickCapture: { events(.quickCapture) },
            settings: { events(.settings) },
            quit: { events(.quit) }
        )
    }
}
