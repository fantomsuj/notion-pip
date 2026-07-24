import SwiftUI

struct QuickCaptureDestinationSettingsView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
            if let destination = runtime.quickCaptureDestination {
                LabeledContent("Current destination") {
                    Label(destination.title, systemImage: symbol(for: destination))
                }
                Button("Clear Destination", role: .destructive) {
                    Task { await runtime.clearQuickCaptureDestination() }
                }
            } else {
                Text("Choose where Quick Capture creates new Notion pages.")
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            if runtime.isNotionConnected {
                HStack(spacing: DesignTokens.Spacing.control) {
                    TextField("Search pages and data sources", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(search)
                    Button(action: search) {
                        if runtime.isSearchingDestinations {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    .disabled(runtime.isSearchingDestinations)
                    .accessibilityLabel("Search Quick Capture destinations")
                }

                ForEach(
                    runtime.destinationSearchResults,
                    id: \.destination.selectionID
                ) { result in
                    Button {
                        Task {
                            await runtime.selectQuickCaptureDestination(
                                result.destination
                            )
                        }
                    } label: {
                        HStack {
                            Image(systemName: symbol(for: result.destination))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.destination.title)
                                    .lineLimit(1)
                                Text(kindLabel(for: result.destination))
                                    .font(.caption2)
                                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Connect your personal Notion access token to search destinations.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            if let error = runtime.destinationSearchError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
            }
        }
    }

    private func search() {
        Task { await runtime.searchQuickCaptureDestinations(query: query) }
    }

    private func symbol(for destination: QuickCaptureDestination) -> String {
        switch destination {
        case .pageParent:
            "doc"
        case .dataSource:
            "tablecells"
        }
    }

    private func kindLabel(for destination: QuickCaptureDestination) -> String {
        switch destination {
        case .pageParent:
            "Create a child page"
        case .dataSource:
            "Create a data source entry"
        }
    }
}

private extension QuickCaptureDestination {
    var selectionID: String {
        "\(rawKind):\(identifier)"
    }
}
