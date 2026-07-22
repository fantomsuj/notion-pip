import SwiftUI

struct CaptureStatusView: View {
    let status: CaptureEditorStatus

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(isFailure ? DesignTokens.Colors.error : DesignTokens.Colors.secondaryText)
            .accessibilityLabel(label)
    }

    private var label: String {
        switch status {
        case .loading: "Loading editor"
        case .ready: "Ready"
        case .saving: "Saving"
        case let .saved(revision): "Saved revision \(revision)"
        case .stashed: "Draft stashed"
        case let .failed(message): message
        }
    }

    private var symbol: String {
        switch status {
        case .loading, .saving: "arrow.triangle.2.circlepath"
        case .ready: "square.and.pencil"
        case .saved: "checkmark.circle"
        case .stashed: "archivebox"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var isFailure: Bool {
        if case .failed = status { true } else { false }
    }
}
