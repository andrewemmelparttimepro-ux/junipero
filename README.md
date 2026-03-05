# Junipero

A native macOS SwiftUI chat client for [OpenClaw](https://openclaw.ai).

## Overview

Junipero is a clean, fast macOS app that interfaces with the OpenClaw gateway. It features:

- **Two-panel layout** — left panel with analog clock + Bitcoin widget, right panel with threaded chat
- **Thread management** — create, browse, and continue conversations
- **Real-time streaming** — live response streaming from OpenClaw
- **Native macOS feel** — built with SwiftUI, targets macOS 13+

## Structure

```
Sources/JuniperoApp/
├── JuniperoApp.swift          # App entry point
├── ContentView.swift          # Root layout
├── LeftPanel/
│   ├── LeftPanelView.swift
│   ├── AnalogClockView.swift
│   └── BitcoinWidget.swift
├── RightPanel/
│   ├── RightPanelView.swift
│   ├── ThreadListView.swift
│   ├── ThreadDetailView.swift
│   ├── ThreadCard.swift
│   └── ChatInputView.swift
└── Models/
    ├── Thread.swift
    ├── ThreadStore.swift
    ├── OpenClawClient.swift
    └── ChatDiagnostics.swift
```

## Requirements

- macOS 13+
- Xcode 15+ or Swift 5.9+
- OpenClaw gateway running locally

## Build

Open in Xcode or build via Swift Package Manager:

```bash
swift build
swift run
```

## Local Distro (Universal + Apple-style DMG)

Build a clean desktop distro folder with:
- universal `Junipero.app` (Intel + Apple Silicon)
- drag-to-Applications `Junipero.dmg` (includes `Applications` alias)
- checksums and architecture report

```bash
./scripts/build-local-distro.sh
```

Output:
- `~/Desktop/junipero_distro`
- `~/Desktop/junipero-distro` (optional copy target for handoff)

The packaged app includes Sparkle feed metadata (`SUFeedURL`) so in-app update checks can run.

## Release (Signed + Notarized)

See [RELEASE_SIGNING.md](RELEASE_SIGNING.md) for end-to-end macOS signing/notarization.

Once credentials are configured:

```bash
export DEVELOPER_ID_APP_CERT="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="junipero-notary"
export APPCAST_URL="https://raw.githubusercontent.com/andrewemmelparttimepro-ux/junipero/main/appcast.xml"
./scripts/release-macos.sh
```

## License

Private — Andrew Emmel / BoredRoom
