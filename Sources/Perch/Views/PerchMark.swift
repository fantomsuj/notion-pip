import SwiftUI

enum PerchMarkMotionPolicy {
    static let duration: TimeInterval = 0.12

    static func separation(isActive: Bool, reducesMotion: Bool) -> CGFloat {
        isActive && !reducesMotion ? 1.5 : 0
    }
}

struct PerchMark: View {
    let isActive: Bool
    var lineWidth: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let separation = PerchMarkMotionPolicy.separation(
            isActive: isActive,
            reducesMotion: reduceMotion
        )

        ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(lineWidth: lineWidth)
                .offset(x: -0.75 - separation / 2, y: -0.75 - separation / 2)
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(lineWidth: lineWidth)
                .offset(x: 0.75 + separation / 2, y: 0.75 + separation / 2)
        }
        .frame(width: 11, height: 9)
        .animation(
            reduceMotion ? nil : .easeOut(duration: PerchMarkMotionPolicy.duration),
            value: isActive
        )
        .accessibilityHidden(true)
    }
}

struct PerchIdentityLabel: View {
    let title: String
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            PerchMark(isActive: isHovering)
            Text(title)
        }
        .onHover { isHovering = $0 }
    }
}
