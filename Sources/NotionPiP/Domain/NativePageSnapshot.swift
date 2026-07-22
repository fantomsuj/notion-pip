import Foundation

enum NotionBlockKind: Equatable, Sendable, Codable {
    case paragraph
    case heading(level: Int)
    case bulletedList
    case numberedList
    case toDo
    case quote
    case toggle
    case code
    case divider
    case image
    case unsupported(String)

}

struct NativePageBlock: Equatable, Identifiable, Sendable, Codable {
    let id: String
    var kind: NotionBlockKind
    var text: String
    var checked: Bool

    init(id: String, kind: NotionBlockKind, text: String = "", checked: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.checked = checked
    }
}

struct NativePageSnapshot: Equatable, Sendable, Codable {
    let pageID: String
    var title: String
    var blocks: [NativePageBlock]
    let remoteFingerprint: String
    let fetchedAt: Date
}
