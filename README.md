# TileSail

<img src="./resources/Assets.xcassets/AppIcon.appiconset/icon.png" width="40%" align="right">

TileSail is an independent macOS window manager derived from
[nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace) focused on a
friendlier, more visual macOS tiling experience. It keeps AeroSpace's tree,
workspaces, CLI, and TOML configuration while adding smooth coordinated window
movement and a native Settings interface.

> TileSail was previously developed as AeroSpaceSmooth. It is maintained independently
> by **C. Cassel** and is not an official AeroSpace release.

## Features

- A native menu-bar **Settings…** window, written in SwiftUI.
- Visual editing for General, Workspaces, Applications, Automation, Shortcuts,
  and the active TOML file, including an app picker for Floating/Tiled defaults.
- Per-monitor automatic layout profiles for every window count from 1 through 10.
- Fullscreen, Dwindle, Vertical Pairs, Grid, Columns, Rows, and Custom layouts.
- Monitor previews that use the connected display's real aspect ratio and resolution.
- A direct-manipulation Custom editor with draggable dividers, exact proportions,
  presets, Hybrid Dwindle, tile ordering, split controls, undo, and redo.
- Configurable per-monitor window limits with overflow routed to another workspace
  on the same monitor.
- Coordinated window animations with configurable duration and Reduce Motion support.
- Detection of applications that repeatedly reject an animated size, preventing
  resize feedback loops while still allowing their position to update.
- Stable display profiles backed by hardware UUID, with migration from older
  display-name profiles.
- Automatic reflow after windows open, close, or move, while intentional manual
  `join-with` grouping remains stable until workspace membership changes.
- Visual ordered application rules for layout, title matching, workspace routing,
  and scratchpads; monitor-relative workspace slots; and ten multi-window scratchpads.
- Manual-layout restoration, conflicting window-manager detection, and an opt-in
  per-display workspace bar.
- A searchable workspace/window Overview and Command Palette, both available as
  menu actions and bindable commands.
- Configurable daily update checks against TileSail's public GitHub releases; the
  app never downloads or installs an update automatically.
- Comment-preserving TOML updates, preview, validation, reload, and visual shortcut editing.

Read the complete [TileSail feature and Settings guide](./TILESAIL.md)
for the design goals, every Settings page, layout behavior, keyboard workflow,
multi-monitor model, limitations, and build instructions.

## Settings screenshots

These screenshots were captured before the TileSail rename; the app now displays TileSail.

### Per-monitor layouts

Choose a connected display and define the layout used for each window count from
1 through 10. The previews use that monitor's real aspect ratio and resolution.

![TileSail per-monitor layout settings](./docs/assets/aerospace-smooth-layouts.jpeg)

### Visual Custom Layout editor

Build a layout directly on the monitor preview, drag dividers to resize tiles, or
use exact split controls, presets, Hybrid Dwindle, ordering, undo, and redo.

![TileSail visual Custom Layout editor](./docs/assets/aerospace-smooth-custom-layout.jpeg)

### General settings

Configure startup, standard AeroSpace window-tree behavior, and coordinated window
animations from the same native interface.

![TileSail General settings](./docs/assets/aerospace-smooth-general.jpeg)

## Project status

TileSail is currently a source-built development version. It has been used
as a daily multi-monitor setup, but packaging, code signing, notarization, migration,
and public releases still need dedicated work before it should be treated as a
drop-in distribution for general users.


## Build and run

Requires macOS 13 or newer, Xcode with Swift 6.2 or newer, and Git.

```sh
git clone https://github.com/cassel/TileSail.git
cd TileSail
swift test
xcodebuild -project xcode/AeroSpace.xcodeproj -scheme AeroSpace \
  -configuration Debug -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
open .build/xcode/Build/Products/Debug/TileSail.app
```

Grant Accessibility permission to the app you run. Run only one window manager at
one time. This is a source-built development app, not a notarized public release.

Build the CLI with `swift build --product tilesail`. The `aerospace` executable is
also retained for existing scripts. Both use the same commands and TOML syntax.
Existing configuration paths and saved AeroSpaceSmooth settings remain compatible.
The internal Xcode project and scheme retain their historical names; both app
configurations produce **TileSail.app**.

## Credits and license

TileSail builds on [AeroSpace by Nikita Bobko and its contributors](https://github.com/nikitabobko/AeroSpace).
The complete development history and upstream copyright notices are preserved.
See [LICENSE.txt](./LICENSE.txt) and [NOTICE.md](./NOTICE.md).

- [TileSail issues](https://github.com/cassel/TileSail/issues)
- [TileSail releases](https://github.com/cassel/TileSail/releases)
- [Upstream command reference](https://nikitabobko.github.io/AeroSpace/commands)
