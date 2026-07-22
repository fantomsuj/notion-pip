import AppKit

enum AppCommandID: Int, CaseIterable, Sendable {
    case quickCapture
    case changePinnedPage
    case settings
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
            quickCapture: {},
            changePinnedPage: {},
            settings: {},
            quit: {}
        )
    }

    init(
        quickCapture: @escaping @MainActor () -> Void,
        changePinnedPage: @escaping @MainActor () -> Void,
        settings: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void
    ) {
        groups = [
            AppCommandGroup(commands: [
                AppCommand(
                    id: .quickCapture,
                    title: "Quick Capture",
                    keyEquivalent: "n",
                    action: quickCapture
                ),
            ]),
            AppCommandGroup(commands: [
                AppCommand(
                    id: .changePinnedPage,
                    title: "Change Pinned Page…",
                    action: changePinnedPage
                ),
            ]),
            AppCommandGroup(commands: [
                AppCommand(
                    id: .settings,
                    title: "Settings…",
                    keyEquivalent: ",",
                    action: settings
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
