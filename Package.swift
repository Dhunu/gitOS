// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitOS",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "GitOS", path: "Sources/GitOS"),
        .testTarget(name: "GitOSTests", dependencies: ["GitOS"], path: "Tests/GitOSTests"),
    ]
)
