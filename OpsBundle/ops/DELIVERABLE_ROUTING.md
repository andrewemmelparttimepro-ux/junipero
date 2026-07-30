# DELIVERABLE_ROUTING.md

## Purpose
Define where Thrawn 2.0 outputs live so reviewable work stays easy to inspect.

## Ticketed deliverables
- Manifest: `workspace/deliverables/manifest.json`
- Primary format: HTML
- Filesystem pattern: `workspace/deliverables/<ticket-id>/<yyyy-mm-dd>/<slug>/index.html`
- Supporting assets: `workspace/deliverables/<ticket-id>/<yyyy-mm-dd>/<slug>/assets/`

The Deliverables tab reads the manifest. Markdown, JSON, logs, screenshots, and raw folders may support a deliverable, but the user-facing handoff is the HTML `index.html`.

## Completion rule
A task is not complete until the output is reviewed and the Deliverable field points to the human-readable HTML `index.html` when an artifact exists.
