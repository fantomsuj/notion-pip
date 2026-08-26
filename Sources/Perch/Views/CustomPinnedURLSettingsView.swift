import SwiftUI

struct CustomPinnedURLSettingsView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        Section("Custom Pins (Beta)") {
            Toggle(
                "Allow custom pinned URLs",
                isOn: Binding(
                    get: { runtime.customPinnedURLsEnabled },
                    set: { runtime.setCustomPinnedURLsEnabled($0) }
                )
            )

            Text(
                "Experimental. Pin HTTPS sites such as Canvas in Perch. Your last Notion page stays saved so you can switch back anytime."
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)

            if runtime.customPinnedURLsEnabled {
                if runtime.isShowingCustomURL {
                    Button("Show Notion page") {
                        runtime.returnToNotionPage()
                    }
                    .accessibilityHint("Leaves the custom site and reopens your last Notion page")
                }

                PageURLInputView(
                    state: runtime.customPinnedURLInputState,
                    onSubmit: { _ = runtime.addCustomPinnedURL() },
                    title: "Custom URL",
                    subtitle: "Paste any HTTPS link. Notion page URLs still open as Notion.",
                    placeholder: "https://canvas.example.edu",
                    accessibilityLabel: "Custom pinned URL",
                    submitTitle: "Pin URL"
                )

                if runtime.customPinnedURLs.isEmpty {
                    Text("No custom URLs yet. Add an HTTPS link to keep it beside Notion.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                } else {
                    ForEach(runtime.customPinnedURLs) { pin in
                        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.control) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pin.displayTitle)
                                    .lineLimit(1)
                                Text(pin.canonicalURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                                    .lineLimit(1)
                                    .help(pin.canonicalURL.absoluteString)
                            }
                            Spacer(minLength: DesignTokens.Spacing.compact)
                            if runtime.activeCustomURL?.id == pin.id {
                                Text("Open")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                            } else {
                                Button("Open") {
                                    runtime.activateCustomPinnedURL(pin)
                                }
                            }
                            Button("Remove", role: .destructive) {
                                runtime.removeCustomPinnedURL(pin)
                            }
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }
        }
    }
}
