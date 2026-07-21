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

struct PageURLInputWindowContent: View {
    @ObservedObject var state: PageURLInputState
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                Text("Pin a Notion page")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.primaryText)

                Text("Paste a full Notion page URL.")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            PageURLInputView(state: state, onSubmit: onSubmit)
        }
        .padding(DesignTokens.Spacing.container)
        .frame(width: 440)
        .background(DesignTokens.Colors.background)
    }
}
