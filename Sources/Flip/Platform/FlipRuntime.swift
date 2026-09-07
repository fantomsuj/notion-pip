import AppKit
import Foundation
import OSLog

@MainActor
final class FlipRuntime {
    private(set) var session = FlipSession()
    private let resolver: any FlipWindowResolving
    private let permissions: any FlipPermissionChecking
    private let snapshotter: any FlipSnapshotCapturing
    private let parker: any FlipWindowParking
    private let overlay: any FlipOverlayControlling
    private let shortcutRegistrar: any FlipShortcutRegistering
    private let shortcutStore: FlipShortcutStore
    private let currentProcessIdentifier: pid_t
    private let primaryScreenHeight: () -> CGFloat
    private let reducesMotion: () -> Bool
    private let logger = Logger(subsystem: FlipIdentity.bundleIdentifier, category: "runtime")

    var onNeedsPermissions: (@MainActor () -> Void)?
    var onSessionChanged: (@MainActor (FlipSession) -> Void)?

    private(set) var shortcut: FlipShortcut

    init(
        resolver: any FlipWindowResolving,
        permissions: any FlipPermissionChecking,
        snapshotter: any FlipSnapshotCapturing,
        parker: any FlipWindowParking,
        overlay: any FlipOverlayControlling,
        shortcutRegistrar: any FlipShortcutRegistering,
        shortcutStore: FlipShortcutStore = FlipShortcutStore(),
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        primaryScreenHeight: @escaping () -> CGFloat = {
            AccessibilityFlipWindowResolver.primaryDisplayHeight()
        },
        reducesMotion: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    ) {
        self.resolver = resolver
        self.permissions = permissions
        self.snapshotter = snapshotter
        self.parker = parker
        self.overlay = overlay
        self.shortcutRegistrar = shortcutRegistrar
        self.shortcutStore = shortcutStore
        self.currentProcessIdentifier = currentProcessIdentifier
        self.primaryScreenHeight = primaryScreenHeight
        self.reducesMotion = reducesMotion
        shortcut = shortcutStore.load()
    }

    func start() {
        overlay.onFlipBack = { [weak self] in
            self?.handleShortcut()
        }
        registerShortcut()
        publish()
    }

    func prepareForTermination() {
        if session.phase == .occupying || session.isAnimating, let pairing = session.pairing {
            overlay.dismissImmediately()
            _ = parker.restore(pairing, primaryScreenHeight: primaryScreenHeight())
        }
        shortcutRegistrar.unregister()
        session.abortToIdle()
        publish()
    }

    func handleShortcut() {
        let decision = FlipTogglePolicy.decision(
            session: session,
            permissions: permissions.status,
            frontmost: resolver.frontmostTarget(),
            currentProcessIdentifier: currentProcessIdentifier
        )
        switch decision {
        case .ignore:
            return
        case .showPermissions:
            session.notePermissionsMissing()
            publish()
            onNeedsPermissions?()
        case let .reject(rejection):
            session.reject(rejection)
            logger.notice(
                "Flip rejected occupancy reason=\(String(describing: rejection), privacy: .public)"
            )
            publish()
        case let .restore(pairing):
            beginRestore(pairing)
        case let .occupy(target):
            session.beginCapture(target: target, parkStrategy: .hide)
            publish()
            Task { await occupyCapturedTarget() }
        }
    }

    func retryAfterGrantingPermissions() {
        if permissions.status.isReady {
            session.abortToIdle()
            publish()
            handleShortcut()
        } else {
            session.notePermissionsMissing()
            publish()
        }
    }

    private func occupyCapturedTarget() async {
        guard let target = session.pairing?.target, session.phase == .capturing else { return }
        let snapshot: NSImage
        do {
            snapshot = try await snapshotter.capture(windowID: target.windowID)
        } catch {
            session.reject(.missingWindowIdentity)
            logger.error("Flip snapshot failed")
            publish()
            return
        }

        session.beginFlippingOut()
        publish()
        overlay.presentOccupying(
            frame: target.frame,
            frontSnapshot: snapshot,
            destinationURL: FlipDestination.notionHome,
            reducesMotion: reducesMotion()
        ) { [weak self] in
            self?.session.beginOccupancy()
            self?.publish()
        }

        guard let parked = parker.park(target, strategy: .hide) else {
            overlay.dismissImmediately()
            session.reject(.missingWindow)
            publish()
            return
        }
        session.updateParkStrategy(parked)
        publish()
    }

    private func beginRestore(_ pairing: FlipPairing) {
        session.beginFlippingIn()
        if let frame = overlay.currentFrame {
            session.updateOverlayFrame(frame)
        }
        publish()
        overlay.restore(reducesMotion: reducesMotion()) { [weak self] frame in
            guard let self else { return }
            self.session.updateOverlayFrame(frame)
            if let current = self.session.pairing {
                _ = self.parker.restore(current, primaryScreenHeight: self.primaryScreenHeight())
            }
            self.session.completeRestore()
            self.publish()
        }
    }

    private func registerShortcut() {
        do {
            try shortcutRegistrar.register(shortcut: shortcut) { [weak self] in
                self?.handleShortcut()
            }
        } catch {
            logger.error("Flip shortcut registration failed")
        }
    }

    private func publish() {
        onSessionChanged?(session)
    }
}
