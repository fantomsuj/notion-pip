import AppKit
@preconcurrency import ApplicationServices
import Foundation

@MainActor
protocol FlipWindowResolving: AnyObject {
    func frontmostTarget() -> FlipTarget?
}

@MainActor
struct FlipWindowListEntry: Equatable, Sendable {
    let windowID: CGWindowID
    let processIdentifier: pid_t
    let title: String?
    let quartzBounds: CGRect
    let layer: Int
    let isOnScreen: Bool
}

enum FlipWindowListMatching {
    static func match(
        processIdentifier: pid_t,
        cocoaFrame: CGRect,
        primaryScreenHeight: CGFloat,
        entries: [FlipWindowListEntry]
    ) -> FlipWindowListEntry? {
        let quartz = FlipGeometry.quartzBounds(
            fromCocoaFrame: cocoaFrame,
            primaryScreenHeight: primaryScreenHeight
        )
        return entries.first { entry in
            entry.processIdentifier == processIdentifier
                && entry.layer == 0
                && entry.isOnScreen
                && FlipGeometry.framesMatch(entry.quartzBounds, quartz)
        }
    }
}

@MainActor
final class AccessibilityFlipWindowResolver: FlipWindowResolving {
    private let currentProcessIdentifier: pid_t
    private let primaryScreenHeight: () -> CGFloat
    private let screenFrames: () -> [CGRect]
    private let frontmostApplication: () -> RunningFlipApplication?
    private let windowList: () -> [FlipWindowListEntry]
    private let focusedWindowProbe: (pid_t) -> FlipAXWindowAttributes?

    init(
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        primaryScreenHeight: @escaping () -> CGFloat = {
            AccessibilityFlipWindowResolver.primaryDisplayHeight()
        },
        screenFrames: @escaping () -> [CGRect] = {
            NSScreen.screens.map(\.frame)
        },
        frontmostApplication: @escaping () -> RunningFlipApplication? = {
            AccessibilityFlipWindowResolver.liveFrontmostApplication()
        },
        windowList: @escaping () -> [FlipWindowListEntry] = {
            CGWindowListCatalog.entries()
        },
        focusedWindowProbe: @escaping (pid_t) -> FlipAXWindowAttributes? = { pid in
            FlipAXWindowProbe.focusedWindow(processIdentifier: pid)
        }
    ) {
        self.currentProcessIdentifier = currentProcessIdentifier
        self.primaryScreenHeight = primaryScreenHeight
        self.screenFrames = screenFrames
        self.frontmostApplication = frontmostApplication
        self.windowList = windowList
        self.focusedWindowProbe = focusedWindowProbe
    }

    func frontmostTarget() -> FlipTarget? {
        guard let application = frontmostApplication() else { return nil }
        guard application.processIdentifier != currentProcessIdentifier else { return nil }
        guard let attributes = focusedWindowProbe(application.processIdentifier) else {
            return nil
        }

        let height = primaryScreenHeight()
        let cocoaFrame = FlipGeometry.cocoaFrame(
            fromQuartzBounds: attributes.quartzFrame,
            primaryScreenHeight: height
        )
        let matched = FlipWindowListMatching.match(
            processIdentifier: application.processIdentifier,
            cocoaFrame: cocoaFrame,
            primaryScreenHeight: height,
            entries: windowList()
        )
        let isFullScreen = attributes.isFullScreen
            || screenFrames().contains {
                FlipGeometry.isEffectivelyFullScreen(cocoaFrame, screenFrame: $0)
            }

        return FlipTarget(
            processIdentifier: application.processIdentifier,
            windowID: matched?.windowID ?? kCGNullWindowID,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName,
            title: attributes.title ?? matched?.title,
            frame: cocoaFrame,
            layer: matched?.layer ?? 0,
            isOnScreen: matched?.isOnScreen ?? true,
            isMinimized: attributes.isMinimized,
            isFullScreen: isFullScreen,
            isStageManagerLocked: false
        )
    }

    static func primaryDisplayHeight() -> CGFloat {
        let screens = NSScreen.screens
        if let primary = screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.height
        }
        return screens.first?.frame.height ?? 0
    }

    static func liveFrontmostApplication() -> RunningFlipApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return RunningFlipApplication(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName
        )
    }
}

struct RunningFlipApplication: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
}

struct FlipAXWindowAttributes: Equatable, Sendable {
    let quartzFrame: CGRect
    let title: String?
    let isMinimized: Bool
    let isFullScreen: Bool
}

enum CGWindowListCatalog {
    static func entries() -> [FlipWindowListEntry] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }
        return info.compactMap { entry in
            guard let windowNumber = entry[kCGWindowNumber as String] as? NSNumber,
                  let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = cgFloat(bounds["X"]),
                  let y = cgFloat(bounds["Y"]),
                  let width = cgFloat(bounds["Width"]),
                  let height = cgFloat(bounds["Height"])
            else {
                return nil
            }
            let windowID = CGWindowID(windowNumber.uint32Value)
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let onScreen = (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
            return FlipWindowListEntry(
                windowID: windowID,
                processIdentifier: pid_t(pidNumber.int32Value),
                title: entry[kCGWindowName as String] as? String,
                quartzBounds: CGRect(x: x, y: y, width: width, height: height),
                layer: layer,
                isOnScreen: onScreen
            )
        }
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        (value as? NSNumber).map { CGFloat(truncating: $0) }
    }
}

enum FlipAXWindowProbe {
    static func focusedWindow(processIdentifier: pid_t) -> FlipAXWindowAttributes? {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let window = copyElement(application, kAXFocusedWindowAttribute as CFString)
        else {
            return nil
        }
        guard let origin = copyPoint(window, kAXPositionAttribute as CFString),
              let size = copySize(window, kAXSizeAttribute as CFString)
        else {
            return nil
        }
        let title = copyString(window, kAXTitleAttribute as CFString)
        let isMinimized = copyBool(window, kAXMinimizedAttribute as CFString) ?? false
        let isFullScreen = copyBool(window, "AXFullScreen" as CFString) ?? false
        return FlipAXWindowAttributes(
            quartzFrame: CGRect(origin: origin, size: size),
            title: title,
            isMinimized: isMinimized,
            isFullScreen: isFullScreen
        )
    }

    static func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        // AXUIElement is a CF type; the type-ID check above is the invariant.
        return (value as! AXUIElement)
    }

    static func copyString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        return value as? String
    }

    static func copyBool(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    static func copyPoint(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func copySize(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
