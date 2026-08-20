import SwiftUI

struct StorageRecoveryView: View {
    @ObservedObject var controller: StorageRecoveryController

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.section) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(DesignTokens.Colors.error)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
                    Text(StorageRecoveryPresentation.title)
                        .font(.title2.weight(.semibold))
                    Text(StorageRecoveryPresentation.explanation)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupBox("What you can do") {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
                    Label(
                        "Keep working in Notion for this session without local Perch history.",
                        systemImage: "checkmark.circle"
                    )
                    Label(
                        "Reveal the preserved store artifacts for inspection or support.",
                        systemImage: "folder"
                    )
                    Label(
                        "Archive only the Perch store artifacts, quit, and reopen with fresh local storage.",
                        systemImage: "archivebox"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.callout)
                .padding(.vertical, DesignTokens.Spacing.compact)
            }

            if case let .failed(message) = controller.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Colors.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Archive failed. \(message)")
            } else if controller.isBusy {
                ProgressView("Archiving local store…")
                    .controlSize(.small)
                    .accessibilityLabel("Archiving local store")
            }

            Spacer(minLength: 0)

            HStack {
                actionButton(.revealStore) {
                    controller.revealStore()
                }

                Spacer()

                actionButton(.continueWithoutSaving) {
                    controller.continueWithoutSaving()
                }
                .keyboardShortcut(.defaultAction)

                actionButton(.archiveStoreAndQuit, role: .destructive) {
                    controller.requestArchiveConfirmation()
                }
            }
            .disabled(controller.isBusy)
        }
        .padding(DesignTokens.Spacing.container)
        .frame(width: 560, height: 430)
        .alert(
            StorageRecoveryPresentation.archiveConfirmationTitle,
            isPresented: archiveConfirmationBinding
        ) {
            Button("Cancel", role: .cancel) {
                controller.cancelArchiveConfirmation()
            }
            Button("Archive Store and Quit", role: .destructive) {
                controller.archiveStoreAndQuit()
            }
        } message: {
            Text(StorageRecoveryPresentation.archiveConfirmationMessage)
        }
    }

    private var archiveConfirmationBinding: Binding<Bool> {
        Binding(
            get: { controller.phase == .confirmingArchive },
            set: { isPresented in
                if !isPresented {
                    controller.cancelArchiveConfirmation()
                }
            }
        )
    }

    private func actionButton(
        _ action: StorageRecoveryAction,
        role: ButtonRole? = nil,
        perform: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: perform) {
            Text(action.label)
        }
        .accessibilityLabel(action.label)
        .help(action.accessibilityHelp)
    }
}
