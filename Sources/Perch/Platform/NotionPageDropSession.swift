import AppKit

struct NotionPageDropSession {
    private var activeDrop: (sequenceNumber: Int, drop: NotionPageDrop)?

    mutating func update(
        sequenceNumber: Int,
        candidate: NotionPageDrop?,
        sourceOperationMask: NSDragOperation
    ) -> NSDragOperation {
        if activeDrop?.sequenceNumber != sequenceNumber {
            reset()
        }
        guard sourceOperationMask.contains(.copy) else {
            reset()
            return []
        }
        if activeDrop != nil {
            return .copy
        }
        guard let candidate else {
            return []
        }

        activeDrop = (sequenceNumber, candidate)
        return .copy
    }

    func canPrepare(sequenceNumber: Int) -> Bool {
        activeDrop?.sequenceNumber == sequenceNumber
    }

    mutating func perform(sequenceNumber: Int) -> NotionPageDrop? {
        guard let activeDrop, activeDrop.sequenceNumber == sequenceNumber else {
            return nil
        }
        reset()
        return activeDrop.drop
    }

    mutating func reset() {
        activeDrop = nil
    }
}
