import AppKit
import SwiftUI

struct FlipPermissionView: View {
    let status: FlipPermissionStatus
    let shortcut: FlipShortcut
    let onGrantAccessibility: () -> Void
    let onGrantScreenRecording: () -> Void
    let onContinue: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(FlipIdentity.displayName)
                .font(.headline)
            Text(FlipPermissionCopy.heading)
                .font(.system(size: 22, weight: .semibold))
            Text(FlipPermissionCopy.detail)
                .font(.body)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(
                kind: .accessibility,
                granted: status.accessibilityTrusted,
                action: onGrantAccessibility,
                title: FlipPermissionCopy.grantAccessibility
            )
            permissionRow(
                kind: .screenRecording,
                granted: status.screenRecordingAllowed,
                action: onGrantScreenRecording,
                title: FlipPermissionCopy.grantScreenRecording
            )

            Text("Then press \(shortcut.tutorialDisplayString) while another window is frontmost.")
                .font(.callout)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            HStack {
                Button(FlipPermissionCopy.quitTitle, action: onQuit)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(FlipPermissionCopy.continueTitle, action: onContinue)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!status.isReady)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
    }

    private func permissionRow(
        kind: FlipPermissionKind,
        granted: Bool,
        action: @escaping () -> Void,
        title: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                Text(FlipPermissionCopy.title(for: kind))
                    .font(.headline)
                Text(FlipPermissionCopy.explanation(for: kind))
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button(title, action: action)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
final class FlipPermissionWindowPresenter {
    private var window: NSWindow?
    private let status: () -> FlipPermissionStatus
    private let shortcut: () -> FlipShortcut
    private let onGrantAccessibility: () -> Void
    private let onGrantScreenRecording: () -> Void
    private let onContinue: () -> Void

    init(
        status: @escaping () -> FlipPermissionStatus,
        shortcut: @escaping () -> FlipShortcut,
        onGrantAccessibility: @escaping () -> Void,
        onGrantScreenRecording: @escaping () -> Void,
        onContinue: @escaping () -> Void
    ) {
        self.status = status
        self.shortcut = shortcut
        self.onGrantAccessibility = onGrantAccessibility
        self.onGrantScreenRecording = onGrantScreenRecording
        self.onContinue = onContinue
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: true
            )
            window.title = FlipPermissionCopy.windowTitle
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.level = .normal
            self.window = window
        }
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        guard let window else { return }
        window.contentView = NSHostingView(
            rootView: FlipPermissionView(
                status: status(),
                shortcut: shortcut(),
                onGrantAccessibility: onGrantAccessibility,
                onGrantScreenRecording: onGrantScreenRecording,
                onContinue: {
                    self.onContinue()
                    self.window?.orderOut(nil)
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )
    }

    func hide() {
        window?.orderOut(nil)
    }
}
