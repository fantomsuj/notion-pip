import CoreGraphics
import Foundation

/// A foreign window Flip may occupy. Values are snapshots; they are not live
/// AX or CoreGraphics objects.
struct FlipTarget: Equatable, Sendable {
    let processIdentifier: pid_t
    let windowID: CGWindowID
    let bundleIdentifier: String?
    let localizedName: String?
    let title: String?
    let frame: CGRect
    let layer: Int
    let isOnScreen: Bool
    let isMinimized: Bool
    let isFullScreen: Bool
    let isStageManagerLocked: Bool

    var hasWindowIdentity: Bool {
        windowID != kCGNullWindowID
    }
}

enum FlipParkStrategy: Equatable, Sendable {
    case hide
    case minimize
    case moveOffscreen
}

struct FlipPairing: Equatable, Sendable {
    let target: FlipTarget
    let originalFrame: CGRect
    var overlayFrame: CGRect
    var parkStrategy: FlipParkStrategy

    var restoreFrame: CGRect { overlayFrame }
}
