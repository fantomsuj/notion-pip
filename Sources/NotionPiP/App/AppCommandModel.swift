import AppKit

enum AppCommandID: Int, CaseIterable, Sendable {
    case newNotionPage
    case settings
    case gettingStarted
    case quit
}

struct AppCommand {
    let id: AppCommandID
    let title: String
    let keyEquivalent: String
    let modifierMask: NSEvent.ModifierFlags
    private let enabled: @MainActor () -> Bool
    private let action: @MainActor () -> Void

    @MainActor
    var isEnabled: Bool {
        enabled()
    }

    init(
        id: AppCommandID,
        title: String,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = .command,
        isEnabled: @escaping @MainActor () -> Bool = { true },
        action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.keyEquivalent = keyEquivalent
        self.modifierMask = modifierMask
        enabled = isEnabled
        self.action = action
    }

    @MainActor
    func perform() {
        action()
    }
}

struct AppCommandGroup {
    let commands: [AppCommand]
}

@MainActor
final class AppCommandModel {
    let groups: [AppCommandGroup]

    var commands: [AppCommand] {
        groups.flatMap(\.commands)
    }

    static var noOp: AppCommandModel {
        AppCommandModel(
            newNotionPage: {},
            settings: {},
            gettingStarted: {},
            quit: {}
        )
    }

    init(
        newNotionPage: @escaping @MainActor () -> Void,
        settings: @escaping @MainActor () -> Void,
        gettingStarted: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void
    ) {
        groups = [
            AppCommandGroup(commands: [
                AppCommand(
                    id: .newNotionPage,
                    title: "New Notion Page",
                    keyEquivalent: "n",
                    action: newNotionPage
                ),
            ]),
            AppCommandGroup(commands: [
                AppCommand(
                    id: .settings,
                    title: "Settings…",
                    keyEquivalent: ",",
                    action: settings
                ),
                AppCommand(
                    id: .gettingStarted,
                    title: "Getting Started…",
                    action: gettingStarted
                ),
            ]),
            AppCommandGroup(commands: [
                AppCommand(
                    id: .quit,
                    title: "Quit Notion PiP",
                    keyEquivalent: "q",
                    action: quit
                ),
            ]),
        ]
    }

    func command(for id: AppCommandID) -> AppCommand? {
        commands.first { $0.id == id }
    }

    func perform(_ id: AppCommandID) {
        command(for: id)?.perform()
    }
}
