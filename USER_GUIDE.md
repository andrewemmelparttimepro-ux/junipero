# Junipero User Guide: Setup + Troubleshooting

## What Junipero Does
Junipero is a Mac app that opens a chat UI and manages your local AI runtime (OpenClaw, with optional Ollama fallback) so you do not need terminal commands.

## Normal Install Flow
1. Download `Junipero.dmg`.
2. Open it and drag `Junipero.app` to `Applications`.
3. Open `Junipero.app`.
4. If first launch, complete setup:
   - `Free Local` for local-first usage.
   - `Bring Your Own Plan` if you want your own paid provider/model.
5. Start chatting.

## Common Problems and Fixes

### 1) "Junipero can’t be opened" or macOS security warning
Cause:
- App is not signed/notarized for your machine.

Fix:
1. In Finder, right-click `Junipero.app` and choose `Open`.
2. Click `Open` again in the prompt.
3. If blocked: System Settings > Privacy & Security > allow app launch.

Long-term product fix:
- Ship Developer ID signed + Apple notarized builds.

### 2) Setup opens again even though I used the app before
Cause:
- Setup state file missing/reset, or config migration detected an invalid config and forced recovery.

Fix:
1. Open setup and click `Set Up Now` again.
2. If using provider mode, re-enter token (stored in macOS Keychain).
3. Run `Full Test` in app header to verify all checks pass.

### 3) "Runtime recovering" or status is red/yellow
Cause:
- OpenClaw or Ollama is not healthy.

Fix:
1. Click `Heal` in the top bar.
2. Open `Setup` and click `Run Diagnostics`.
3. If fallback model missing, click `Fix Missing Model`.

### 4) Chat fails with overload/rate-limit errors
Cause:
- Provider is overloaded or rate-limited.

Fix:
1. Wait 15-60 seconds and retry.
2. Keep Ollama fallback enabled.
3. Use `Free Local` mode during provider outages.

### 5) I can’t copy message text
Fix:
1. Drag-select text directly in a chat bubble.
2. Click the clipboard icon on the bubble.
3. Right-click bubble and choose `Copy`.

### 6) I need help sending logs to support
Fix:
1. Click `Support` in app header.
2. A zip file is exported to your Desktop.
3. Send that zip to support.

## What "Full Test" Checks
- OpenClaw CLI availability
- Gateway health
- Local read/write storage
- Ollama availability (if enabled)
- Fallback model presence

It reports pass/fail summary in the app status text.

## Security Notes
- Provider token is stored in macOS Keychain (not plain text config).
- Config file is kept under `~/.junipero/config.json`.
- Support bundle export redacts token fields.

## Current Distribution Limits (and How We Fix Them)

### Problem A: Signing/Notarization
Current risk:
- Some users may see Gatekeeper warnings or launch blocks.

Engineering fix plan:
1. Sign app with Apple Developer ID certificate.
2. Notarize app with `notarytool`.
3. Staple notarization ticket to app/DMG.
4. Verify on clean macOS account before release.

Release check:
- Fresh machine can open app without security workarounds.

### Problem B: Missing Dependency Auto-Install
Current risk:
- If OpenClaw/Ollama are not already installed, setup may fail for non-technical users.

Engineering fix plan:
1. During setup, detect missing binaries.
2. Offer one-click install flow for dependencies.
3. Re-run health checks after install.
4. Show clear progress and failure reasons in plain language.

Release check:
- Clean machine with no OpenClaw/Ollama still reaches successful chat from setup.

## Team Ship Checklist (Before Public Distribution)
1. Signed + notarized DMG build.
2. Dependency auto-install from clean machine.
3. First-run setup succeeds with no terminal.
4. `Heal`, `Run Diagnostics`, `Fix Missing Model`, `Full Test`, and `Support` all verified.
5. Recovery path tested with intentionally corrupted config.
