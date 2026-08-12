import Foundation

final class OnboardingPreferenceStore {
    static let completedVersionKey = "onboardingCompletedVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shouldPresent(version: Int) -> Bool {
        defaults.integer(forKey: Self.completedVersionKey) < version
    }

    func markCompleted(version: Int) {
        defaults.set(version, forKey: Self.completedVersionKey)
    }
}
