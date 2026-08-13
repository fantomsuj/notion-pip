import AppKit

enum StatusItemGlyph: Equatable, Sendable {
    case visible
    case stashed
    case loading
    case needsSignIn

    var systemSymbolName: String {
        switch self {
        case .visible:
            "rectangle.on.rectangle"
        case .stashed:
            "rectangle.bottomhalf.inset.filled"
        case .loading:
            "rectangle.dashed"
        case .needsSignIn:
            "rectangle.badge.person.crop"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .visible:
            "Perch is open"
        case .stashed:
            "Perch"
        case .loading:
            "Perch is loading"
        case .needsSignIn:
            "Perch needs sign-in"
        }
    }

    var accessibilityDescription: String {
        accessibilityLabel
    }
}

@MainActor
enum StatusItemGlyphPolicy {
    static func glyph(
        presentation: PiPPresentationState,
        sessionState: NotionWebSessionState,
        loginState: NotionBrowserLoginState
    ) -> StatusItemGlyph {
        if needsSignIn(loginState) {
            return .needsSignIn
        }
        if isLoading(sessionState, loginState) {
            return .loading
        }
        switch presentation {
        case .visible:
            return .visible
        case .stashed, .unavailable:
            return .stashed
        }
    }

    static func makeImage(
        for glyph: StatusItemGlyph,
        verticalOffset: CGFloat = 0
    ) -> NSImage {
        let symbol = NSImage(
            systemSymbolName: glyph.systemSymbolName,
            accessibilityDescription: glyph.accessibilityDescription
        ) ?? NSImage(
            systemSymbolName: StatusItemGlyph.visible.systemSymbolName,
            accessibilityDescription: glyph.accessibilityDescription
        )
        let image = symbol ?? NSImage()
        image.isTemplate = true
        guard verticalOffset != 0 else { return image }

        let size = image.size
        let offsetImage = NSImage(size: size)
        offsetImage.lockFocus()
        image.draw(
            at: NSPoint(x: 0, y: -verticalOffset),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        offsetImage.unlockFocus()
        offsetImage.isTemplate = true
        return offsetImage
    }

    private static func needsSignIn(_ loginState: NotionBrowserLoginState) -> Bool {
        switch loginState {
        case .loginRequired, .failed, .restorationFailed:
            true
        case .idle, .openingBrowser, .redeeming:
            false
        }
    }

    private static func isLoading(
        _ sessionState: NotionWebSessionState,
        _ loginState: NotionBrowserLoginState
    ) -> Bool {
        if sessionState == .loading {
            return true
        }
        switch loginState {
        case .openingBrowser, .redeeming:
            return true
        case .idle, .loginRequired, .failed, .restorationFailed:
            return false
        }
    }
}
