import AppKit
import Carbon.HIToolbox
import SwiftUI

struct GlobalShortcutRecorderView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var isRecording = false
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
            HStack {
                Text(runtime.globalShortcut.displayString)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control))

                Button(isRecording ? "Press a shortcut…" : "Record Shortcut") {
                    isRecording.toggle()
                    feedback = nil
                }

                Button("Reset") {
                    runtime.resetGlobalShortcut()
                    isRecording = false
                    feedback = nil
                }
            }

            if isRecording {
                ShortcutKeyCaptureView { result in
                    switch result {
                    case let .success(shortcut):
                        if runtime.applyGlobalShortcut(shortcut) {
                            feedback = "Shortcut updated to \(shortcut.displayString)."
                            isRecording = false
                        } else {
                            feedback = "macOS could not register that shortcut. Your previous shortcut is still active."
                        }
                    case let .failure(message):
                        feedback = message
                    }
                }
                .frame(width: 1, height: 1)
            }

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(feedback.hasPrefix("Shortcut updated") ? DesignTokens.Colors.secondaryText : DesignTokens.Colors.error)
            }
        }
    }
}

struct QuickCaptureShortcutRecorderView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        ShortcutRecorder(
            shortcut: runtime.quickCaptureShortcut,
            apply: runtime.applyQuickCaptureShortcut,
            reset: runtime.resetQuickCaptureShortcut
        )
    }
}

private struct ShortcutRecorder: View {
    let shortcut: GlobalShortcut
    let apply: (GlobalShortcut) -> Bool
    let reset: () -> Void
    @State private var isRecording = false
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
            HStack {
                Text(shortcut.displayString).font(.system(.body, design: .monospaced))
                Button(isRecording ? "Press a shortcut…" : "Record Shortcut") {
                    isRecording.toggle(); feedback = nil
                }
                Button("Reset") { reset(); isRecording = false; feedback = nil }
            }
            if isRecording {
                ShortcutKeyCaptureView { result in
                    switch result {
                    case let .success(value):
                        if apply(value) { feedback = "Shortcut updated to \(value.displayString)."; isRecording = false }
                        else { feedback = "Choose a shortcut distinct from Show/Hide that macOS can register." }
                    case let .failure(message): feedback = message
                    }
                }.frame(width: 1, height: 1)
            }
            if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private enum ShortcutCaptureResult {
    case success(GlobalShortcut)
    case failure(String)
}

private struct ShortcutKeyCaptureView: NSViewRepresentable {
    let onResult: (ShortcutCaptureResult) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onResult = onResult
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
        view.onResult = onResult
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }
}

private final class ShortcutCaptureNSView: NSView {
    var onResult: ((ShortcutCaptureResult) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard !Self.modifierKeyCodes.contains(event.keyCode) else {
            onResult?(.failure("Press a key together with at least one modifier."))
            return
        }

        let shortcut = GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: Self.carbonModifiers(from: event.modifierFlags)
        )
        guard shortcut.isValid else {
            onResult?(.failure("Use Command, Option, Control, or Shift with a supported key."))
            return
        }
        onResult?(.success(shortcut))
    }

    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command), UInt16(kVK_Shift), UInt16(kVK_Option), UInt16(kVK_Control),
        UInt16(kVK_RightCommand), UInt16(kVK_RightShift), UInt16(kVK_RightOption), UInt16(kVK_RightControl),
    ]

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
