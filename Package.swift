// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NotionPiP",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "NotionPiP", targets: ["NotionPiP"]),
    ],
    targets: [
        .executableTarget(
            name: "NotionPiP",
            path: "Sources/NotionPiP"
        ),
        .testTarget(
            name: "NotionPiPTests",
            dependencies: ["NotionPiP"],
            path: "Tests/NotionPiPTests"
        ),
    ]
)
