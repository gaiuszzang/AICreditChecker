// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AICreditChecker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AICreditChecker", path: "Sources/AICreditChecker")
    ]
)
