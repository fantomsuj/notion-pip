import AppKit
import Combine
import Foundation

/// Why Copy for Agent had nothing to copy.
enum AgentPageCopyError: Error, Equatable, Sendable {
    /// No Notion page or custom pin is open in Perch.
    case noPage
}

/// Short confirmation shown in the panel after Copy for Agent.
enum AgentPageCopyFeedback: Equatable, Sendable {
    case copied(wordCount: Int, coverage: AgentPageSnapshot.Coverage, truncated: Bool)
    case noPage
    case clipboardUnavailable

    var message: String {
        switch self {
        case let .copied(wordCount, coverage, truncated):
            if coverage == .linkOnly {
                return "Copied page link for agent"
            }
            let words = wordCount.formatted(.number)
            let unit = wordCount == 1 ? "word" : "words"
            return truncated
                ? "Copied for agent · \(words) \(unit), truncated"
                : "Copied for agent · \(words) \(unit)"
        case .noPage:
            return "Open a page to copy it for an agent"
        case .clipboardUnavailable:
            return "Couldn’t write to the clipboard"
        }
    }

    var isError: Bool {
        switch self {
        case .copied:
            false
        case .noPage, .clipboardUnavailable:
            true
        }
    }
}

typealias AgentPageSnapshotReader = @MainActor (
    @escaping @MainActor (Result<AgentPageSnapshot, AgentPageCopyError>) -> Void
) -> Void

/// Runs Copy for Agent: reads the open page, writes Markdown to the clipboard,
/// and publishes a brief confirmation for the panel.
@MainActor
final class AgentPageCopyController: ObservableObject {
    static let feedbackDuration: TimeInterval = 2.5

    @Published private(set) var feedback: AgentPageCopyFeedback?

    private let readPage: AgentPageSnapshotReader
    private let writeToClipboard: @MainActor (String) -> Bool
    private let now: @MainActor () -> Date
    private let scheduleFeedbackClear: NotionWebEvictionScheduler
    private var isCopying = false
    private var feedbackClearCancellable: AnyCancellable?

    init(
        readPage: @escaping AgentPageSnapshotReader,
        writeToClipboard: @escaping @MainActor (String) -> Bool = AgentPageCopyController
            .writeToGeneralPasteboard,
        now: @escaping @MainActor () -> Date = { Date() },
        scheduleFeedbackClear: @escaping NotionWebEvictionScheduler = { interval, action in
            let task = Task { @MainActor in
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                action()
            }
            return AnyCancellable { task.cancel() }
        }
    ) {
        self.readPage = readPage
        self.writeToClipboard = writeToClipboard
        self.now = now
        self.scheduleFeedbackClear = scheduleFeedbackClear
    }

    convenience init(webSession: NotionWebSession) {
        self.init(readPage: { [weak webSession] completion in
            guard let webSession else {
                completion(.failure(.noPage))
                return
            }
            webSession.readPageForAgent(completion: completion)
        })
    }

    func copy() {
        guard !isCopying else { return }
        isCopying = true
        readPage { [weak self] result in
            guard let self else { return }
            self.isCopying = false
            switch result {
            case .failure(.noPage):
                self.show(.noPage)
            case let .success(snapshot):
                let markdown = AgentPageContextFormatter.markdown(
                    for: snapshot,
                    copiedAt: self.now()
                )
                guard self.writeToClipboard(markdown) else {
                    self.show(.clipboardUnavailable)
                    return
                }
                self.show(
                    .copied(
                        wordCount: snapshot.wordCount,
                        coverage: snapshot.coverage,
                        truncated: snapshot.wasTruncatedByReader
                            || markdown.hasSuffix(
                                AgentPageContextFormatter.truncationMarker + "\n"
                            )
                    )
                )
            }
        }
    }

    private func show(_ feedback: AgentPageCopyFeedback) {
        self.feedback = feedback
        feedbackClearCancellable = scheduleFeedbackClear(Self.feedbackDuration) { [weak self] in
            self?.feedback = nil
        }
    }

    static func writeToGeneralPasteboard(_ markdown: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(markdown, forType: .string)
    }
}
