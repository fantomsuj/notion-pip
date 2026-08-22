import AppKit
import QuartzCore

@MainActor
enum SpaceTransitionWindowAnimator {
    static func apply(
        _ frame: SpaceTransitionMotionPolicy.VisualFrame,
        to windows: [NSWindow]
    ) {
        for window in windows {
            window.alphaValue = frame.opacity
            applyTransform(frame, to: window)
        }
    }

    static func animate(
        _ windows: [NSWindow],
        to frame: SpaceTransitionMotionPolicy.VisualFrame,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) async {
        guard !windows.isEmpty else { return }
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction
            for window in windows {
                window.animator().alphaValue = frame.opacity
                guard !window.styleMask.contains(.titled),
                    let layer = chromeLayer(for: window)
                else {
                    continue
                }
                CATransaction.begin()
                CATransaction.setAnimationDuration(duration)
                CATransaction.setAnimationTimingFunction(timingFunction)
                layer.transform = transform(for: frame)
                CATransaction.commit()
            }
        }
    }

    static func restore(_ windows: [NSWindow]) {
        apply(SpaceTransitionMotionPolicy.restFrame, to: windows)
    }

    static func play(
        _ animation: SpaceTransitionAnimation,
        on windows: [NSWindow]
    ) async {
        let windows = windows.filter(\.isVisible)
        guard !windows.isEmpty else { return }

        switch animation {
        case let .hide(direction):
            await animate(
                windows,
                to: SpaceTransitionMotionPolicy.departureFrame(direction: direction),
                duration: SpaceTransitionMotionPolicy.departureDuration,
                timingFunction: CAMediaTimingFunction(name: .easeIn)
            )
        case let .show(direction):
            apply(
                SpaceTransitionMotionPolicy.arrivalStartFrame(direction: direction),
                to: windows
            )
            await animate(
                windows,
                to: SpaceTransitionMotionPolicy.restFrame,
                duration: SpaceTransitionMotionPolicy.arrivalDuration,
                timingFunction: arrivalTimingFunction
            )
            restore(windows)
        case let .hideThenShow(direction):
            await play(.hide(direction), on: windows)
            guard !Task.isCancelled else { return }
            await play(.show(direction), on: windows)
        }
    }

    private static var arrivalTimingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    }

    private static func applyTransform(
        _ frame: SpaceTransitionMotionPolicy.VisualFrame,
        to window: NSWindow
    ) {
        guard !window.styleMask.contains(.titled) else { return }
        chromeLayer(for: window)?.transform = transform(for: frame)
    }

    private static func chromeLayer(for window: NSWindow) -> CALayer? {
        guard let chrome = window.contentView?.superview else { return nil }
        chrome.wantsLayer = true
        return chrome.layer
    }

    private static func transform(
        for frame: SpaceTransitionMotionPolicy.VisualFrame
    ) -> CATransform3D {
        CATransform3DMakeTranslation(frame.translationX, 0, 0)
    }
}
