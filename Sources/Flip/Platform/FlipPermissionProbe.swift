import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
protocol FlipPermissionChecking: AnyObject {
    var status: FlipPermissionStatus { get }
    func promptAccessibility()
    func requestScreenRecording()
}

@MainActor
final class FlipPermissionProbe: FlipPermissionChecking {
    private let accessibilityTrusted: () -> Bool
    private let screenRecordingAllowed: () -> Bool
    private let promptAccessibilityAccess: () -> Void
    private let requestScreenCaptureAccess: () -> Void

    init(
        accessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        screenRecordingAllowed: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        promptAccessibilityAccess: @escaping () -> Void = {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        requestScreenCaptureAccess: @escaping () -> Void = {
            _ = CGRequestScreenCaptureAccess()
        }
    ) {
        self.accessibilityTrusted = accessibilityTrusted
        self.screenRecordingAllowed = screenRecordingAllowed
        self.promptAccessibilityAccess = promptAccessibilityAccess
        self.requestScreenCaptureAccess = requestScreenCaptureAccess
    }

    var status: FlipPermissionStatus {
        FlipPermissionStatus(
            accessibilityTrusted: accessibilityTrusted(),
            screenRecordingAllowed: screenRecordingAllowed()
        )
    }

    func promptAccessibility() {
        promptAccessibilityAccess()
    }

    func requestScreenRecording() {
        requestScreenCaptureAccess()
    }
}
