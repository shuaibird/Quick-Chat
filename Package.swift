// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickChat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "QuickChat",
            path: "Sources/QuickChat"
        ),
        .testTarget(name: "QuickChatTests", dependencies: ["QuickChat"]),
    ]
)
