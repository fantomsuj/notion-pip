import CoreGraphics

enum CursorAdjacentControlPlacement {
    static let controlSize: CGFloat = 30
    static let gap: CGFloat = 6
    static let inset: CGFloat = 8

    static func center(
        for geometry: NotionEditorCaretGeometry?,
        in viewSize: CGSize
    ) -> CGPoint {
        let maximumX = max(inset, viewSize.width - inset - controlSize)
        let maximumY = max(inset, viewSize.height - inset - controlSize)

        guard let geometry else {
            return CGPoint(
                x: maximumX + controlSize / 2,
                y: maximumY + controlSize / 2
            )
        }

        let horizontalScale = viewSize.width / geometry.viewportWidth
        let verticalScale = viewSize.height / geometry.viewportHeight
        let caretLeft = geometry.left * horizontalScale
        let caretTop = geometry.top * verticalScale
        let caretBottom = geometry.bottom * verticalScale

        var x = caretLeft + gap
        if x + controlSize > viewSize.width {
            x = caretLeft - gap - controlSize
        }
        var y = caretBottom + gap
        if y + controlSize > viewSize.height {
            y = caretTop - gap - controlSize
        }

        x = min(max(x, inset), maximumX)
        y = min(max(y, inset), maximumY)
        return CGPoint(x: x + controlSize / 2, y: y + controlSize / 2)
    }
}
