import AppKit
import XCTest

@testable import Perch

@MainActor
final class AppCommandTests: XCTestCase {
    func testSharedCommandsHaveStableGroupsLabelsAndShortcuts() {
        let model = makeModel(events: { _ in })

        XCTAssertEqual(
            model.groups.map { $0.commands.map(\.id) },
            [
                [.newNotionPage],
                [.settings, .gettingStarted, .checkForUpdates],
                [.quit],
            ])
        XCTAssertEqual(
            model.commands.map(\.title),
            [
                "New Notion Page",
                "Settings…",
                "Getting Started…",
                "Check for Updates…",
                "Quit Perch",
            ])
        XCTAssertEqual(model.command(for: .newNotionPage)?.keyEquivalent, "n")
        XCTAssertEqual(model.command(for: .settings)?.keyEquivalent, ",")
        XCTAssertEqual(model.command(for: .gettingStarted)?.keyEquivalent, "")
        XCTAssertEqual(model.command(for: .checkForUpdates)?.keyEquivalent, "")
        XCTAssertEqual(model.command(for: .quit)?.keyEquivalent, "q")
        XCTAssertTrue(model.commands.allSatisfy(\.isEnabled))
    }

    func testCheckForUpdatesReflectsUpdaterAvailability() throws {
        let canCheck = AppCommandBoolean(false)
        var checkCount = 0
        let model = AppCommandModel(
            newNotionPage: {},
            settings: {},
            gettingStarted: {},
            canCheckForUpdates: { canCheck.value },
            checkForUpdates: { checkCount += 1 },
            quit: {}
        )
        let command = try XCTUnwrap(model.command(for: .checkForUpdates))

        XCTAssertFalse(command.isEnabled)
        canCheck.value = true
        XCTAssertTrue(command.isEnabled)

        command.perform()
        XCTAssertEqual(checkCount, 1)
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
        XCTAssertEqual(toolbarMenu.symbolName, "ellipsis")
        XCTAssertEqual(PiPChromeView.primaryActionID, .newNotionPage)
        XCTAssertEqual(PiPChromeView.primaryActionAccessibilityLabel, "New Notion Page")
        XCTAssertEqual(PiPChromeView.primaryActionHelp, "Create a new page in Perch")
        XCTAssertEqual(PiPChromeView.pageSwitcherAccessibilityLabel, "Search Notion pages")
        XCTAssertEqual(PiPChromeView.pageSwitcherHelp, "Open Notion search (⌘K)")
    }

    func testPanelSizeMenuOpensSettingsWithoutBuiltInPresetRows() throws {
        let defaultsName = "AppCommandTests.PanelSizes.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        let controller = PanelSizeController(
            store: PanelSizePreferencesStore(defaults: defaults)
        )
        let model = makeModel(events: { _ in })

        let menu = AppKitCommandMenuFactory.make(
            commandModel: model,
            panelSizeController: controller
        )
        let panelSizeItem = try XCTUnwrap(menu.item(withTitle: "Panel Size…"))
        XCTAssertNil(panelSizeItem.submenu)
        XCTAssertEqual(
            panelSizeItem.representedObject as? String,
            AppKitCommandMenuFactory.managePanelSizesMarker
        )
        XCTAssertTrue(panelSizeItem.isEnabled)
        XCTAssertNil(menu.item(withTitle: "Horizontal"))
        XCTAssertNil(menu.item(withTitle: "Vertical"))

        let toolbarMenu = PiPAppCommandMenu(
            commandModel: model,
            panelSizeController: controller
        )
        XCTAssertTrue(toolbarMenu.panelSizeController === controller)
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
        XCTAssertEqual(StatusMenuContextCommand.stash.title, "Stash Perch")
        XCTAssertEqual(StatusMenuContextCommand.show.title, "Show Perch")
        XCTAssertEqual(StatusMenuContextCommand.openSettings.title, "Open Settings…")
    }

    func testStatusItemMenuPrependsContextWhileRetainingSharedCommands() {
        let model = makeModel(events: { _ in })

        let menu = AppKitCommandMenuFactory.makeStatusItemMenu(
            commandModel: model,
            contextualCommand: .stash
        )
        let commandItems = menu.items.filter { !$0.isSeparatorItem }

        XCTAssertEqual(commandItems.first?.title, "Stash Perch")
        XCTAssertEqual(
            Array(commandItems.dropFirst().map(\.title)),
            model.commands.map(\.title)
        )
        XCTAssertEqual(commandItems.first?.tag, StatusMenuContextCommand.stash.menuItemTag)
    }

    func testStatusItemMenuRetainsPanelSizeItemAfterContextualCommand() throws {
        let defaultsName = "AppCommandTests.StatusPanelSizes.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        let controller = PanelSizeController(
            store: PanelSizePreferencesStore(defaults: defaults)
        )

        let menu = AppKitCommandMenuFactory.makeStatusItemMenu(
            commandModel: makeModel(events: { _ in }),
            contextualCommand: .show,
            panelSizeController: controller
        )

        XCTAssertEqual(menu.items.first?.title, "Show Perch")
        XCTAssertNotNil(menu.item(withTitle: "Panel Size…"))
        XCTAssertNil(menu.item(withTitle: "Panel Size…")?.submenu)
        XCTAssertNil(menu.item(withTitle: "Horizontal"))
        XCTAssertNil(menu.item(withTitle: "Vertical"))
    }

    private func makeModel(events: @escaping (AppCommandID) -> Void) -> AppCommandModel {
        AppCommandModel(
            newNotionPage: { events(.newNotionPage) },
            settings: { events(.settings) },
            gettingStarted: { events(.gettingStarted) },
            canCheckForUpdates: { true },
            checkForUpdates: { events(.checkForUpdates) },
            quit: { events(.quit) }
        )
    }
}

@MainActor
private final class AppCommandBoolean {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}
