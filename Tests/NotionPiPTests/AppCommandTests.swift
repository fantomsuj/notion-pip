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

    func testStatusItemRouterOpensMenuForBothMouseButtons() {
        var menuCount = 0
        let router = StatusItemEventRouter(
            onMenu: { menuCount += 1 }
        )

        router.handle(eventType: .rightMouseUp)
        XCTAssertEqual(menuCount, 1)

        router.handle(eventType: .leftMouseUp)
        XCTAssertEqual(menuCount, 2)
    }

    func testStatusMenuContextCommandsMatchEveryPresentationState() {
        XCTAssertEqual(
            StatusMenuContextCommand(presentationState: .visible),
            .stash
        )
        XCTAssertEqual(
            StatusMenuContextCommand(presentationState: .stashed),
            .show
        )
        XCTAssertEqual(
            StatusMenuContextCommand(presentationState: .unavailable),
            .openSettings
        )
        XCTAssertEqual(StatusMenuContextCommand.stash.title, "Stash Notion PiP")
        XCTAssertEqual(StatusMenuContextCommand.show.title, "Show Notion PiP")
        XCTAssertEqual(StatusMenuContextCommand.openSettings.title, "Open Settings…")
    }

    func testStatusItemMenuPrependsContextWhileRetainingSharedCommands() {
        let model = makeModel(events: { _ in })

        let menu = AppKitCommandMenuFactory.makeStatusItemMenu(
            commandModel: model,
            contextualCommand: .stash
        )
        let commandItems = menu.items.filter { !$0.isSeparatorItem }

        XCTAssertEqual(commandItems.first?.title, "Stash Notion PiP")
        XCTAssertEqual(
            Array(commandItems.dropFirst().map(\.title)),
            model.commands.map(\.title)
        )
        XCTAssertEqual(commandItems.first?.tag, StatusMenuContextCommand.stash.menuItemTag)
    }

    private func makeModel(events: @escaping (AppCommandID) -> Void) -> AppCommandModel {
        AppCommandModel(
            quickCapture: { events(.quickCapture) },
            settings: { events(.settings) },
            quit: { events(.quit) }
        )
    }
}
