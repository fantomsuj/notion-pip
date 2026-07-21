import SwiftUI

struct ConflictRecoveryView: View {
    let conflict: CaptureConflict
    let resolve: (CaptureConflictAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
            Label("A newer draft was saved elsewhere", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.error)

            Text("Your current editor content is still here. Choose how to recover it.")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)

            HStack(spacing: DesignTokens.Spacing.control) {
                recoveryButton("Reload latest", action: .reloadLatest)
                recoveryButton("Save as new", action: .saveAsNew)
                recoveryButton("Open in Notion", action: .openInNotion)
            }
            .controlSize(.small)
        }
        .padding(DesignTokens.Spacing.control)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Draft conflict recovery")
    }

    private func recoveryButton(_ title: String, action: CaptureConflictAction) -> some View {
        Button(title) { resolve(action) }
            .disabled(!conflict.availableActions.contains(action))
    }
}
