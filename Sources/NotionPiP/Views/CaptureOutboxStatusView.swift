import SwiftUI

struct CaptureDeliveryPresentation: Equatable {
    let label: String
    let symbol: String
    let needsRecovery: Bool

    init(state: DeliveryState) {
        switch state {
        case .queued:
            self = .init(label: "Queued", symbol: "clock", needsRecovery: false)
        case .inFlight:
            self = .init(label: "Delivering", symbol: "arrow.up.circle", needsRecovery: false)
        case .delivered:
            self = .init(label: "Delivered", symbol: "checkmark.circle", needsRecovery: false)
        case .retrying:
            self = .init(label: "Retrying", symbol: "arrow.clockwise.circle", needsRecovery: false)
        case .blockedConflict:
            self = .init(label: "Needs review", symbol: "exclamationmark.triangle", needsRecovery: true)
        case .uncertain:
            self = .init(label: "Delivery uncertain", symbol: "questionmark.diamond", needsRecovery: true)
        }
    }

    private init(label: String, symbol: String, needsRecovery: Bool) {
        self.label = label
        self.symbol = symbol
        self.needsRecovery = needsRecovery
    }
}

struct CaptureOutboxStatusView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
            if runtime.captureRecords.isEmpty {
                Text("No captures have been queued yet.")
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                ForEach(runtime.captureRecords.prefix(10), id: \.id) { record in
                    let presentation = CaptureDeliveryPresentation(state: record.state)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                        HStack {
                            Label(
                                record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Untitled"
                                    : record.title,
                                systemImage: presentation.symbol
                            )
                            Spacer()
                            Text(presentation.label)
                                .font(.caption)
                                .foregroundStyle(
                                    presentation.needsRecovery
                                        ? DesignTokens.Colors.error
                                        : DesignTokens.Colors.secondaryText
                                )
                        }
                        if let message = record.safeError?.message {
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                        }
                        if presentation.needsRecovery {
                            Button("Open Local Capture") {
                                Task { await runtime.openLocalCapture(recordID: record.id) }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            if let message = runtime.captureRecoveryMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
            }

            Button("Refresh Status") {
                Task { await runtime.refreshCaptureRecords() }
            }
            .controlSize(.small)
        }
        .task {
            await runtime.refreshCaptureRecords()
        }
    }
}
