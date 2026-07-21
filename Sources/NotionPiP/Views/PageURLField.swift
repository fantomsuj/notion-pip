import SwiftUI

struct PageURLField: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("Notion page URL")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)

            HStack(spacing: DesignTokens.Spacing.control) {
                TextField("https://www.notion.so/…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onSubmit)
                    .accessibilityLabel("Notion page URL")

                Button("Check", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.Colors.action)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint("Validates the URL before pinning")
            }
        }
    }
}
