import Foundation

protocol CaptureClock: Sendable {
    func now() -> Date
}

struct SystemCaptureClock: CaptureClock {
    func now() -> Date { Date() }
}

struct RetryPolicy: Equatable, Sendable {
    var baseDelay: TimeInterval = 5
    var maximumDelay: TimeInterval = 6 * 60 * 60
    var attentionInterval: TimeInterval = 7 * 24 * 60 * 60

    func delay(forAttempt attempt: Int, retryAfter: TimeInterval? = nil) -> TimeInterval {
        if let retryAfter {
            return max(0, retryAfter)
        }
        let exponent = min(max(0, attempt - 1), 20)
        return min(baseDelay * pow(2, Double(exponent)), maximumDelay)
    }

    func requiresAttention(firstQueuedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(firstQueuedAt) >= attentionInterval
    }
}

struct RetentionPolicy: Equatable, Sendable {
    var retentionInterval: TimeInterval = 30 * 24 * 60 * 60
}

struct RetentionResult: Equatable, Sendable {
    let deletedRecords: Int
    let deletedDrafts: Int
}
