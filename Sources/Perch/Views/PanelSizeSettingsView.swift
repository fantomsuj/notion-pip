import SwiftUI

struct PanelSizeSettingsView: View {
    @ObservedObject var controller: PanelSizeController
    @State private var isPresentingSaveSheet = false
    @State private var capturedName = "My Size"
    @State private var capturedWidth = 520.0
    @State private var capturedHeight = 680.0

    var body: some View {
        Group {
            LabeledContent("Current panel size") {
                Text(currentSizeDescription)
                    .monospacedDigit()
            }

            HStack {
                Button("Save Current Size…") {
                    prepareCapture()
                }
                .disabled(!controller.canSaveCurrentSize)
            }

            if let validationMessage = controller.validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
                    .accessibilityLabel("Panel size error: \(validationMessage)")
            }

            HStack {
                Text("Custom Sizes")
                    .font(.headline)
                Spacer()
                Text(
                    "\(controller.preferences.customPresets.count)/\(PanelSizePreferences.maximumCustomPresetCount)"
                )
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .monospacedDigit()
            }
            .padding(.top, DesignTokens.Spacing.compact)

            if controller.preferences.customPresets.isEmpty {
                Text("Save the current panel size to create a custom preset.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                ForEach(controller.preferences.customPresets) { preset in
                    CustomPanelSizeRow(
                        preset: preset,
                        canApply: controller.canApply,
                        onSave: { name, width, height in
                            controller.updateCustomPreset(
                                id: preset.id,
                                name: name,
                                width: width,
                                height: height
                            )
                        },
                        onApply: {
                            controller.apply(.custom(preset.id))
                        },
                        onDelete: {
                            controller.deleteCustomPreset(id: preset.id)
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $isPresentingSaveSheet) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
                Text("Save Current Panel Size")
                    .font(.headline)

                TextField("Preset name", text: $capturedName)

                HStack {
                    TextField(
                        "Width",
                        value: $capturedWidth,
                        format: .number.precision(.fractionLength(0))
                    )
                    Text("×")
                        .accessibilityHidden(true)
                    TextField(
                        "Height",
                        value: $capturedHeight,
                        format: .number.precision(.fractionLength(0))
                    )
                    Text("pt")
                }

                if let validationMessage = controller.validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        isPresentingSaveSheet = false
                        controller.clearValidationMessage()
                    }
                    Button("Save") {
                        saveCapture()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(DesignTokens.Spacing.container)
            .frame(width: 360)
        }
    }

    private var currentSizeDescription: String {
        guard let currentContentSize = controller.currentContentSize else {
            return "Unavailable"
        }
        return "\(formatted(currentContentSize.width)) × \(formatted(currentContentSize.height)) pt"
    }

    private func prepareCapture() {
        guard let contentSize = controller.currentContentSize else { return }
        capturedName = "My Size"
        capturedWidth = contentSize.width.rounded()
        capturedHeight = contentSize.height.rounded()
        controller.clearValidationMessage()
        isPresentingSaveSheet = true
    }

    private func formatted(_ value: CGFloat) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return Double(value).formatted(
            .number.precision(.fractionLength(1))
        )
    }

    private func saveCapture() {
        guard
            controller.addCustomPreset(
                name: capturedName,
                width: capturedWidth,
                height: capturedHeight
            ) != nil
        else {
            return
        }
        isPresentingSaveSheet = false
    }
}

private struct CustomPanelSizeRow: View {
    let preset: CustomPanelSizePreset
    let canApply: Bool
    let onSave: (String, Double, Double) -> Void
    let onApply: () -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var width: Double
    @State private var height: Double

    init(
        preset: CustomPanelSizePreset,
        canApply: Bool,
        onSave: @escaping (String, Double, Double) -> Void,
        onApply: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.preset = preset
        self.canApply = canApply
        self.onSave = onSave
        self.onApply = onApply
        self.onDelete = onDelete
        _name = State(initialValue: preset.name)
        _width = State(initialValue: preset.contentSize.width)
        _height = State(initialValue: preset.contentSize.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            HStack {
                TextField("Preset name", text: $name)
                    .accessibilityLabel("Preset name")
            }

            HStack {
                dimensionField("Width", value: $width)
                Text("×")
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .accessibilityHidden(true)
                dimensionField("Height", value: $height)
                Text("pt")
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                Spacer()
            }

            HStack {
                Spacer()
                Button("Save Changes") {
                    onSave(name, width, height)
                }
                Button("Apply", action: onApply)
                    .disabled(!canApply)
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
        .padding(.vertical, 2)
    }

    private func dimensionField(
        _ label: String,
        value: Binding<Double>
    ) -> some View {
        TextField(
            label,
            value: value,
            format: .number.precision(.fractionLength(0))
        )
        .frame(width: 72)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel(label)
    }
}
