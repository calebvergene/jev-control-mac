// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JevControl",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Pinned to 0.13.x deliberately: 0.15+ pulls swift-jinja, whose manifest
        // needs Swift tools 6.0, so it cannot be built with the Command Line
        // Tools toolchain this project targets.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", .upToNextMinor(from: "0.13.0"))
    ],
    targets: [
        .executableTarget(
            name: "JevControl",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            path: "Sources/JevControl",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
