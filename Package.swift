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
                "ThrawnConsole.entitlements",
                // Thrawn provider credentials use non-interactive environment
                // or private app-support config loading. Keeping the legacy
                // Security helpers out of the target prevents macOS Keychain
                // authorization dialogs from ever being triggered at runtime.
                "Models/KeychainHelper.swift",
                "Models/KeychainStore.swift"
            ],
            resources: [
                .copy("Resources/clock-reference-default.png"),
                .copy("Resources/thrawn-agent-avatar.png"),
                .copy("Resources/samwell-agent-avatar.png"),
                .copy("Resources/sir-davos-agent-avatar.png"),
                .copy("Resources/dwight-agent-avatar.png"),
                .copy("Resources/spas360-logo.png"),
                .copy("Resources/hitzero-logo.png"),
                .copy("Resources/sandpro-omp-logo.png"),
                .copy("Resources/Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "ThrawnAppTests",
            dependencies: ["ThrawnApp"],
            path: "Tests/ThrawnAppTests"
        )
    ]
)
