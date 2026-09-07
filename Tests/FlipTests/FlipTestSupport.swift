import CoreGraphics
import Foundation
@testable import Flip

enum FlipTestSupport {
    static func target(
        processIdentifier: pid_t = 42,
        windowID: CGWindowID = 7,
        bundleIdentifier: String? = "com.apple.TextEdit",
        localizedName: String? = "TextEdit",
        title: String? = "Untitled",
        frame: CGRect = CGRect(x: 100, y: 80, width: 800, height: 600),
        layer: Int = 0,
        isOnScreen: Bool = true,
        isMinimized: Bool = false,
        isFullScreen: Bool = false,
        isStageManagerLocked: Bool = false
    ) -> FlipTarget {
        FlipTarget(
            processIdentifier: processIdentifier,
            windowID: windowID,
            bundleIdentifier: bundleIdentifier,
            localizedName: localizedName,
            title: title,
            frame: frame,
            layer: layer,
            isOnScreen: isOnScreen,
            isMinimized: isMinimized,
            isFullScreen: isFullScreen,
            isStageManagerLocked: isStageManagerLocked
        )
    }
}
