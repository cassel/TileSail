# Development Notes

## TileSail maintainer entry point

This root checkout builds TileSail. Start with [README.md](../README.md) for the
current Swift/Xcode commands, [architecture.md](architecture.md) for ownership
and execution flow, and [SECURITY.md](../SECURITY.md) for trust boundaries.
The notes below are retained upstream background; historical AeroSpace names
are not current install locations or release branding.

Run `swift test`, then build the Xcode `AeroSpace` scheme to produce
`TileSail.app`. The Debug bundle ID remains `bobko.aerospace.debug`; Release is
`us.cassel.tilesail`. Do not launch a second window manager during validation.
Builds and unit tests do not require installing the result.

For cleanup, preview `bash script/clean-project.sh --dry-run` before removing
generated outputs. Xcode regeneration and native installation are separate
operations. Follow [Safe native installation](#safe-native-installation) for the
current app/CLI/startup migration workflow; [the audit](audits/2026-10-07.md) records
its evidence and live acceptance limits.

To build/install from sources do the following:
1. Install dependencies
2. Create codesign certificate in `Keychain Access.app`
3. Run one of the entry point scripts to build/install from sources

If you struggle to build AeroSpace locally, you can also refer to [builds in GitHub Actions](https://github.com/nikitabobko/AeroSpace/actions?query=branch%3Amain)

## Definitions

**SPM.** Swift package manager and Swift build tool. In other words, `swift` CLI tool

## 1. Install dependencies

1.  Install Xcode from App Store https://apps.apple.com/us/app/xcode/id497799835
2.  Install [swiftly](https://github.com/swiftlang/swiftly).
    Swiftly is a Swift toolchain manager that will make sure that you use the same swift version as written in `.swift-version` file.
    `brew install swiftly`
3.  If you want to build shell completion, install rust, bash and fish
    -   Install Rust using rustup. https://www.rust-lang.org/tools/install
    -   `brew install bash fish`
4.  If you want to build man pages, install Ruby >= 3.0. I recommend using [rbenv](https://github.com/rbenv/rbenv).
    -   `rbenv install 3.3.4` (or whatever 3.x version)
    -   Install asciidoctor using Ruby `bundler`. `cd AeroSpace && bundler install`
5.  Install optional `xcbeautify` to make Xcode build logs readable. `brew install xcbeautify`

## 2. Create codesign certificate

If you want to run AeroSpace as App Bundle (AeroSpace.app) you need to create self-signed certificate that will be used to codesign AeroSpace.
Release artifact is built as App Bundle.
If you only plan to build the debug version of AeroSpace, you can run it from the terminal and custom certificate is not required.

1.  Open `Keychain Access.app`
2.  Menu -> `Keychain Access` -> `Certificate Assistance` -> `Create a Certificate...`
    -   Name: `aerospace-codesign-certificate`
    -   Identity Type: `Self-Signed Root`
    -   Certificate Type: `Code Signing`

## 3. Entry point scripts

**Debug build**
-   `build-debug.sh` - Build debug build to `.debug` dir by using SPM. (Xcode is not involved)
-   `test.sh` - Run tests.
-   `swiftformat.sh` - Format the code.
-   `run-debug.sh` - Run AeroSpace.app debug build.
-   `run-cli.sh` - Run `aerospace` in CLI. Arguments are forwarded to `aerospace` binary.
-   `build-docs.sh` - Build the site and man pages to `.site` and `.man` dirs respectively.
-   `build-shell-completion.sh` - Build shell completion to `.shell-completion`.
    You can test that the completion works properly by sourcing the file `source ./.shell-completion/zsh/_aerospace`
-   `generate.sh` - Regenerate generated project files. `xcode/AeroSpace.xcodeproj` is generated, and some of the source files
    (the source files have `Generated` suffix in their names).

**Release build**
-   `build-release.sh` - Build release build to `.release` dir by using Xcode.
-   `install-from-sources.sh` - Build a prepared release and migrate the app, matching CLIs and recognized startup path transactionally.
    This script is "work in progress".
    Use it on your own risk.

## IDE

-   You can obviously [open the project in Xcode](#xcode).
-   You can use your editor of choice (Neovim, Vim, Emacs, Sublime, VS Code) by using [sourcekit-lsp LSP](https://github.com/apple/sourcekit-lsp).
    I only tested it in Neovim
-   AppCode. The initial codebase was written in AppCode and the IDE was pretty solid.
    But AppCode was unfortunately sunsetted, and it started falling apart.
    Last time I checked it, it didn't support Swift 5.9 features, and I couldn't make it reliably import the project.
    RIP

## Xcode

Even if you use LSP and another text editor, Xcode is still useful to attach debugger (though you can use `lldb` in CLI).

1.  To open the project in Xcode: File -> Open -> Choose `Package.swift` file instead of `xcode/AeroSpace.xcodeproj`.
    It's better to open `Package.swift`, because SPM project is more lightweight.
    `xcode/AeroSpace.xcodeproj` is only used in `*release*.sh` build scripts.
2.  After you opened the project in Xcode.
    Edit Scheme... -> Options -> Console -> Choose `Terminal`.
    This way Accessibility permission will be requested from Terminal.
    If you don't change Console to `Terminal`, Accessibility permission will be requested on every rebuild, because the debug binary is unsigned.

## Tips

- Use built-in "Accessibility Inspector.app" to inspect accessibility properties of windows
- Use [DeskPad](https://github.com/Stengo/DeskPad) or [BetterDisplay 2](https://github.com/waydabber/BetterDisplay) to emulate several monitors
- You can use `script/clean-project.sh` to clean the project when something goes wrong.


## Safe native installation

Stop TileSail/AeroSpace/AeroSpaceSmooth manually before installation. If an
external startup job uses KeepAlive, suspend that job manually first so it cannot
restart the manager during staging or replacement. After migration, manually
reload the updated job when ready to start the installed app. The installer
never calls launchctl, reloads jobs or activates apps. Prepare a
release with `build-release.sh` (which records app/CLI executable SHA-256 consistency in
`.release/install-manifest.json`; this checks executable consistency, not full
bundle authenticity or signer identity), then preview `./install-from-sources.sh --dry-run`.
Preview does not rebuild, write files, launch apps or reload jobs. The copied stage is rechecked against the manifest captured during planning
before any replacement. Each executable has its own hash; compatible CLI builds
may differ in Mach-O or signing identifiers. Apply a prepared
release with `./install-from-sources.sh --dont-rebuild` after reviewing the plan.

The migration installs a fresh `~/Applications/TileSail.app`, both `tilesail` and
`aerospace` into `~/.local/bin`, and updates the existing compatibility directory
`~/.config/aerospace/bin` when present. Add the canonical directory to PATH.
Update any additional hand-copied CLI binaries from the same release; legacy
clients cannot use the new private socket path. Named previous manager bundles
in user and system Applications are archived as ZIPs under `.backups` before
replacement. App staging and archives use ditto to retain macOS metadata.
System-owned replacements require filesystem permission; failures abort or
restore originals independently and retain recovery archives. If restoration is
incomplete, the error identifies the preserved staging directory and its
`recovery.json` mapping so remaining originals can be recovered manually. Any
uninstalled prepared app retained there uses a non-`.app` extension. Fixtures
verify stage mutation rejection, independent restoration, and retained recovery.

One recognized direct-executable or `/usr/bin/open -a` LaunchAgent is updated
atomically, preserving label, plist format, config arguments and other properties.
Ambiguous, malformed or unrecognized managed jobs fail closed. No job is launched
or reloaded. Runtime startup preserves an external agent and unregisters duplicate
SMAppService registration. Known derived build products are unregistered after a
successful apply; a tool failure explicitly reports that installation succeeded
but registration cleanup remains incomplete.

Fixture tests use explicit `--release`, `--applications`, `--system-applications`,
`--cli`, `--compatibility-cli`, `--agents`, `--backups` and `--project` paths,
without changing HOME. `python3 -m unittest discover -s script/tests -v` covers
planning preservation, startup forms, compatibility CLIs, symlink bundle copies,
unsafe paths, active-manager rejection and rollback after injected failures.
No real desktop installation, launchctl activation, different-UID connection,
Accessibility acceptance or signed Release distribution is established by these
fixtures or a Debug build.
