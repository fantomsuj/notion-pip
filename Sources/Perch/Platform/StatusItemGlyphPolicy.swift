import AppKit

enum StatusItemGlyph: Equatable, Sendable {
    case visible
    case stashed
    case loading
    case needsSignIn

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
        separation: CGFloat = 0,
        verticalOffset: CGFloat = 0
    ) -> NSImage {
        let canvasSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: canvasSize, flipped: false) { _ in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()

            switch glyph {
            case .visible:
                drawLayers(
                    separation: separation,
                    dashed: false,
                    compressed: false,
                    verticalOffset: verticalOffset
                )
            case .stashed:
                drawLayers(
                    separation: 0,
                    dashed: false,
                    compressed: true,
                    verticalOffset: verticalOffset
                )
            case .loading:
                drawLayers(
                    separation: separation,
                    dashed: true,
                    compressed: false,
                    verticalOffset: verticalOffset
                )
            case .needsSignIn:
                drawLayers(
                    separation: separation,
                    dashed: false,
                    compressed: false,
                    verticalOffset: verticalOffset
                )
                drawPersonBadge(verticalOffset: verticalOffset)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawLayers(
        separation: CGFloat,
        dashed: Bool,
        compressed: Bool,
        verticalOffset: CGFloat
    ) {
        let layerSize = NSSize(width: 10, height: compressed ? 3.5 : 6)
        let centerX = CGFloat(9)
        let centerY = CGFloat(9) - verticalOffset
        let centerSpacing = compressed ? CGFloat(2) : CGFloat(3.5)
        let layerCenters = [
            centerY - (centerSpacing + separation) / 2,
            centerY + (centerSpacing + separation) / 2,
        ]

        for layerCenterY in layerCenters {
            let rect = NSRect(
                x: centerX - layerSize.width / 2,
                y: layerCenterY - layerSize.height / 2,
                width: layerSize.width,
                height: layerSize.height
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
            path.lineWidth = 1.25
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            if dashed {
                path.setLineDash([2, 1.5], count: 2, phase: 0)
            }
            path.stroke()
        }
    }

    private static func drawPersonBadge(verticalOffset: CGFloat) {
        let badgeCenter = NSPoint(x: 13.25, y: 5.25 - verticalOffset)
        NSBezierPath(
            ovalIn: NSRect(
                x: badgeCenter.x - 1,
                y: badgeCenter.y + 0.5,
                width: 2,
                height: 2
            )
        ).fill()

        let shoulders = NSBezierPath()
        shoulders.move(to: NSPoint(x: badgeCenter.x - 2, y: badgeCenter.y - 1.25))
        shoulders.curve(
            to: NSPoint(x: badgeCenter.x + 2, y: badgeCenter.y - 1.25),
            controlPoint1: NSPoint(x: badgeCenter.x - 1.5, y: badgeCenter.y + 0.25),
            controlPoint2: NSPoint(x: badgeCenter.x + 1.5, y: badgeCenter.y + 0.25)
        )
        shoulders.lineWidth = 1.25
        shoulders.lineCapStyle = .round
        shoulders.lineJoinStyle = .round
        shoulders.stroke()
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
