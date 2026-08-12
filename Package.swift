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
    targets: [
        .executableTarget(
            name: "Perch",
            path: "Sources/Perch"
        ),
        .testTarget(
            name: "PerchTests",
            dependencies: ["Perch"],
            path: "Tests/PerchTests"
        ),
    ]
)
