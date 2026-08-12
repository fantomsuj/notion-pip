import AppKit

@MainActor
enum NotionPageDropPasteboardReader {
    private static let urlNameType = NSPasteboard.PasteboardType("public.url-name")

    static func candidate(from pasteboard: NSPasteboard) -> NotionPageDrop? {
        guard let items = pasteboard.pasteboardItems, items.count == 1,
              let item = items.first
        else {
            return nil
        }

        let sourceLabel = item.string(forType: urlNameType)
        if let urlString = item.string(forType: .URL) {
            return candidate(
                validating: urlString,
                sourceLabel: sourceLabel,
                trimsWhitespace: false
            )
        }
        guard let string = item.string(forType: .string) else {
            return nil
        }
        return candidate(
            validating: string,
            sourceLabel: sourceLabel,
            trimsWhitespace: true
        )
    }

    private static func candidate(
        validating rawURL: String,
        sourceLabel: String?,
        trimsWhitespace: Bool
    ) -> NotionPageDrop? {
        let urlString = trimsWhitespace
            ? rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            : rawURL
        guard let url = URL(string: urlString), url.absoluteString == urlString else {
            return nil
        }
        return try? NotionPageDrop(validating: url, sourceLabel: sourceLabel)
    }
}
