# Thrawn Agent Gateway Cohesion — Design QA

## Comparison target

- Source visual truth:
  - `/var/folders/7y/fdzx9ksn0yl0wwy2hpz5_dqh0000gn/T/TemporaryItems/NSIRD_screencaptureui_TGDzdV/Screenshot 2026-07-29 at 10.23.16 PM.png`
  - `/var/folders/7y/fdzx9ksn0yl0wwy2hpz5_dqh0000gn/T/TemporaryItems/NSIRD_screencaptureui_c6ChOY/Screenshot 2026-07-29 at 10.23.31 PM.png`
- Rendered implementation:
  - `artifacts/design-qa/agent-gateway-synchronized-thread-final.jpeg`
  - `artifacts/design-qa/agent-gateway-synchronized-stable-final.jpeg`
- Combined comparison evidence:
  - `artifacts/design-qa/comparison-thread-header-source-over-implementation.jpg`
  - `artifacts/design-qa/comparison-stable-source-over-implementation.jpg`
- Source pixels: thread 1476 × 462; stable 1390 × 742.
- Implementation pixels: 1298 × 768 native macOS window.
- Native viewport: installed `/Applications/Thrawn.app` at 1298 × 768.
- Density normalization:
  - Thread header source crop 1338 × 79 was downsampled to the implementation crop at 588 × 36.
  - Stable source crop 1313 × 701 was downsampled to the implementation dossier width of 579 pixels; the implementation crop remained native at 579 × 280.
- State: Thrawn selected on Claude, Claude Max ready, stable dossier visible, left rail visible, and Command thread containing a completed live Claude response.

## Full-view comparison evidence

The installed app retains the established Thrawn/NDAI shell, agent portraits, typography, spacing, color tokens, dossier geometry, project tabs, and utility rail. The active gateway now appears as the same value in the global Thrawn header, left provider card, every left-rail agent card, stable account profile, stable dossier, stable roster tile, specialist chat header, and Command thread header. Steven remains a non-interactive Grok exception.

## Focused comparison evidence

- The thread comparison shows the intentional addition of `THRAWN · CLAUDE` between the unchanged Thread title and date/close controls. It preserves the blue header height and original alignment without crowding the close control.
- The stable comparison shows the dossier composition is materially unchanged. `GATEWAY` remains the field label and `CLAUDE` remains the large selected value, now backed by the shared picker.
- A separate focused crop was not required for the left rail because the final native full-view capture clearly resolves every agent name and gateway chip at 1:1 scale.

## Required fidelity surfaces

- Fonts and typography: passed. Existing rounded display faces, monospaced micro-labels, system body text, weights, tracking, hierarchy, and truncation behavior are preserved.
- Spacing and layout rhythm: passed. New controls fit the existing header, dossier, tile, and rail slots without overflow, overlap, card growth, or hidden actions.
- Colors and visual tokens: passed. The controls reuse Chiss blue, obsidian, white-opacity, green-ready, and orange-locked treatments already present in the app.
- Image quality and asset fidelity: passed. Existing portraits, logos, and SF Symbols remain native and sharp. No visible asset was replaced or approximated.
- Copy and content: passed. The selected brain is explicit (`OPENAI`, `GROK`, or `CLAUDE`), the agent name stays primary, and help text explains that identity and local conversation persist.

## Interaction and runtime verification

- Changed Thrawn from Claude to OpenAI using the left-rail picker. The top header, provider card, left rail, account profile, and stable dossier all updated to OpenAI immediately.
- Changed Thrawn from OpenAI back to Claude using the stable dossier picker. All representations updated to Claude immediately.
- Opened the existing Command thread. Its header displayed `THRAWN · CLAUDE`.
- Sent `For routing verification, reply exactly: THRAWN CONTINUITY OK` from that existing thread. The installed app returned `THRAWN CONTINUITY OK`.
- Persisted thread evidence recorded `lastProvider = claude` and `modelUsed = claude-opus-5`.
- The Claude provider log contained the bounded identity-continuity handoff with the earlier Codex transcript before the current message.
- The standalone signed-in Claude create-and-resume integration test passed.
- The full Swift test suite passed: 10 tests, 0 failures, with the three opt-in live provider suites skipped in the ordinary run.
- Native app remained responsive with no crash or visible runtime error. Browser-console checks are not applicable to this SwiftUI surface.

## Comparison history

1. Initial implementation pass found two P2 label defects caused by macOS `Menu` rendering:
   - The dossier showed only `GATEWAY`, hiding the selected provider value.
   - The thread header showed only `THRAWN`, hiding the selected provider value.
2. Fix:
   - Moved the dossier field label outside the menu and made the menu's primary text the provider value.
   - Collapsed the thread identity and provider into one explicit menu label: `THRAWN · CLAUDE`.
3. Post-fix evidence:
   - `artifacts/design-qa/agent-gateway-synchronized-stable-final.jpeg`
   - `artifacts/design-qa/agent-gateway-synchronized-thread-final.jpeg`
   - Both combined comparison images listed above.

## Findings

No actionable P0, P1, or P2 issues remain.

## Follow-up polish

- None required for this feature.

## Implementation checklist

- [x] One persisted gateway route per agent.
- [x] Every relevant agent representation reads and writes that route.
- [x] Command threads and specialist chats execute through the selected route.
- [x] Voice-to-Command inherits the same ThreadStore route.
- [x] Cross-provider handoff preserves bounded local transcript context.
- [x] Provider-specific sessions remain resumable when switching back.
- [x] Steven remains locked to Grok.
- [x] Signed and installed app visually and functionally verified.

final result: passed
