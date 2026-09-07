import Foundation

enum FlipPermissionKind: String, Equatable, Sendable, CaseIterable {
    case accessibility
    case screenRecording
}

struct FlipPermissionStatus: Equatable, Sendable {
    var accessibilityTrusted: Bool
    var screenRecordingAllowed: Bool

    var isReady: Bool {
        accessibilityTrusted && screenRecordingAllowed
    }

    var missing: [FlipPermissionKind] {
        var kinds: [FlipPermissionKind] = []
        if !accessibilityTrusted {
            kinds.append(.accessibility)
        }
        if !screenRecordingAllowed {
            kinds.append(.screenRecording)
        }
        return kinds
    }
}

enum FlipPermissionCopy: Sendable {
    static let windowTitle = "Flip Needs Permissions"
    static let heading = "Flip occupies another window with an overlay you own."
    static let detail = """
    macOS will not rotate ChatGPT or any other app's real window. Flip snapshots \
    the frontmost window, animates a card-flip in a window it owns, and parks \
    the original until you flip back.

    That needs Accessibility (to find, hide, and restore the window) and Screen \
    Recording (for a one-frame snapshot used only during the animation). Flip \
    does not request Input Monitoring and does not click other apps' title bars.
    """

    static func title(for kind: FlipPermissionKind) -> String {
        switch kind {
        case .accessibility:
            "Accessibility"
        case .screenRecording:
            "Screen Recording"
        }
    }

    static func explanation(for kind: FlipPermissionKind) -> String {
        switch kind {
        case .accessibility:
            "Identify the frontmost window, hide it while Notion occupies its rectangle, and restore it on the second flip."
        case .screenRecording:
            "Capture one frame of that window so the front face of the flip can match what you were looking at. The bitmap stays in memory and is not saved."
        }
    }

    static let grantAccessibility = "Open Accessibility Settings"
    static let grantScreenRecording = "Open Screen Recording Settings"
    static let continueTitle = "Continue"
    static let quitTitle = "Quit Flip"
}
