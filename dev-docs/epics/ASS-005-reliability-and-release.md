# ASS-005 — Reliability, migration and release

## Goal

Ship the custom editor without repeating the loops, duplicate instances or
unexpected monitor moves found during early TileSail development.

## Scope

- End-to-end scenarios for the MacBook, LG Ultra and vertical LG profiles.
- Stress tests for rapid open/close, workspace changes and command repetition.
- Schema migration backups and a one-click profile reset.
- Diagnostics that identify the selected monitor, count, style, blueprint
  revision and reconciliation reason.
- A single-instance startup and installation smoke test.
- User documentation for presets, custom editing and recovery.

## Release gates

- Full test suite and lint pass.
- No refresh loop in a 30-minute stress run.
- Exactly one installed process uses the expected TOML configuration.
- Existing monitor assignments and shortcuts survive upgrade and rollback.
- The previous app bundle and stored profile data are recoverable.

