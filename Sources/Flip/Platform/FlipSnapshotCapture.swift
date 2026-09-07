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
    private let scaleFactor: @MainActor () -> CGFloat

    init(
        scaleFactor: @escaping @MainActor () -> CGFloat = {
            NSScreen.main?.backingScaleFactor ?? 2
        }
    ) {
        self.scaleFactor = scaleFactor
    }

    func capture(windowID: CGWindowID) async throws -> NSImage {
        let bitmap = try await Self.captureBitmap(windowID: windowID, scale: scaleFactor())
        return NSImage(cgImage: bitmap.image, size: bitmap.size)
    }

    private struct CapturedBitmap: Sendable {
        let image: CGImage
        let size: CGSize
    }

    nonisolated private static func captureBitmap(
        windowID: CGWindowID,
        scale: CGFloat
    ) async throws -> CapturedBitmap {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw FlipSnapshotError.captureFailed
        }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw FlipSnapshotError.windowUnavailable
        }
        let configuration = SCStreamConfiguration()
        let width = window.frame.width
        let height = window.frame.height
        configuration.width = max(1, Int((width * scale).rounded()))
        configuration.height = max(1, Int((height * scale).rounded()))
        configuration.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw FlipSnapshotError.captureFailed
        }
        return CapturedBitmap(image: image, size: CGSize(width: width, height: height))
    }
}
