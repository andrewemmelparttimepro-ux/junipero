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
            // Entitlements file is consumed by the App Store / codesign step,
            // not by SPM at compile time. Excluding silences the unhandled-file
            // warning without affecting distribution builds.
            exclude: [
                "ThrawnConsole.entitlements"
            ],
            resources: [
                .copy("Resources/clock-reference-default.png"),
                .copy("Resources/Assets.xcassets")
            ]
        )
    ]
)
