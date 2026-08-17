import SwiftUI

enum PagePickerDisplay {
    static let maximumTitleLength = 30

    static func title(for page: NotionPageReference) -> String {
        let title = fullTitle(for: page)
        guard title.count > maximumTitleLength else {
            return title
        }

        return String(title.prefix(maximumTitleLength - 1)) + "…"
    }

    static func fullTitle(for page: NotionPageReference) -> String {
        page.displayTitle ?? "Untitled Notion page"
    }

    static func helpText(for page: NotionPageReference) -> String {
        fullTitle(for: page)
    }
}

struct PagePickerView: View {
    let pages: [NotionPageReference]
    let onPin: (NotionPageReference) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("Current page")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)

            ForEach(pages, id: \.pageID) { page in
                Button {
                    onPin(page)
                } label: {
                    Label(PagePickerDisplay.title(for: page), systemImage: "doc.text")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .chromePressStyle()
                .help(PagePickerDisplay.helpText(for: page))
                .accessibilityHint("Shows this page in the floating panel")
            }
        }
    }
}
