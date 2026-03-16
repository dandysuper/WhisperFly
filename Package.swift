// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhisperFly",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WhisperFly",
            path: "Sources/WhisperFly",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "WhisperFlyTests",
            dependencies: ["WhisperFly"],
            path: "Tests/WhisperFlyTests"
        ),
    ]
)
