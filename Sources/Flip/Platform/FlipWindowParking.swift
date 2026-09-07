import AppKit
@preconcurrency import ApplicationServices
import Foundation

@MainActor
protocol FlipWindowParking: AnyObject {
    func park(_ target: FlipTarget, strategy: FlipParkStrategy) -> FlipParkStrategy?
    func restore(_ pairing: FlipPairing, primaryScreenHeight: CGFloat) -> Bool
}

@MainActor
final class AccessibilityFlipWindowParking: FlipWindowParking {
    private let setHidden: (AXUIElement, Bool) -> Bool
    private let setMinimized: (AXUIElement, Bool) -> Bool
    private let setQuartzFrame: (AXUIElement, CGRect) -> Bool
    private let focusedWindow: (pid_t) -> AXUIElement?

    init(
        setHidden: @escaping (AXUIElement, Bool) -> Bool = { element, hidden in
            FlipAXAttributeWriter.setBool(element, kAXHiddenAttribute as CFString, hidden)
        },
        setMinimized: @escaping (AXUIElement, Bool) -> Bool = { element, minimized in
            FlipAXAttributeWriter.setBool(element, kAXMinimizedAttribute as CFString, minimized)
        },
        setQuartzFrame: @escaping (AXUIElement, CGRect) -> Bool = { element, frame in
            FlipAXAttributeWriter.setFrame(element, frame)
        },
        focusedWindow: @escaping (pid_t) -> AXUIElement? = { pid in
            let application = AXUIElementCreateApplication(pid)
            return FlipAXWindowProbe.copyElement(application, kAXFocusedWindowAttribute as CFString)
                ?? application
        }
    ) {
        self.setHidden = setHidden
        self.setMinimized = setMinimized
        self.setQuartzFrame = setQuartzFrame
        self.focusedWindow = focusedWindow
    }

    func park(_ target: FlipTarget, strategy: FlipParkStrategy) -> FlipParkStrategy? {
        guard let window = focusedWindow(target.processIdentifier) else { return nil }
        switch strategy {
        case .hide:
            if setHidden(window, true) { return .hide }
            return park(target, strategy: .minimize)
        case .minimize:
            if setMinimized(window, true) { return .minimize }
            return park(target, strategy: .moveOffscreen)
        case .moveOffscreen:
            let offscreen = CGRect(
                origin: FlipGeometry.offscreenOrigin,
                size: target.frame.size
            )
            return setQuartzFrame(window, offscreen) ? .moveOffscreen : nil
        }
    }

    func restore(_ pairing: FlipPairing, primaryScreenHeight: CGFloat) -> Bool {
        guard let window = focusedWindow(pairing.target.processIdentifier) else {
            return false
        }
        let quartz = FlipGeometry.quartzBounds(
            fromCocoaFrame: pairing.restoreFrame,
            primaryScreenHeight: primaryScreenHeight
        )
        switch pairing.parkStrategy {
        case .hide:
            _ = setHidden(window, false)
        case .minimize:
            _ = setMinimized(window, false)
        case .moveOffscreen:
            break
        }
        return setQuartzFrame(window, quartz)
    }
}

enum FlipAXAttributeWriter {
    static func setBool(_ element: AXUIElement, _ attribute: CFString, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, attribute, value as CFBoolean) == .success
    }

    static func setFrame(_ element: AXUIElement, _ frame: CGRect) -> Bool {
        var origin = frame.origin
        var size = frame.size
        guard let originValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else {
            return false
        }
        let positionStatus = AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            originValue
        )
        let sizeStatus = AXUIElementSetAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        return positionStatus == .success && sizeStatus == .success
    }
}
