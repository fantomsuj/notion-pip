import SwiftUI

struct PageURLInputView: View {
    @ObservedObject var state: PageURLInputState
    let onSubmit: () -> Void
    var title: String = "Notion page URL"
    var subtitle: String = "In Notion, choose ••• → Copy link."
    var placeholder: String = "https://www.notion.com/…"
    var accessibilityLabel: String = "Notion page URL"
    var submitTitle: String = "Open in Perch"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakeToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            PageURLField(
                text: $state.text,
                focusRequest: state.focusRequest,
                title: title,
                subtitle: subtitle,
                placeholder: placeholder,
                accessibilityLabel: accessibilityLabel,
                submitTitle: submitTitle,
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
        .errorShake(trigger: shakeToken, reducesMotion: reduceMotion)
        .onChange(of: state.validationFailed) { _, failed in
            if failed {
                shakeToken += 1
            }
        }
    }
}
