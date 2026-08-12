import SwiftUI

struct PageURLField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let focusRequest: Int
    @FocusState private var isFocused: Bool

    init(text: Binding<String>, focusRequest: Int = 0, onSubmit: @escaping () -> Void) {
        _text = text
        self.focusRequest = focusRequest
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notion page URL")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                Text("In Notion, choose ••• → Copy link.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            HStack(spacing: DesignTokens.Spacing.control) {
                TextField("https://www.notion.com/…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(onSubmit)
                    .accessibilityLabel("Notion page URL")

                Button("Open in Perch", action: onSubmit)
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
