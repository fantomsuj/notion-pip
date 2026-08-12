import Foundation

struct QuickCopySource: Equatable, Sendable {
    let processID: pid_t
    let bundleIdentifier: String?
    let applicationName: String?
    let isSecure: Bool
    let supportsSelectedText: Bool

    init(
        processID: pid_t,
        bundleIdentifier: String? = nil,
        applicationName: String? = nil,
        isSecure: Bool = false,
        supportsSelectedText: Bool = true
    ) {
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.isSecure = isSecure
        self.supportsSelectedText = supportsSelectedText
    }
}

struct QuickCopyCandidate: Equatable, Sendable {
    let text: String
    let source: QuickCopySource
    let sequence: UInt64
}

enum QuickCopyRejection: Equatable, Sendable {
    case secureField
    case unsupportedSource(String?)
    case oversized
}

struct QuickCopyPolicy: Sendable {
    enum Decision: Equatable, Sendable {
        case accept
        case ignore
        case reject(QuickCopyRejection)
    }

    static let defaultMaximumUTF8Bytes = 256 * 1_024

    let maximumUTF8Bytes: Int
    let ownProcessID: pid_t

    init(
        maximumUTF8Bytes: Int = defaultMaximumUTF8Bytes,
        ownProcessID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.maximumUTF8Bytes = maximumUTF8Bytes
        self.ownProcessID = ownProcessID
    }

    func decision(
        for candidate: QuickCopyCandidate,
        lastAcceptedSequence: UInt64?
    ) -> Decision {
        if candidate.sequence == lastAcceptedSequence
            || candidate.source.processID == ownProcessID
            || candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return .ignore
        }
        if candidate.source.isSecure {
            return .reject(.secureField)
        }
        if !candidate.source.supportsSelectedText {
            return .reject(.unsupportedSource(candidate.source.applicationName))
        }
        if candidate.text.utf8.count > maximumUTF8Bytes {
            return .reject(.oversized)
        }
        return .accept
    }
}
