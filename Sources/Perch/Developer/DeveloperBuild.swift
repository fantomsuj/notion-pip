import Foundation

/// Whether this binary is a developer build.
///
/// Debug builds define `PERCH_DEVELOPER` (see `Package.swift`). Those builds make
/// the Notion web view inspectable from Safari's Develop menu and add a Developer
/// menu with a live diagnostics HUD. Release builds, including every notarized DMG,
/// compile none of that code.
enum DeveloperBuild {
    #if PERCH_DEVELOPER
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    /// Launch argument that opens the diagnostics HUD at startup, for example
    /// `open dist/Perch.app --args -PerchShowDiagnosticsHUD YES`.
    static let showHUDAtLaunchDefaultsKey = "PerchShowDiagnosticsHUD"
}
