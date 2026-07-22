import SwiftUI

struct NotionWorkspaceSearchView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("From your Notion workspace")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)

            HStack(spacing: DesignTokens.Spacing.control) {
                TextField("Search pages", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button(action: search) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search Notion pages")
            }

            if let searchError = runtime.searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
            }

            ForEach(runtime.searchResults, id: \.page.pageID) { result in
                Button {
                    runtime.activate(page: result.page, source: .notionSearch)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .lineLimit(1)
                        Text(result.lastEditedTime.isEmpty ? "Notion page" : "Edited \(result.lastEditedTime)")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func search() {
        Task { await runtime.searchNotionPages(query: query) }
    }
}
