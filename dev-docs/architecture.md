# TileSail architecture and repository map

The repository root is the canonical TileSail checkout. Internal AeroSpace names
remain where they support upstream history, CLI/config compatibility, and Xcode
integration; they do not designate a second product. See [TILESAIL.md](../TILESAIL.md)
for user-facing behavior and [AGENTS.md](../AGENTS.md) for development constraints.

## Module boundaries

| Location | Responsibility | Change with |
| --- | --- | --- |
| `Sources/AeroSpaceApp/`, `xcode/` | SPM and Xcode entry points | App lifecycle and packaging |
| `Sources/AppBundle/initAppBundle.swift` | Startup, permissions, config, observers, IPC, restoration | Startup integration |
| `Sources/Common/` | CLI argument models/parsers, metadata, shared IPC protocol/utilities | Client/server compatibility |
| `Sources/Cli/` | CLI entry point, stdin/env, server requests and subscriptions | Command-line behavior |
| `Sources/AppBundle/command/` | Command parsing, target resolution, command execution | Matching Common parser and docs |
| `Sources/AppBundle/shell/` | Internal command language, lexer, parser, execution | Config command semantics; this is distinct from an OS shell |
| `Sources/AppBundle/config/` | TOML parsing/watching, hotkeys, visual drafts and saves, login settings | Config compatibility and round-trip tests |
| `Sources/AppBundle/tree/`, `model/` | Window/workspace tree, monitor identity, geometry, AX-backed models | Tree invariants and monitor tests |
| `Sources/AppBundle/layout/` | Layout selection, custom trees, animation, manual layouts, app workspace memory | Runtime and geometry regressions |
| `Sources/AppBundle/focus*.swift`, `GlobalObserver.swift`, `mouse/` | Focus cache, OS events, dragging, resizing | Event-order and live desktop validation |
| `Sources/AppBundle/ui/` | SwiftUI Settings, menu bar, workspace bar, overview/palette | Model tests plus real UI review |
| `Sources/AppBundle/util/`, `Sources/PrivateApi/` | Accessibility/thread helpers and private AX bridge | Platform integration |
| `Sources/AppBundle/UpdateChecker.swift`, `WindowManagerConflictDetector.swift` | Release checks and competing-app detection | Service decoding and startup tests |
| `Sources/AppBundleTests/` | XCTest fixtures and regression coverage | `swift test` |
| `resources/`, `xcode/` | Icons, bundled default TOML, generated Xcode project and source template | Both `xcode/project.yml` and generated project |
| `grammar/`, `docs/` | CLI grammar, generated help/completions, upstream command documentation | `generate.sh` and generation diff |
| `dev-docs/`, `TILESAIL.md` | Maintainer architecture and fork feature guide | Keep current with implementation |
| `script/`, root `*.sh`, `.github/` | Build, cleanup, release preparation, CI | Isolated shell fixtures and app build |
| `legal/`, `LICENSE.txt`, `NOTICE.md` | MIT license and upstream attribution | Preserve notices/history |
| `_bmad/`, `.agents/`, `.claude/` | Local development workflow support | Keep separate from shipping source |

## Execution flow

1. The app initializes configuration and waits for Accessibility permission.
2. The Unix listener accepts CLI requests. Common framing carries JSON with a
   protocol-version handshake; both client and server parse command arguments.
3. Command execution enters the serialized refresh/session machinery and updates
   the window/workspace tree. OS Accessibility and display events use this same
   model through observers and per-app run loops.
4. Automatic layouts select a profile using monitor hardware identity and window
   count. Geometry, Dock/workspace-bar reservations, and animation determine AX
   frame updates. Focus/visibility handling must avoid event feedback loops.
5. Manual trees and app workspace memory persist selected state through defaults.
   Visual Settings patch the active TOML while preserving unrelated text and
   validate it before save/reload. A stale on-disk file causes save to fail.

## Compatibility invariants

- App/product/executable: `TileSail`; Debug bundle ID: `bobko.aerospace.debug`;
  Release: `us.cassel.tilesail`.
- `tilesail` and compatibility `aerospace` CLI products share the same protocol.
  Xcode project/scheme names remain `AeroSpace`.
- Preserve `AeroSpaceSmooth.*` preferences, AeroSpace TOML paths, old command
  semantics, MIT notices, and the complete Git history.
- Display names are labels; hardware `stableIdentifier` is the profile/group key.
- Installation must leave one active window manager. Backups belong under
  `.backups/` as ZIPs or with a non-`.app` extension.

## Local-only content and cleanup

`AeroSpaceSmooth/`, when present in this workspace, is an independent nested Git
checkout, not the source directory for this app. It was not moved or deleted.
`.local/`, `.backups/`, and development tooling can contain irreplaceable local
work. Do not run repository-wide double-force Git cleanup.

`bash script/clean-project.sh --dry-run` previews removal of an explicit allowlist
of ignored build outputs. Running it without the flag removes only those outputs;
it does not regenerate Xcode files or remove local tooling/source checkouts.
Use `generate.sh` deliberately when generated source/project changes are needed.

## Validation and review boundaries

Run `swift test` and the Xcode app build described in [README.md](../README.md).
Unit tests cover parsers, models, geometry, and isolated socket framing. They do
not establish live multi-monitor focus stability, permission behavior, wake/sleep,
installation, signing, notarization, or public release readiness. Those require
separate evidence. See [SECURITY.md](../SECURITY.md) and the
[2026-10-07 audit](audits/2026-10-07.md) for reviewed boundaries and remaining work.
