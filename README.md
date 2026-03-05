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

## License

Private — Andrew Emmel / BoredRoom
