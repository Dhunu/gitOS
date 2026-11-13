// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitOS",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .executableTarget(name: "GitOS", dependencies: ["Sparkle"], path: "Sources/GitOS",
                          exclude: ["ee/LICENSE", "ee/README.md"]),
        .testTarget(name: "GitOSTests", dependencies: ["GitOS"], path: "Tests/GitOSTests"),
    ]
)
