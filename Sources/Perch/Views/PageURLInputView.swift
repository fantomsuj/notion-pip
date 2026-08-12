import SwiftUI

struct PageURLInputView: View {
    @ObservedObject var state: PageURLInputState
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            PageURLField(
                text: $state.text,
                focusRequest: state.focusRequest,
                onSubmit: onSubmit
            )

            if let validationMessage = state.validationMessage {
                Label(
                    validationMessage,
                    systemImage: state.validationFailed
                        ? "exclamationmark.circle"
                        : "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(
                    state.validationFailed
                        ? DesignTokens.Colors.error
                        : DesignTokens.Colors.secondaryText
                )
                .accessibilityLabel(validationMessage)
            }
        }
    }
}
