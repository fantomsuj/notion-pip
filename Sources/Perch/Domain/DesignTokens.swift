import AppKit
import SwiftUI

enum DesignTokens {
    enum Spacing {
        static let compact: CGFloat = 4
        static let control: CGFloat = 8
        static let section: CGFloat = 12
        static let container: CGFloat = 16
    }

    enum Radius {
        static let control: CGFloat = 6
        static let card: CGFloat = 8
        static let panel: CGFloat = 10
    }

    enum Colors {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let surface = Color(nsColor: .controlBackgroundColor)
        static let primaryText = Color(nsColor: .labelColor)
        static let secondaryText = Color(nsColor: .secondaryLabelColor)
        static let border = Color(nsColor: .separatorColor)
        static let action = Color(nsColor: .systemBlue)
        static let error = Color(nsColor: .systemRed)
    }
}
