import AppKit
import XCTest
@testable import Flip

@MainActor
final class FlipRuntimeTests: XCTestCase {
    func testShortcutOccupiesThenRestoresThroughSpies() async throws {
        let harness = FlipRuntimeHarness()
        harness.runtime.start()

        harness.runtime.handleShortcut()
        try await waitUntil { harness.overlay.occupyingFrames.count == 1 }

        XCTAssertEqual(harness.runtime.session.phase, .flippingOut)
        XCTAssertEqual(harness.parker.parked.count, 1)
        XCTAssertEqual(harness.overlay.occupyingFrames.first, FlipTestSupport.target().frame)

        harness.overlay.finishOccupy()
        XCTAssertEqual(harness.runtime.session.phase, .occupying)

        harness.overlay.currentFrame = CGRect(x: 40, y: 50, width: 700, height: 500)
        harness.runtime.handleShortcut()
        XCTAssertEqual(harness.overlay.restoreCount, 1)
        XCTAssertEqual(harness.parker.restored.first?.restoreFrame.width, 700)
        XCTAssertEqual(harness.runtime.session.phase, .idle)
    }

    func testMissingPermissionsAskForGrantInsteadOfOccupying() {
        let harness = FlipRuntimeHarness(
            permissions: FlipPermissionStatus(
                accessibilityTrusted: false,
                screenRecordingAllowed: false
            )
        )
        var asked = false
        harness.runtime.onNeedsPermissions = { asked = true }
        harness.runtime.start()
        harness.runtime.handleShortcut()

        XCTAssertTrue(asked)
        XCTAssertEqual(harness.runtime.session.phase, .needsPermissions)
        XCTAssertTrue(harness.overlay.occupyingFrames.isEmpty)
    }

    func testSnapshotFailureReturnsToIdleWithoutParking() async throws {
        let harness = FlipRuntimeHarness()
        harness.snapshotter.error = .captureFailed
        harness.runtime.start()
        harness.runtime.handleShortcut()
        try await waitUntil { harness.runtime.session.phase == .idle }

        XCTAssertTrue(harness.parker.parked.isEmpty)
        XCTAssertTrue(harness.overlay.occupyingFrames.isEmpty)
        XCTAssertEqual(harness.runtime.session.lastRejection, .missingWindowIdentity)
    }

    func testTerminationRestoresAParkedWindow() async throws {
        let harness = FlipRuntimeHarness()
        harness.runtime.start()
        harness.runtime.handleShortcut()
        try await waitUntil { harness.overlay.occupyingFrames.count == 1 }
        harness.overlay.finishOccupy()

        harness.runtime.prepareForTermination()
        XCTAssertEqual(harness.overlay.dismissCount, 1)
        XCTAssertEqual(harness.parker.restored.count, 1)
        XCTAssertEqual(harness.runtime.session.phase, .idle)
        XCTAssertEqual(harness.registrar.unregisterCount, 1)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() > deadline {
                XCTFail("timed out waiting for runtime spy")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

@MainActor
private final class FlipRuntimeHarness {
    let resolver = FlipWindowResolverSpy()
    let permissions = FlipPermissionSpy()
    let snapshotter = FlipSnapshotSpy()
    let parker = FlipParkerSpy()
    let overlay = FlipOverlaySpy()
    let registrar = FlipShortcutRegistrarSpy()
    let runtime: FlipRuntime

    init(
        permissions status: FlipPermissionStatus = FlipPermissionStatus(
            accessibilityTrusted: true,
            screenRecordingAllowed: true
        )
    ) {
        resolver.target = FlipTestSupport.target()
        permissions.status = status
        let suiteName = "flip.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        runtime = FlipRuntime(
            resolver: resolver,
            permissions: permissions,
            snapshotter: snapshotter,
            parker: parker,
            overlay: overlay,
            shortcutRegistrar: registrar,
            shortcutStore: FlipShortcutStore(defaults: defaults),
            currentProcessIdentifier: 1,
            primaryScreenHeight: { 1080 },
            reducesMotion: { true }
        )
    }
}

@MainActor
private final class FlipWindowResolverSpy: FlipWindowResolving {
    var target: FlipTarget?
    func frontmostTarget() -> FlipTarget? { target }
}

@MainActor
private final class FlipPermissionSpy: FlipPermissionChecking {
    var status = FlipPermissionStatus(accessibilityTrusted: true, screenRecordingAllowed: true)
    func promptAccessibility() {}
    func requestScreenRecording() {}
}

@MainActor
private final class FlipSnapshotSpy: FlipSnapshotCapturing {
    var image = NSImage(size: NSSize(width: 10, height: 10))
    var error: FlipSnapshotError?
    func capture(windowID: CGWindowID) async throws -> NSImage {
        if let error { throw error }
        return image
    }
}

@MainActor
private final class FlipParkerSpy: FlipWindowParking {
    var parked: [FlipTarget] = []
    var restored: [FlipPairing] = []
    var parkResult: FlipParkStrategy? = .hide
    func park(_ target: FlipTarget, strategy: FlipParkStrategy) -> FlipParkStrategy? {
        parked.append(target)
        return parkResult
    }

    func restore(_ pairing: FlipPairing, primaryScreenHeight: CGFloat) -> Bool {
        restored.append(pairing)
        return true
    }
}

@MainActor
private final class FlipOverlaySpy: FlipOverlayControlling {
    var currentFrame: CGRect?
    var onFlipBack: (@MainActor () -> Void)?
    var occupyingFrames: [CGRect] = []
    var restoreCount = 0
    var dismissCount = 0
    private var occupyCompletion: (@MainActor () -> Void)?

    func presentOccupying(
        frame: CGRect,
        frontSnapshot: NSImage,
        destinationURL: URL,
        reducesMotion: Bool,
        onFinished: @escaping @MainActor () -> Void
    ) {
        occupyingFrames.append(frame)
        currentFrame = frame
        occupyCompletion = onFinished
    }

    func finishOccupy() {
        occupyCompletion?()
        occupyCompletion = nil
    }

    func restore(
        reducesMotion: Bool,
        onFinished: @escaping @MainActor (CGRect) -> Void
    ) {
        restoreCount += 1
        onFinished(currentFrame ?? .zero)
    }

    func dismissImmediately() {
        dismissCount += 1
        currentFrame = nil
    }
}

@MainActor
private final class FlipShortcutRegistrarSpy: FlipShortcutRegistering {
    var registered: [FlipShortcut] = []
    var unregisterCount = 0
    func register(shortcut: FlipShortcut, handler: @escaping @MainActor () -> Void) throws {
        registered.append(shortcut)
    }

    func unregister() {
        unregisterCount += 1
    }
}
