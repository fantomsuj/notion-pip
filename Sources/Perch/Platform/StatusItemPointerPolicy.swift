enum StatusItemPointerPhase: Equatable, Sendable {
    case idle
    case holding
    case peeking
}

enum StatusItemPointerEvent: Equatable, Sendable {
    case leftMouseDown
    case leftMouseUp(isPointerInside: Bool)
    case rightMouseUp
    case holdElapsed
}

enum StatusItemPointerCommand: Equatable, Sendable {
    case beginHold
    case beginPeek
    case commitPeek
    case cancelPeek
    case showMenu
}

enum StatusItemPointerPolicy {
    static func handle(
        phase: StatusItemPointerPhase,
        event: StatusItemPointerEvent
    ) -> (StatusItemPointerPhase, [StatusItemPointerCommand]) {
        switch (phase, event) {
        case (.idle, .leftMouseDown):
            (.holding, [.beginHold])
        case (.holding, .leftMouseDown), (.peeking, .leftMouseDown):
            (phase, [])
        case (.idle, .leftMouseUp), (.holding, .leftMouseUp):
            (.idle, [.showMenu])
        case (.peeking, .leftMouseUp(true)):
            (.idle, [.commitPeek])
        case (.peeking, .leftMouseUp(false)):
            (.idle, [.cancelPeek])
        case (.peeking, .rightMouseUp):
            (.idle, [.cancelPeek, .showMenu])
        case (_, .rightMouseUp):
            (.idle, [.showMenu])
        case (.holding, .holdElapsed):
            (.peeking, [.beginPeek])
        case (_, .holdElapsed):
            (phase, [])
        }
    }
}
