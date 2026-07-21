import AppKit

protocol PasteboardReading {
    func readString() -> String?
}

struct SystemPasteboardReader: PasteboardReading {
    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
