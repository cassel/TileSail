---
title: Restore saved floating state within the same workspace
type: bugfix
created: 2026-10-07
status: done
route: oneshot
---

<frozen-after-approval>
## Intent

Correct startup restoration so a saved floating window regains its floating state even when discovery already placed it in the correct workspace. Restore saved tiled windows from floating discovery as well. Preserve the existing saved identity matching and monitor/profile constraints. Validate, commit the authorized local Grid changes alongside this correction, compile and reopen the installed Debug TileSail with matching CLI binaries and a recoverable backup.
</frozen-after-approval>

## Implementation Notes

- PersistentManualLayouts.swift gated both workspace and container restoration on a workspace mismatch; startup can discover a window as tiled in its saved workspace.
- Change only the container decision, with regressions for both directions and idempotence. Existing snapshots store floating identities, not absolute rectangles; this fix restores floating classification and does not invent historical geometry.
- User authorized committing, compiling and reopening in the latest message. Preserve Debug bundle ID and preference keys. No remote publishing.
- Verification: 519 Swift tests passed; signed Debug Xcode build succeeded; matching tilesail and aerospace CLI builds succeeded.

## Review Triage Log

- Independent blind review: no substantiated actionable findings. Confirmed discovery precedes placement restoration and both state transitions are covered. No review findings deferred.
- Live verification exposed explicit floating startup rules being overwritten by saved tiled classification (Numi). Patched successful startup layout commands to retain classification priority, including successful no-ops; clear transient overrides after placement restoration. Independent follow-up review found no actionable correctness findings.
- Final verification: 521 Swift tests passed and the signed Xcode Debug build succeeded. Local install and reopen use a ZIP backup, matching CLI binaries and the existing configuration argument.
