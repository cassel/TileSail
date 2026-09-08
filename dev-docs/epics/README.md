# TileSail product roadmap

This directory records the TileSail product roadmap. Report bugs and propose
improvements at https://github.com/cassel/TileSail/issues.

## Product principles

1. Settings are written in English and use native macOS interaction patterns.
2. Every non-obvious setting has contextual help available from an info button.
3. Layouts are deterministic per monitor and window count.
4. Custom layouts use the native tiling tree; they do not emulate tiling with
   floating windows.
5. A settings change must never create a refresh loop or move a workspace to a
   different monitor.
6. Existing configuration and stored layout profiles remain recoverable.

## Delivery order

| Epic | Outcome | Depends on | Status |
| --- | --- | --- | --- |
| [ASS-001](ASS-001-settings-experience.md) | English Settings and contextual help | — | Complete |
| [ASS-002](ASS-002-custom-layout-model.md) | Versioned custom-layout data model | ASS-001 | MVP complete |
| [ASS-003](ASS-003-custom-layout-editor.md) | Visual editor inside Settings | ASS-002 | MVP complete |
| [ASS-004](ASS-004-custom-layout-runtime.md) | Reliable runtime application | ASS-002 | MVP complete |
| [ASS-005](ASS-005-reliability-and-release.md) | Regression, migration and release safety | ASS-003, ASS-004 | In progress |

ASS-003 and ASS-004 can proceed in parallel after the model in ASS-002 is
stable. ASS-005 is the release gate.

## Definition of done

An epic is complete only when its acceptance criteria are automated where
possible, the full Swift test suite and lint pass, accessibility labels exist,
and the installed application has been smoke-tested with one running instance.
