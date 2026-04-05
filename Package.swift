// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThrawnConsole",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ThrawnApp",
            path: "Sources/ThrawnApp",
            resources: [
                .copy("Resources/clock-reference-default.png"),
                .copy("Resources/Assets.xcassets")
            ]
        )
    ]
)
