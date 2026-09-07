import Foundation

enum FlipPhase: Equatable, Sendable {
    case idle
    case needsPermissions
    case capturing
    case flippingOut
    case occupying
    case flippingIn
}

struct FlipSession: Equatable, Sendable {
    var phase: FlipPhase = .idle
    var pairing: FlipPairing?
    var lastRejection: FlipOccupancyRejection?

    var isAnimating: Bool {
        switch phase {
        case .capturing, .flippingOut, .flippingIn:
            true
        case .idle, .needsPermissions, .occupying:
            false
        }
    }

    var canToggle: Bool {
        switch phase {
        case .idle, .occupying, .needsPermissions:
            true
        case .capturing, .flippingOut, .flippingIn:
            false
        }
    }

    mutating func notePermissionsMissing() {
        phase = .needsPermissions
        lastRejection = nil
    }

    mutating func beginCapture(target: FlipTarget, parkStrategy: FlipParkStrategy) {
        pairing = FlipPairing(
            target: target,
            originalFrame: target.frame,
            overlayFrame: target.frame,
            parkStrategy: parkStrategy
        )
        phase = .capturing
        lastRejection = nil
    }

    mutating func beginFlippingOut() {
        guard pairing != nil else { return }
        phase = .flippingOut
    }

    mutating func beginOccupancy() {
        guard pairing != nil else { return }
        phase = .occupying
    }

    mutating func updateOverlayFrame(_ frame: CGRect) {
        pairing?.overlayFrame = frame
    }

    mutating func updateParkStrategy(_ strategy: FlipParkStrategy) {
        pairing?.parkStrategy = strategy
    }

    mutating func beginFlippingIn() {
        guard pairing != nil else { return }
        phase = .flippingIn
    }

    mutating func completeRestore() {
        pairing = nil
        phase = .idle
        lastRejection = nil
    }

    mutating func reject(_ rejection: FlipOccupancyRejection) {
        lastRejection = rejection
        if rejection == .animationInFlight || rejection == .alreadyOccupied {
            return
        }
        pairing = nil
        phase = .idle
    }

    mutating func abortToIdle() {
        pairing = nil
        phase = .idle
    }
}

enum FlipToggleDecision: Equatable, Sendable {
    case showPermissions
    case occupy(FlipTarget)
    case restore(FlipPairing)
    case reject(FlipOccupancyRejection)
    case ignore
}

enum FlipTogglePolicy: Sendable {
    static func decision(
        session: FlipSession,
        permissions: FlipPermissionStatus,
        frontmost: FlipTarget?,
        currentProcessIdentifier: pid_t
    ) -> FlipToggleDecision {
        guard session.canToggle else { return .ignore }
        if session.phase == .occupying, let pairing = session.pairing {
            return .restore(pairing)
        }
        if !permissions.isReady {
            return .showPermissions
        }
        switch FlipOccupancyPolicy.evaluate(
            target: frontmost,
            session: session,
            currentProcessIdentifier: currentProcessIdentifier
        ) {
        case let .success(target):
            return .occupy(target)
        case let .failure(rejection):
            return .reject(rejection)
        }
    }
}
