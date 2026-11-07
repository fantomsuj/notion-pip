import AppKit
import Combine
import SwiftUI

/// Jots a note from the pointer in any app and drops it into the Notion page
/// open in Perch.
///
/// The note lands where the cursor last was in the Perch page, as one bullet
/// that keeps the time and the app (and window) it was jotted from. When the
/// page has no cursor yet, or Perch has no page loaded, the note waits on this
/// Mac until it can be dropped in, so nothing is lost.
@MainActor
final class MarginNoteController: ObservableObject {
    @Published private(set) var waitingNotes: [MarginNote]
    @Published private(set) var isComposing = false

    private weak var target: (any AgentStreamTarget)?
    private let queueStore: MarginNoteQueueStore
    private let notify: @MainActor (String) -> Void
    private let now: @MainActor () -> Date
    private var panel: MarginNotePanel?
    private var draft: MarginNoteDraft?
    private var resignObserver: NSObjectProtocol?

    init(
        target: (any AgentStreamTarget)?,
        queueStore: MarginNoteQueueStore = MarginNoteQueueStore(),
        notify: @escaping @MainActor (String) -> Void,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.target = target
        self.queueStore = queueStore
        self.notify = notify
        self.now = now
        waitingNotes = queueStore.load()
    }

    /// Opens a note card at the pointer. Return saves, Escape cancels.
    func beginNote() {
        if isComposing {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        // Read the source before Perch's card takes focus.
        let source = MarginNoteSourceReader.read()
        let draft = MarginNoteDraft(source: source, createdAt: now())
        self.draft = draft

        let panel = panel ?? MarginNotePanel.make()
        let view = MarginNoteCardView(
            draft: draft,
            onSave: { [weak self] in self?.finishComposing(save: true) },
            onCancel: { [weak self] in self?.finishComposing(save: false) }
        )
        let hostingView = NSHostingView(rootView: view)
        panel.contentView = hostingView
        let size = hostingView.fittingSize
        panel.setFrame(Self.frame(for: size, near: NSEvent.mouseLocation), display: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        isComposing = true

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            // Clicking away keeps what was typed rather than throwing it out.
            MainActor.assumeIsolated {
                self?.finishComposing(save: true)
            }
        }
    }

    /// Tries to drop every waiting note into the Perch page, oldest first.
    func dropWaitingNotes() {
        guard !waitingNotes.isEmpty else { return }
        let notes = waitingNotes
        deliver(notes) { [weak self] delivered in
            guard let self else { return }
            if delivered {
                self.removeWaiting(notes)
                self.notify(notes.count == 1 ? "Dropped 1 note into Notion." : "Dropped \(notes.count) notes into Notion.")
            } else {
                self.notify("Click where the notes should go in your Perch page, then try again.")
            }
        }
    }

    /// Copies every waiting note as Markdown, to paste anywhere.
    func copyWaitingNotes(to pasteboard: NSPasteboard = .general) {
        guard !waitingNotes.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(Self.markdown(for: waitingNotes), forType: .string)
    }

    func clearWaitingNotes() {
        waitingNotes = []
        queueStore.save([])
    }

    func stop() {
        guard isComposing else { return }
        finishComposing(save: true)
    }

    // MARK: - Composing

    private func finishComposing(save: Bool) {
        guard isComposing else { return }
        isComposing = false
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        let draft = self.draft
        self.draft = nil
        panel?.orderOut(nil)
        panel?.contentView = nil

        guard save, let draft, let text = MarginNote.normalizedText(draft.text) else { return }
        let note = MarginNote(text: text, createdAt: draft.createdAt, source: draft.source)
        submit(note)
    }

    /// Drops the note into the Perch page, or keeps it waiting.
    func submit(_ note: MarginNote) {
        // Older waiting notes go first, so the page keeps them in order.
        let notes = waitingNotes + [note]
        deliver(notes) { [weak self] delivered in
            guard let self else { return }
            if delivered {
                self.removeWaiting(notes)
                self.notify("Noted in Notion.")
            } else {
                self.appendWaiting(note)
                self.notify("Saved. It will wait until you click in your Perch page and drop it in from Settings.")
            }
        }
    }

    private func deliver(_ notes: [MarginNote], completion: @escaping @MainActor (Bool) -> Void) {
        guard let target, target.isAgentStreamTargetAvailable, !notes.isEmpty else {
            completion(false)
            return
        }
        let markdown = Self.markdown(for: notes)
        target.rememberCurrentEditorCursor { [weak target] hasCursor in
            guard hasCursor, let target else {
                completion(false)
                return
            }
            target.pasteMarkdownAtSavedEditorCursor(markdown, completion: completion)
        }
    }

    private static func markdown(for notes: [MarginNote]) -> String {
        notes.map { $0.markdown() }.joined(separator: "\n") + "\n"
    }

    private func appendWaiting(_ note: MarginNote) {
        guard !waitingNotes.contains(where: { $0.id == note.id }) else { return }
        waitingNotes.append(note)
        queueStore.save(waitingNotes)
    }

    private func removeWaiting(_ notes: [MarginNote]) {
        let delivered = Set(notes.map(\.id))
        let remaining = waitingNotes.filter { !delivered.contains($0.id) }
        guard remaining != waitingNotes else { return }
        waitingNotes = remaining
        queueStore.save(remaining)
    }

    /// Below and to the right of the pointer, kept on the pointer's screen.
    private static func frame(for size: CGSize, near point: CGPoint) -> CGRect {
        var frame = CGRect(
            x: point.x + 12,
            y: point.y - 12 - size.height,
            width: size.width,
            height: size.height
        )
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - size.width - 8)
        frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - size.height - 8)
        return frame
    }
}

@MainActor
final class MarginNoteDraft: ObservableObject {
    @Published var text = ""
    let source: MarginNoteSource?
    let createdAt: Date

    init(source: MarginNoteSource?, createdAt: Date) {
        self.source = source
        self.createdAt = createdAt
    }
}

/// A small card that takes typing without pulling the app underneath out of
/// the front, like Spotlight.
final class MarginNotePanel: NSPanel {
    static func make() -> MarginNotePanel {
        let panel = MarginNotePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct MarginNoteCardView: View {
    @ObservedObject var draft: MarginNoteDraft
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
            HStack(spacing: DesignTokens.Spacing.compact) {
                Image(systemName: "pencil.line")
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                Text(sourceLine)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            .font(.caption)

            TextField("Jot a note…", text: $draft.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1 ... 6)
                .focused($isFocused)
                .onSubmit(onSave)
                .onExitCommand(perform: onCancel)

            Text("Return to save · Esc to cancel")
                .font(.caption2)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .padding(DesignTokens.Spacing.section)
        .frame(width: 300, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
                .strokeBorder(DesignTokens.Colors.border)
        )
        .onAppear { isFocused = true }
    }

    private var sourceLine: String {
        let time = draft.createdAt.formatted(date: .omitted, time: .shortened)
        guard let source = draft.source else { return time }
        return "\(source.summary) · \(time)"
    }
}
