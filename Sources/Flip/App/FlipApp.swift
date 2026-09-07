import AppKit
import OSLog

@main
enum FlipApp {
    static func main() {
        do {
            try FlipApplicationLaunch.run(
                claimInstance: {
                    try FlipApplicationInstanceCoordinator().claim()
                },
                prepareApplication: FlipComposition.init,
                runApplication: { composition, _ in
                    let appDelegate = FlipAppDelegate()
                    let application = NSApplication.shared
                    application.delegate = appDelegate
                    application.setActivationPolicy(.accessory)
                    application.mainMenu = FlipMenuFactory.make()
                    composition.start(appDelegate: appDelegate)
                    application.run()
                }
            )
        } catch {
            Logger(subsystem: FlipIdentity.bundleIdentifier, category: "lifecycle")
                .fault("Unable to claim the Flip instance lock")
        }
    }
}

@MainActor
final class FlipAppDelegate: NSObject, NSApplicationDelegate {
    private var prepareForTermination: (@MainActor () -> Void)?

    func bind(prepareForTermination: @escaping @MainActor () -> Void) {
        self.prepareForTermination = prepareForTermination
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        prepareForTermination?()
        return .terminateNow
    }
}

@MainActor
private final class FlipComposition {
    let runtime: FlipRuntime
    private let permissions: FlipPermissionProbe
    private let overlay: FlipOverlayController
    private let permissionPresenter: FlipPermissionWindowPresenter
    private var statusItemController: FlipStatusItemController?

    init() {
        let permissions = FlipPermissionProbe()
        let overlay = FlipOverlayController()
        let runtime = FlipRuntime(
            resolver: AccessibilityFlipWindowResolver(),
            permissions: permissions,
            snapshotter: ScreenCaptureKitSnapshotter(),
            parker: AccessibilityFlipWindowParking(),
            overlay: overlay,
            shortcutRegistrar: CarbonFlipShortcutRegistrar()
        )
        let permissionPresenter = FlipPermissionWindowPresenter(
            status: { permissions.status },
            shortcut: { runtime.shortcut },
            onGrantAccessibility: permissions.promptAccessibility,
            onGrantScreenRecording: permissions.requestScreenRecording,
            onContinue: runtime.retryAfterGrantingPermissions
        )
        runtime.onNeedsPermissions = { [weak permissionPresenter] in
            permissionPresenter?.show()
        }
        self.permissions = permissions
        self.overlay = overlay
        self.runtime = runtime
        self.permissionPresenter = permissionPresenter
    }

    func start(appDelegate: FlipAppDelegate) {
        statusItemController = FlipStatusItemController(
            runtime: runtime,
            showPermissions: { [weak permissionPresenter] in
                permissionPresenter?.show()
            }
        )
        appDelegate.bind { [weak self] in
            self?.runtime.prepareForTermination()
        }
        runtime.start()
        if !permissions.status.isReady {
            permissionPresenter.show()
        }
    }
}

enum FlipMenuFactory {
    static func make() -> NSMenu {
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Flip",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Flip",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)
        return menu
    }
}
