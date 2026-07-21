import SwiftUI

enum PagePickerDisplay {
    static let maximumTitleLength = 30

    static func title(for page: NotionPageReference) -> String {
        let title = page.displayTitle ?? "Untitled Notion page"
        guard title.count > maximumTitleLength else {
            return title
        }

        return String(title.prefix(maximumTitleLength - 1)) + "…"
    }
}

struct PagePickerView: View {
    let pages: [NotionPageReference]
    let onPin: (NotionPageReference) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("Pinned page")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)

            ForEach(pages, id: \.pageID) { page in
                Button {
                    onPin(page)
                } label: {
                    Label(PagePickerDisplay.title(for: page), systemImage: "pin")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows this page in the floating panel")
            }
        }
    }
}
