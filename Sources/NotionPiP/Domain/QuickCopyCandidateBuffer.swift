import Foundation

struct QuickCopyCandidateBuffer: Sendable {
    enum EnqueueResult: Equatable, Sendable {
        case accepted
        case atCapacity
    }

    static let standardCapacity = 8

    let capacity: Int
    private var storage: [QuickCopyCandidate?]
    private var headIndex = 0
    private(set) var count = 0

    init(capacity: Int = Self.standardCapacity) {
        self.capacity = max(1, capacity)
        storage = Array(repeating: nil, count: self.capacity)
    }

    var isEmpty: Bool { count == 0 }

    var front: QuickCopyCandidate? {
        guard count > 0 else { return nil }
        return storage[headIndex]
    }

    @discardableResult
    mutating func enqueue(_ candidate: QuickCopyCandidate) -> EnqueueResult {
        guard count < capacity else { return .atCapacity }
        let insertionIndex = (headIndex + count) % capacity
        storage[insertionIndex] = candidate
        count += 1
        return .accepted
    }

    @discardableResult
    mutating func dequeue() -> QuickCopyCandidate? {
        guard count > 0 else { return nil }
        let candidate = storage[headIndex]
        storage[headIndex] = nil
        headIndex = (headIndex + 1) % capacity
        count -= 1
        if count == 0 { headIndex = 0 }
        return candidate
    }

    mutating func removeAll() {
        for index in storage.indices {
            storage[index] = nil
        }
        headIndex = 0
        count = 0
    }
}
