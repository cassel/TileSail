# TileSail recommended hardening — 2026-10-07

## Delivered

- Shared app/CLI endpoint at `/private/tmp/tilesail-<euid>/<bundle-id>.sock`.
  Directory creation uses mode0700; validation checks owner/type/mode through
  lstat and no-follow open/fstat. Socket checks reject files, symlinks and foreign
  owners without repairing or deleting untrusted objects. An active listener
  cannot be unlinked by a second startup. A closed owned socket can be removed
  after a bounded probe and inode recheck.
- A token preflight rejects grouping deeper than128 before recursive shell
  parsing. Quoted parentheses, sibling groups and existing syntax remain valid;
  eval parsing propagates the diagnostic with exit code2. No crash reproduction
  was attempted.
- Native migration stages a fresh app and both compatibility CLIs, verifies
  staged executable hashes against a prepared manifest, and archives originals
  with ditto before replacement. Different valid CLI signing identifiers are
  supported; executable consistency does not mean byte equality or publisher
  authenticity.
- Existing direct, Program/argv0 and open-form startup agents retain their label,
  format, config arguments and unrelated properties while paths are updated.
  Runtime no longer deletes the legacy plist and removes duplicate native login
  registration. Failed scanning still allows disabling the native service;
  enabled registration fails closed, and external authority is diagnosed.
- Migration validates path overlap and permissions, checks running manager
  processes before planning/applying and again before replacement, restores
  originals independently on failure, and retains a recovery mapping if restore
  is incomplete. Retained prepared backups use a non-app extension.
- Derived app unregistration is restricted to recognized build outputs. Preview
  makes no writes, rebuilds, activation or launchctl changes. Known old bundles
  are backed up as ZIPs; nested source checkouts are preserved.
- App/CLI consistency manifests are included with correct paths in release
  archives. CI runs repeatable migration, archive and cleanup fixtures.

## Verification

- Full Swift suite: **517 tests, zero failures**.
- Python filesystem/packaging/cleanup fixtures: **22 tests passed**.
- Final Xcode Debug app build: **BUILD SUCCEEDED**.
- Shell syntax checks and `git diff --check`: passed.
- Real built CLI `--version` with the private endpoint absent: local version and
  server Unknown, exit0; no connection to the running application.
- The four layout-file diffs present before this task match their saved initial
  snapshot exactly. Their pre-existing Grid hunks are excluded from the local commit; independent audit monitor-limit hunks are included.

Tests use owner-private temporary sockets, real temporary files/ditto archives,
parser domain fixtures and isolated Git checkouts. Process discovery and external
service decisions use bounded fixtures; no real app/service was killed or
started. Python tests cover exact canonical startup destinations, staged-input
changes, aliases/overlap, incompatible inputs, rollback/restore failures,
recovery retention, symlink metadata, legacy CLI copies and correct ZIP manifests.

## Review and remaining evidence

Three independent review lenses examined the changes: blind defects, edge cases,
and verification gaps. Findings and dispositions are recorded in
[the implementation spec](../../_bmad-output/implementation-artifacts/spec-recommended-hardening.md).
Confirmed hardening regressions and missing verification were corrected.

Three additional existing config-store concerns were recorded for a subsequent
config-focused change: save/retry after failed runtime reload, external writer
coordination during compare/replace, and loading a draft during an awaited save.
These were outside the endpoint/parser/installation recommendations implemented
here; see [the follow-up ledger](../../_bmad-output/implementation-artifacts/deferred-work.md).

Owner-private storage does not identify individual apps belonging to the same
UID. No different-UID runtime test, Accessibility/native desktop acceptance,
actual installation, launch-agent reload, sleep/reconnect/Stream Deck focus test,
or signed/notarized Release distribution was performed. The Debug build is
validation evidence, not an activated replacement of the user's running app.

To adopt the changes, prepare and review a release, suspend any KeepAlive job,
and upgrade app and all hand-copied CLI binaries together using the documented
migration workflow. A legacy CLI intentionally has no insecure socket fallback.
See [development.md](../development.md) and [SECURITY.md](../../SECURITY.md).

Local evidence: `/tmp/tilesail-hardening-final-swift-test.log`,
`/tmp/tilesail-hardening-python.log`, `/tmp/tilesail-hardening-final-xcode.log`.
