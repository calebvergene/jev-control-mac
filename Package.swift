// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JevControl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "JevControl",
            path: "Sources/JevControl",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
