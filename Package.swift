// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AmIShouting",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AmIShouting",
            path: "Sources/AmIShouting",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AmIShoutingTests",
            dependencies: ["AmIShouting"],
            path: "Tests/AmIShoutingTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
