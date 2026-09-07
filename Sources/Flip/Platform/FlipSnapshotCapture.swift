import AppKit
import Foundation
import ScreenCaptureKit

enum FlipSnapshotError: Error, Equatable, Sendable {
    case windowUnavailable
    case captureFailed
}

@MainActor
protocol FlipSnapshotCapturing: AnyObject {
    func capture(windowID: CGWindowID) async throws -> NSImage
}

@MainActor
final class ScreenCaptureKitSnapshotter: FlipSnapshotCapturing {
    private let scaleFactor: () -> CGFloat
    private let shareableWindows: () async throws -> [SCWindow]
    private let captureImage: (SCWindow, SCStreamConfiguration) async throws -> CGImage

    init(
        scaleFactor: @escaping () -> CGFloat = {
            NSScreen.main?.backingScaleFactor ?? 2
        },
        shareableWindows: @escaping () async throws -> [SCWindow] = {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            return content.windows
        },
        captureImage: @escaping (SCWindow, SCStreamConfiguration) async throws -> CGImage = {
            window,
            configuration in
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        }
    ) {
        self.scaleFactor = scaleFactor
        self.shareableWindows = shareableWindows
        self.captureImage = captureImage
    }

    func capture(windowID: CGWindowID) async throws -> NSImage {
        let windows = try await shareableWindows()
        guard let window = windows.first(where: { $0.windowID == windowID }) else {
            throw FlipSnapshotError.windowUnavailable
        }
        let configuration = SCStreamConfiguration()
        let scale = scaleFactor()
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))
        configuration.showsCursor = false
        let image: CGImage
        do {
            image = try await captureImage(window, configuration)
        } catch {
            throw FlipSnapshotError.captureFailed
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: window.frame.width, height: window.frame.height)
        )
    }
}
