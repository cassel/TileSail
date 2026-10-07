---
title: 'Apply the remaining TileSail audit recommendations'
type: 'bugfix'
created: '2026-10-07'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '90a52bbe77a997630947a29804b5d398179eb304'
context:
  - '{project-root}/AGENTS.md'
---

<frozen-after-approval reason="User requested the previously recommended corrections in this chat">

## Intent

**Problem:** The ECC audit leaves the local socket without owner-private endpoint
storage, the command parser without a nesting bound, and native installation
without a safe app/CLI/startup migration. Apply these recommendations to the
source and verify them locally.

**Approach:** Create shared checked socket endpoints, reject excessive grouping
before recursive parsing, and replace overlay installation with a reversible,
fixture-tested migration. Update documentation with actual evidence.

## Boundaries & Constraints

**Always:** Preserve existing local Grid changes and prior audit fixes; keep
TileSail branding, Debug/Release IDs, legacy TOML and preference keys. Retain
upstream history/notices. Archive replaced bundles as ZIPs under `.backups`.
Keep app and CLI compatible by installing both from the same prepared release.
Preserve startup agent label, config arguments and other properties.

**Never:** Install/activate on the real desktop during this task; terminate real
processes, reload launchctl jobs, contact the running app, change account
credentials, reproduce stack exhaustion, publish, or delete nested checkouts.
No insecure legacy socket fallback or claimed different-UID runtime proof.

## I/O & Edge-Case Matrix

| Scenario | State | Expected behavior | Error handling |
| --- | --- | --- | --- |
| IPC normal | Private directory absent or owned 0700 | Server creates/validates it, clients use short UID/bundle-ID path | Clear operational failure on filesystem error |
| IPC unsafe | Directory wrong type/mode/owner or symlink; socket non-socket/symlink | Reject without repairing or deleting untrusted targets | Fail closed |
| IPC stale | Own real socket in checked directory | Server removes only that stale endpoint | Ownership/type check before unlink |
| Parser boundary | 128 versus 129 nested groups | Accept128, reject129 before descent; normal quoting unaffected | Location diagnostic/code2 propagated by eval parsing |
| Install normal | Stopped manager, valid release app and both CLIs, known old bundles | Stage fresh app, archive previous app/CLI, replace without overlay | Preserve archives for recovery |
| Startup | One known direct-executable or open-form plist | Rewrite only recognized app/executable path; preserve config/options/format | Reject malformed/ambiguous or multiple managed agents |
| Install failure | Archive/staging/plist/copy failures; running manager | Abort or rollback prior app/CLI/plist; never kill | Actionable error, no silent success |
| Install preview | --dry-run | Describe plan, zero writes/activation | No rebuild side effect |
| Derived registration | Known built app under project build roots | Unregister only derived products after successful install | Report tool failures |

</frozen-after-approval>

## Code Map

- `Sources/Common/util/commonUtil.swift`: public socketPath currently globally in /tmp.
- `Sources/Common/util/SocketEndpoint.swift` (new): shared endpoint directory and object checks.
- `Sources/AppBundle/server.swift`: start listener and Debug-to-Release connection path.
- `Sources/Cli/_main.swift`: normal/version connection constructors.
- `Sources/AppBundle/shell/shellParser.swift`: recursive entry and grouping branch.
- `Sources/AppBundleTests/shell/ShellParserTest.swift`: preserve added quoting regressions.
- `install-from-sources.sh`: currently ditto overlay, no CLI/startup migration.
- `script/install-migration.py` (new): testable stdlib migration engine and planning CLI.
- `Sources/AppBundle/config/startAtLogin.swift`: currently deletes bobko plist; replace with non-destructive detection.
- `Sources/AppBundleTests/SocketEndpointTest.swift`, startup detector tests and `script/tests/` (new): isolated fixtures only.

## Tasks & Acceptance

**Execution:**
- [x] Shared socket helper: use `/private/tmp/tilesail-<euid>/<bundle-id>.sock`; mkdir0700, lstat/open(no-follow)/fstat validate ownership/type/mode/inode. Validate existing client endpoint. Remove stale socket using checked dirfd/type/owner. Route server, CLI and debug toggle through helper, clear failures. No peer-credential API claim; same-UID processes remain trusted.
- [x] Parser: token preflight maximum grouping128; sibling depths reset; ignore parentheses inside word tokens. Test boundary, quoting/comments, existing malformed diagnostics and command failure propagation.
- [x] Installer: inventory named TileSail/AeroSpace/AeroSpaceSmooth bundles in user/system Applications; reject running manager, ambiguous agents and unsafe paths. Stage exact fresh bundle and matching release CLIs; back up all replacements before mutation; rollback application/CLI/plist on failure. Support explicit fixture directories without repurposing HOME.
- [x] Startup: preserve direct and `/usr/bin/open -a` launch forms; update one existing agent atomically. Runtime must preserve recognized external startup agents and avoid duplicate SMAppService registration. Do not launch/reload jobs here.
- [x] Derived build registration: inventory recognized products under .release/.debug/.build/xcode/xcode/.xcode-build, unregister only these after successful apply, report failures.
- [x] Verification/docs: meaningful filesystem/network/parser/install/startup tests; Swift full suite/Xcode build; document joint app/CLI upgrade, safe install workflow and remaining live acceptance limits.

**Acceptance Criteria:**
- Given an unsafe endpoint object, when server or client validates, then validation fails and the object survives unchanged.
- Given a parser boundary input, when parsing, then a bounded diagnostic replaces recursion beyond128 without changing literal quoted values.
- Given an existing managed startup config, when fixture migration succeeds, then all non-path arguments/properties remain identical and one canonical app plus compatible CLI remains.
- Given dry-run, active processes or injected migration failure, when planning/applying, then no real desktop changes occur and fixtures verify preservation/rollback.

## Implementation Notes

User's latest instruction authorizes correcting all recommendations; the dirty
tree contains known earlier-session changes and user Grid work. Preserve it,
with the initial diff snapshot at `/tmp/tilesail-before-recommended-fixes.diff`.
Implementation is sequential in one context; investigator summaries are distilled
above. Do not run shared Swift tests concurrently. Add no speculative timeouts or
connection budgets until subscription semantics are specified.

## Spec Change Log

## Review Triage Log

| Review finding | Verdict | Evidence and route |
| --- | --- | --- |
| Blind 1: baseline after failed config reload | medium | Existing save code predates this hardening task; file write succeeds but baseline remains older, retry asks reload. Defer with reproducible save/retry test proposal. |
| Blind 2: external TOML writer check/rename race | medium | Existing comparison does not implement cooperative locking, explicitly documented in first audit. Defer; coordinate writers before claiming an atomic compare-and-swap. |
| Blind 3: load during awaited save | medium | Existing UI load can change baseline during await; pre-existing in this task. Defer; generation or disabled load guard needs config-store regression. |
| Blind 4: rollback stops on restore failure | high | apply catches mutation failure then restoration loop itself can throw, stopping recovery. Patch restoration independently and retain staging on incomplete recovery. |
| Blind 5: prepared release changes before staging | medium | Plan checks manifest but copied staging is not validated against planned hashes. Patch validation of copied inputs before destructive phase. |
| Blind 6: manifest does not cover all resources | false | New manifest binds the three executable inputs, not publisher authenticity or all resources. Narrow documentation to executable consistency; include manifest in archive. Full signing/release certification is not claimed. |
| Blind 7: unrelated textual mentions treated as managed job | medium | rewrite scans all dictionary values for product strings. Patch classification to executable/known startup identity; preserve unrelated log/env references. |
| Blind 8: equivalent Program and argv0 rejected | medium | Both legitimate matching paths populate matches, causing false ambiguity. Patch equivalent pair handling and exact destination tests. |
| Blind 9: disabled startup blocked by malformed unrelated plist | medium | Inspection catch returns before service unregister. Patch disabled handling to always unregister, retain fail-closed registration behavior. |
| Blind 10: plist presence not proof of active startup | medium | External jobs are intentionally managed outside SMAppService; presence suppresses registration even disabled/unloaded. Preserve external authority, add actionable diagnostic and document file-presence policy rather than asserting active job. |
| Blind 11: active own socket removed | medium | Owned type alone establishes identity but not staleness; user can choose Run Anyway in app conflict alert. Patch refusal of a live endpoint, with isolated normal listener fixture. |
| Edge 1: permission failure interrupts rollback | high | Same mutation/restore exception path as Blind4; include permission fault fixture and independent restoration. |
| Edge 2: identical Applications roots duplicate replacements | medium | Inventory appends same Path twice then deletes twice. Patch deduplication; valid normalized fixture roots demonstrate the state. |
| Edge 3: CLI inside replaced bundle | medium | Existing overlap checks exclude old replacement ancestors. Patch reject destination/CLI/startup overlaps with replaced app bundles before mutation. |
| Edge 4: malformed plist prevents disable | medium | Same disabled-action issue as Blind9; test injected failed external-agent scan. |
| Verification 1: startup destination not asserted | medium | Existing tests skip changed path indexes; extend assertions for direct, open and Program forms. Patch. |
| Verification 2: migration fixtures absent from CI | medium | build.yml has only Swift/Xcode/CLI. Add Python fixture command. Patch. |
| Verification 3: cleanup protection only one-time fixture | medium | No persisted cleanup fixture before this task; persist real script temporary-Git test in Python CI. Patch. |

## Verification

- `swift test`: all existing/new registered tests pass, sockets isolated.
- `xcodebuild -project xcode/AeroSpace.xcodeproj -scheme AeroSpace -configuration Debug -derivedDataPath .build/audit-xcode CODE_SIGNING_ALLOWED=NO build`: success.
- `python3 -m unittest discover -s script/tests -v`: installer fixture matrix passes.
- `bash -n install-from-sources.sh`; `git diff --check`: success.

Review patch scope preserves the frozen intent: verified endpoint staleness, staged executable consistency, independent recovery, precise startup-path handling and repeatable verification. Existing unrelated config-store concurrency findings are recorded separately for follow-up.


Verified review patches (focused installer fixtures): copied executable staging
is validated against the separate per-artifact hashes captured during planning;
different CLI binary/signing identities are accepted when their trusted prepared
manifest matches. Restoration continues independently after an error; incomplete
recovery retains original copies, ZIP archives and an explicit recovery mapping,
with any uninstalled prepared app renamed to a non-`.app` extension. The process
guard recognizes SPM `AeroSpaceApp` without treating it as an installed bundle.
The exact known legacy startup label `com.cassel.aerospace-smooth` fails closed
for an unrecognized launch form, while unrelated textual product mentions survive.

- `python3 -m unittest discover -s script/tests -p test_install_migration.py -v`:
  18 installer tests passed after these patches. Full verification remains the
  parent run's responsibility; no desktop migration or activation was performed.

## Final verification and review corrections

Full Swift: 517 passed; Xcode Debug final build succeeded. Python fixtures: 22 passed. CLI offline version passed without
contacting the installed app; shell syntax/diff checks passed. Four pre-task
layout diffs remained byte-for-byte identical and their Grid hunks are excluded from the commit; independent earlier audit hunks are staged separately.

All retained in-scope patch rows were resolved and tested. Existing config-store
concerns in Blind1–3 were recorded in deferred-work.md. Native activation,
cross-user runtime testing and signing/notarization remain unperformed.

Additional root review patches: each prepared CLI uses its own manifest hash
rather than byte equality (actual same-source products have distinct Mach-O
identifiers); AeroSpaceApp is recognized as a running manager without expanding
bundle inventory; retained recovery bundles use a non-app extension; packaged
manifest keys match bin/CLI archive paths; process discovery is rechecked after
staging before mutations so KeepAlive restarts cannot be missed during preparation.

Root review also rejects existing regular files passed as directory roots (including compatibility CLI roots) before planning can mutate anything; the preservation fixture passed.
