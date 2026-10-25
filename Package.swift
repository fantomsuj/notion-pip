// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Perch", targets: ["Perch"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            from: "2.9.6"
        ),
    ],
    targets: [
        .executableTarget(
            name: "Perch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Perch",
            resources: [
                .copy("Resources/stream-to-perch"),
            ],
            swiftSettings: [
                // Debug builds (`swift build`, `swift test`, and
                // `script/build_and_run.sh`) are developer builds: they turn on the
                // Web Inspector and the live diagnostics HUD. Release builds never
                // compile that code.
                .define("PERCH_DEVELOPER", .when(configuration: .debug)),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .testTarget(
            name: "PerchTests",
            dependencies: ["Perch"],
            path: "Tests/PerchTests",
            swiftSettings: [
                .define("PERCH_DEVELOPER", .when(configuration: .debug)),
            ]
        ),
    ]
)
