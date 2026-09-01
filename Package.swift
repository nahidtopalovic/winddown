// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Winddown",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Winddown", path: "Sources/Winddown")
    ]
)
