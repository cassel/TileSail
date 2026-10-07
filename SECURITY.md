# TileSail security model

TileSail controls other applications through macOS Accessibility permissions.
It runs as the signed-in user and is not a sandboxed security boundary between
processes belonging to that same user.

## Trusted inputs and exposed interfaces

- The TOML file is executable configuration: configured automation and hotkey
  callbacks can launch OS processes. Load configuration only from trusted files.
- The CLI uses a local Unix socket, with a versioned, length-prefixed JSON
  protocol. Frames in either direction are limited to 16 MiB. Truncated/closed
  streams terminate reads; this limit is per frame, not a total connection budget.
  Oversized command responses produce a small error response; transport failures
  close the connection rather than leaving clients waiting indefinitely.
- Visual application rules serialize workspace values into the internal command
  language. Delimiters in workspace names must remain data, not extra commands.
- The update checker reads GitHub release metadata over HTTPS and displays a
  release page. It does not download or install releases automatically.
- Build and release scripts run with the developer's permissions. Inspect their
  output before signing, installing, or publishing. Preserve quarantine checks;
  a local unsigned Debug build is not a notarized public distribution.

## Local IPC boundary

App and CLI share `/private/tmp/tilesail-<euid>/<bundle-id>.sock`. Before use,
the helper checks a real, UID-owned directory with mode 0700 using lstat,
no-follow open and fstat identity checks. Clients reject absent or unsafe socket
objects. Server startup uses a nonblocking local probe and refuses an active or uncertain
endpoint. Only absent or connection-refused sockets can be removed through the
checked directory descriptor after rechecking socket identity; files and symlinks survive failed validation unchanged.
There is no insecure legacy socket fallback, so upgrade app and CLI together.

Same-UID processes remain trusted. There is no peer-credential authentication,
and no different-UID runtime test was performed. Owner-private storage is not a
claim of verified cross-user runtime isolation. Permitted callbacks remain
executable configuration. Shell grouping is limited to 128 tokenized levels,
with quoted parentheses preserved as values. The frame and grouping limits do
not provide connection or total command budgets. Do not expose IPC through a
network bridge.

## Reporting

For a suspected vulnerability, provide the affected revision, a minimal isolated
reproduction, trust boundary, impact, and relevant source locations. Never attach
credentials, private TOML contents, window titles, or full desktop dumps to public
issues. The project does not currently document a private reporting channel;
arrange one with the maintainer before sharing sensitive exploit details.

See [the repository audit](dev-docs/audits/2026-10-07.md) for concrete findings,
validation evidence, and limits of the review.
