// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShoutMeter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ShoutMeter",
            path: "Sources/ShoutMeter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ShoutMeterTests",
            dependencies: ["ShoutMeter"],
            path: "Tests/ShoutMeterTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
