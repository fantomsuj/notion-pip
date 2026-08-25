import SwiftUI

struct PageURLField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let focusRequest: Int
    var title: String
    var subtitle: String
    var placeholder: String
    var accessibilityLabel: String
    var submitTitle: String
    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>,
        focusRequest: Int = 0,
        title: String = "Notion page URL",
        subtitle: String = "In Notion, choose ••• → Copy link.",
        placeholder: String = "https://www.notion.com/…",
        accessibilityLabel: String = "Notion page URL",
        submitTitle: String = "Open in Perch",
        onSubmit: @escaping () -> Void
    ) {
        _text = text
        self.focusRequest = focusRequest
        self.title = title
        self.subtitle = subtitle
        self.placeholder = placeholder
        self.accessibilityLabel = accessibilityLabel
        self.submitTitle = submitTitle
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            HStack(spacing: DesignTokens.Spacing.control) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(onSubmit)
                    .accessibilityLabel(accessibilityLabel)

                Button(submitTitle, action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.Colors.action)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint("Opens the page in the floating panel")
            }
        }
        .onAppear {
            if focusRequest > 0 {
                isFocused = true
            }
        }
        .onChange(of: focusRequest) {
            isFocused = true
        }
    }
}
