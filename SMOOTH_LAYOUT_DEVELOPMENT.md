# AeroSpace Smooth development

This fork experiments with coordinated native macOS window reflow animations.
It keeps AeroSpace's workspace and tree model while replacing immediate,
window-by-window layout writes with a single layout transaction.

## Current milestone

- Collect target frames for every visible monitor before applying them.
- Animate local reflows with a cubic ease-out curve at approximately 60 FPS.
- Cancel and rebase when a different layout arrives during an animation.
- Ignore duplicate refreshes that have the same target frames.
- Apply cross-monitor and workspace transitions immediately.
- Respect the macOS Reduce Motion preference.
- Rebuild workspace trees natively when windows open, close, or move.
- Keep independent layout profiles for each physical monitor.
- Choose a layout for every window count from 1 through 10.
- Enforce a configurable tile limit per monitor and move overflow to the next
  workspace assigned to that monitor.

## Monitor layout profiles

Open the TileSail menu and choose **Settings…** (`Command+Shift+L`).
Each detected display has its own profile with:

- An enable switch for native automatic organization.
- A tile limit from 1 through 10.
- A visual layout selector for each window count from 1 through 10.
- Built-in presets for horizontal and vertical monitors.

The settings are stored by the display's stable Core Graphics UUID in the app
preferences; older name-based profiles migrate automatically. A workspace with one
tiled window is always maximized. Manual resizing is preserved until the workspace
membership, window order, selected style, or monitor changes.

## Visual configuration

The same Settings window also exposes the active TOML configuration in visual
sections for general behavior, workspaces and monitor assignments, gaps,
application rules, automation commands, environment variables, and hotkeys.
Edits are validated with AeroSpace's real config parser before the file is
atomically saved and reloaded. The editor patches only changed values so
comments, ordering, and unknown advanced options remain intact.

## Configuration

```toml
# 0 disables layout animations. Accepted range: 0...1000.
layout-animation-duration-ms = 160

layout-animation-respect-reduce-motion = true
```

## Build

```sh
cd /Users/cassel/app/TileSail
./build-debug.sh -Xswiftc -warnings-as-errors
./swift-test.sh
./lint.sh
./generate.sh
xcodebuild \
  -project xcode/AeroSpace.xcodeproj \
  -scheme AeroSpace \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath xcode/.xcode-build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The generated app is:

```text
/Users/cassel/app/TileSail/xcode/.xcode-build/Build/Products/Debug/TileSail.app
```

## Manual test safety

Do not run the installed AeroSpace and an additional TileSail build simultaneously. They
both manage the same windows, shortcuts, and server resources. Quit the
installed app first, install the debug build at the canonical
`/Users/cassel/Applications/TileSail.app` path, and grant TileSail
Accessibility permission when macOS asks.

The first manual test should cover:

1. Close one of five tiled windows and verify that the remaining tree reflows
   once without flattening.
2. Open a window and verify that all affected windows arrive together.
3. Switch workspaces and move a window to another monitor; these transitions
   must snap rather than travel across displays.
4. Trigger repeated focus commands during an active animation and verify that
   the motion does not restart or oscillate.
