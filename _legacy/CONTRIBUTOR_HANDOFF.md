# Junipero Contributor Handoff

This document is a practical handoff for maintainers/contributors.

## Repository
- Path: `/Users/crustacean/.openclaw/workspace/projects/junipero`
- Branch: `main`
- App target: `Sources/JuniperoApp`

## Current Product State
Junipero is a native macOS SwiftUI chat app with:
- Threaded chat UX and persistent memory
- Unread tracking with prominent MSN-style visual indicators
- Retry/cancel/queue behavior for thread sends
- Copyable/selectable message bubbles
- Setup wizard for local runtime bootstrap
- OpenClaw primary runtime + Ollama fallback support
- Diagnostics, full health test, and support bundle export

## Major Runtime Features

### Bootstrap + Runtime Management
- `JuniperoBootstrap` handles startup/setup, runtime health, repair actions, and diagnostics.
- OpenClaw startup uses:
  - `openclaw gateway install`
  - `openclaw gateway start`
  - fallback background run if needed
- Ollama fallback startup and optional model pull supported.

Files:
- `Sources/JuniperoApp/Models/JuniperoBootstrap.swift`
- `Sources/JuniperoApp/Models/ShellCommand.swift`

### Setup Wizard
- First-run setup sheet appears when setup state is incomplete.
- Modes:
  - `Free Local`
  - `Bring Your Own Plan`
- Includes:
  - diagnostics
  - full test
  - fallback model fix
  - probation-gated capability mode

File:
- `Sources/JuniperoApp/SetupWizardView.swift`

### Capability / Guardrail Modes
- Mode switch:
  - `I'm an idiot` (strict)
  - `It's my fault` (relaxed)
- Unlock gating:
  - probation complete after either:
    - 8 interactions
    - ~6 hours elapsed

Preferences:
- persisted in `~/.junipero/preferences.json`
- model: `Sources/JuniperoApp/Models/JuniperoPreferences.swift`

### Security
- Provider token stored in macOS Keychain (not config plaintext).
- Keychain accessor:
  - `Sources/JuniperoApp/Models/KeychainStore.swift`

### Threading + Persistence
- Thread model supports multi-message conversations and unread count.
- Draft persistence supports keystroke-level durability.
- Queueing behavior for sends while thread is in-flight.

Files:
- `Sources/JuniperoApp/Models/Thread.swift`
- `Sources/JuniperoApp/Models/ThreadStore.swift`

### Thread UX
- Unread visual language:
  - neon "NEW" badge
  - glow + highlighted unread cards
- Detail view supports auto-scroll and message copy actions.

Files:
- `Sources/JuniperoApp/RightPanel/ThreadCard.swift`
- `Sources/JuniperoApp/RightPanel/ThreadListView.swift`
- `Sources/JuniperoApp/RightPanel/ThreadDetailView.swift`

### Theming
- Clock and Bitcoin widgets were tuned to match the blue/chrome neon language.

Files:
- `Sources/JuniperoApp/LeftPanel/AnalogClockView.swift`
- `Sources/JuniperoApp/LeftPanel/BitcoinWidget.swift`

## Release + Distribution

### Signing / Notarization
- End-to-end release script:
  - `scripts/release-macos.sh`
- Guide:
  - `RELEASE_SIGNING.md`

Current reality:
- Truly smooth public install requires Apple Developer membership (Developer ID + notarization).

### User Distribution Copy
- A distribution copy was placed at:
  - `/Users/crustacean/Desktop/junipero_distro/Junipero.app`

## Operational Buttons in Header
- `Setup`
- `Heal`
- `Support` (export support bundle)
- `Test` / `Full Test`
- capability mode menu (`Idiot` / `My Fault`)

## Known Remaining Work
1. Clean-machine dependency auto-install (OpenClaw/Ollama install flow).
2. CI pipeline for signed/notarized builds.
3. UI polish and guardrail mode messaging refinement.

## Build / Run
```bash
swift build
swift run
```

## Release
```bash
export DEVELOPER_ID_APP_CERT="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="junipero-notary"
./scripts/release-macos.sh
```

## Support Files
- User troubleshooting:
  - `USER_GUIDE.md`
- Release signing doc:
  - `RELEASE_SIGNING.md`
