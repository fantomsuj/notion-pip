import Foundation

enum FlipIdentity: Sendable {
    static let bundleIdentifier = "com.fantomsuj.Flip"
    static let displayName = "Flip"
    static let perchBundleIdentifier = "com.fantomsuj.Perch"
    static let legacyPerchBundleIdentifier = "com.fantomsuj.NotionPiP"

    static let excludedBundleIdentifiers: Set<String> = [
        bundleIdentifier,
        perchBundleIdentifier,
        legacyPerchBundleIdentifier,
    ]
}
