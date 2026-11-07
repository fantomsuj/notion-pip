import AppKit
import SwiftUI

struct CursorToolsSettingsView: View {
    @ObservedObject var controller: CursorToolsController

    var body: some View {
        Section("Cursor Tools") {
            Toggle(
                "Turn on cursor tools",
                isOn: Binding(
                    get: { controller.isEnabled },
                    set: { controller.setEnabled($0) }
                )
            )

            Text(
                "The pointer is in every app, so Perch can use it to carry things across them."
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)

            if controller.isEnabled {
                LabeledContent(
                    "Carry a screenshot",
                    value: CursorToolsController.carryShortcut.displayString
                )
                Text("Select an area and it rides your pointer. Double-click where it should go to drop it, or shake the pointer to toss it.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)

                LabeledContent(
                    "Jot a margin note",
                    value: CursorToolsController.noteShortcut.displayString
                )
                Text("Type a note at the pointer in any app. It lands where your cursor is in the Perch page, with the time and the app and window it came from.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)

                if let problem = controller.shortcutProblem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }

                LabeledContent(
                    "Accessibility",
                    value: controller.isAccessibilityTrusted ? "Allowed" : "Not allowed"
                )
                if !controller.isAccessibilityTrusted {
                    Text("Allow Accessibility so screenshots drop into other apps in one double-click and notes keep the window title. Without it, drops outside Perch are copied for you to paste, and notes keep only the app name.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                    Button("Allow Accessibility…") {
                        controller.requestAccessibility()
                    }
                }
                Text("Carrying screenshots also asks for Screen Recording the first time.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)

                let waiting = controller.notes.waitingNotes.count
                if waiting > 0 {
                    LabeledContent(
                        "Waiting notes",
                        value: "\(waiting)"
                    )
                    Text("These couldn’t find a cursor in the Perch page. Click where they should go in Perch, then drop them in.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                    HStack {
                        Button("Drop into Notion") {
                            controller.notes.dropWaitingNotes()
                        }
                        Button("Copy") {
                            controller.notes.copyWaitingNotes()
                        }
                        Button("Clear", role: .destructive) {
                            controller.notes.clearWaitingNotes()
                        }
                    }
                }
            }
        }
        .onAppear {
            controller.refreshPermissions()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            controller.refreshPermissions()
        }
    }
}
