import Foundation

struct AppMetadata: Equatable, Sendable {
    let versionAndBuild: String
    let minimumSystemVersion: String
    let copyright: String?

    init(infoDictionary: [String: Any]) {
        let version = infoDictionary["CFBundleShortVersionString"] as? String
        let build = infoDictionary["CFBundleVersion"] as? String

        if let version, !version.isEmpty, let build, !build.isEmpty {
            versionAndBuild = "\(version) (\(build))"
        } else if let version, !version.isEmpty {
            versionAndBuild = version
        } else {
            versionAndBuild = "Unknown"
        }

        minimumSystemVersion =
            (infoDictionary["LSMinimumSystemVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Unknown"
        copyright =
            (infoDictionary["NSHumanReadableCopyright"] as? String).flatMap {
                $0.isEmpty ? nil : $0
            }
    }

    static var current: AppMetadata {
        AppMetadata(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }
}
