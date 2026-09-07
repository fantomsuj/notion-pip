import Foundation

enum FlipOccupancyRejection: Equatable, Sendable {
    case missingWindow
    case ownProcess
    case excludedBundle
    case missingWindowIdentity
    case fullScreen
    case stageManagerLocked
    case minimized
    case offscreen
    case tooSmall
    case nonStandardLayer
    case alreadyOccupied
    case animationInFlight
}

enum FlipOccupancyPolicy: Sendable {
    static func evaluate(
        target: FlipTarget?,
        session: FlipSession,
        currentProcessIdentifier: pid_t
    ) -> Result<FlipTarget, FlipOccupancyRejection> {
        if session.isAnimating {
            return .failure(.animationInFlight)
        }
        if session.phase == .occupying {
            return .failure(.alreadyOccupied)
        }
        guard let target else {
            return .failure(.missingWindow)
        }
        if target.processIdentifier == currentProcessIdentifier {
            return .failure(.ownProcess)
        }
        if let bundleIdentifier = target.bundleIdentifier,
           FlipIdentity.excludedBundleIdentifiers.contains(bundleIdentifier)
        {
            return .failure(.excludedBundle)
        }
        guard target.hasWindowIdentity else {
            return .failure(.missingWindowIdentity)
        }
        if target.isFullScreen {
            return .failure(.fullScreen)
        }
        if target.isStageManagerLocked {
            return .failure(.stageManagerLocked)
        }
        if target.isMinimized {
            return .failure(.minimized)
        }
        if !target.isOnScreen {
            return .failure(.offscreen)
        }
        if target.layer != 0 {
            return .failure(.nonStandardLayer)
        }
        if !FlipGeometry.isLargeEnoughToOccupy(target.frame) {
            return .failure(.tooSmall)
        }
        return .success(target)
    }
}
