import AppKit

struct NotionPageDropSession {
    private var activeDrop: (sequenceNumber: Int, drop: NotionPageDrop)?
    private var copyIsAllowed = false

    mutating func update(
        sequenceNumber: Int,
        candidate: NotionPageDrop?,
        sourceOperationMask: NSDragOperation
    ) -> NSDragOperation {
        if activeDrop?.sequenceNumber != sequenceNumber {
            reset()
        }
        if activeDrop == nil, let candidate {
            activeDrop = (sequenceNumber, candidate)
        }
        copyIsAllowed = activeDrop != nil && sourceOperationMask.contains(.copy)
        return copyIsAllowed ? .copy : []
    }

    func canPrepare(sequenceNumber: Int) -> Bool {
        copyIsAllowed && activeDrop?.sequenceNumber == sequenceNumber
    }

    func frozenCandidate(sequenceNumber: Int) -> NotionPageDrop? {
        guard activeDrop?.sequenceNumber == sequenceNumber else { return nil }
        return activeDrop?.drop
    }

    mutating func perform(sequenceNumber: Int) -> NotionPageDrop? {
        guard copyIsAllowed,
              let activeDrop,
              activeDrop.sequenceNumber == sequenceNumber
        else {
            return nil
        }
        reset()
        return activeDrop.drop
    }

    mutating func reset() {
        activeDrop = nil
        copyIsAllowed = false
    }
}
