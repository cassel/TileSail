#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 PATH/TileSail.app OUTPUT.dmg" >&2
    exit 1
fi
app="$1"
output="$2"
[[ "$output" = /* ]] || output="$PWD/$output"
[[ -d "$app" && "$output" = *.dmg ]] || { echo "Expected TileSail.app and a .dmg output." >&2; exit 1; }
[[ ! -e "$output" ]] || { echo "Output already exists: $output" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")" = TileSail ]]
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
case "$bundle_id" in
    us.cassel.tilesail) build_kind=Release ;;
    bobko.aerospace.debug) build_kind=Debug ;;
    *) echo "Unexpected TileSail bundle ID: $bundle_id" >&2; exit 1 ;;
esac
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
architectures="$(lipo -archs "$app/Contents/MacOS/TileSail")"

stage="$(mktemp -d "${TMPDIR:-/tmp}/tilesail-dmg.XXXXXX")"
raw_image="${stage}.raw.dmg"
trap 'rm -rf "$stage"; rm -f "$raw_image"' EXIT
mkdir -p "$(dirname "$output")"
ditto "$app" "$stage/TileSail.app"
cmp "$app/Contents/MacOS/TileSail" "$stage/TileSail.app/Contents/MacOS/TileSail"
# Preserve a valid distribution signature; sign unsigned local builds ad hoc.
if ! codesign --verify --deep --strict "$stage/TileSail.app" 2>/dev/null; then
    codesign --force --deep --sign - "$stage/TileSail.app"
fi
codesign --verify --deep --strict "$stage/TileSail.app"
(cd "$stage" && shasum -a 256 TileSail.app/Contents/MacOS/TileSail > BUILD-EXECUTABLE.sha256)
ln -s /Applications "$stage/Applications"
cp LICENSE.txt NOTICE.md "$stage/"
ditto legal "$stage/legal"
git rev-parse HEAD > "$stage/BUILD-COMMIT.txt"
signature_description="Ad-hoc signed; not notarized by Apple."
if codesign -dv "$stage/TileSail.app" 2>&1 | grep -q '^Authority=Developer ID Application:'; then
    signature_description="Developer ID signed; notarization has not been verified by this packaging script."
fi
cat > "$stage/README.txt" <<EOF
TileSail $version — $build_kind for macOS 13 or later
Architectures: $architectures
$signature_description

Created and maintained by Cleverson Cassel (C. Cassel), founder and CEO of CambioReal.
An independent macOS window manager focused on fast window management and
multi-monitor workflows. Open About TileSail in the menu bar for credits and links.

INSTALLATION
1. Quit your existing TileSail/AeroSpace before replacing the application.
2. Drag TileSail.app to Applications. Keep only one window manager active.
3. Open TileSail and grant Accessibility permission when requested.
   If macOS blocks this unnotarized build, review the message in
   System Settings > Privacy & Security before choosing whether to open it.

UPDATING
Existing TOML paths and AeroSpaceSmooth preferences remain compatible.
Keep your existing installation path when updating. If a LaunchAgent points to
another path, update it to the canonical TileSail.app location while preserving
its configuration argument. Release and Debug use different bundle identities;
macOS may require Accessibility permission again when switching between them.

SOURCE, SUPPORT AND LICENSE
https://github.com/cassel/TileSail
https://github.com/cassel/TileSail/issues
Contact: C. Cassel <c@cassel.us>

Derived from AeroSpace by Nikita Bobko and contributors. This is an independent
project, not an official AeroSpace release. MIT and third-party notices included.
BUILD-COMMIT.txt identifies the repository HEAD used during packaging; see
BUILD-INFO.json for whether the working tree contained uncommitted changes.
EOF
python3 - "$stage" "$version" "$bundle_id" "$architectures" "$build_kind" <<'PYINFO'
import json, os, subprocess, sys
from pathlib import Path
stage, version, bundle_id, architectures, build_kind = sys.argv[1:]
info = {
    "product": "TileSail", "version": version, "configuration": build_kind,
    "bundle_id": bundle_id, "architectures": architectures.split(),
    "packaging_commit": os.environ.get("TILESAIL_PACKAGING_SOURCE_COMMIT") or subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    "working_tree_dirty": (os.environ["TILESAIL_PACKAGING_SOURCE_DIRTY"] == "true") if "TILESAIL_PACKAGING_SOURCE_DIRTY" in os.environ else bool(subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], text=True).strip()),
}
(Path(stage) / "BUILD-INFO.json").write_text(json.dumps(info, indent=2) + "\n")
PYINFO
if ! hdiutil create -volname TileSail -srcfolder "$stage" -format UDZO "$output"; then
    # HFS+ hybrid creation also works when no disk device service is available.
    # Convert that image to the same compressed UDIF format without mounting it.
    rm -f "$output"
    hdiutil makehybrid -hfs -hfs-volume-name TileSail -o "$raw_image" "$stage"
    hdiutil convert "$raw_image" -format UDZO -o "$output"
fi
hdiutil verify "$output"
cp "$stage/BUILD-INFO.json" "$output.build-info.json"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
mkdir -p .local/installers
printf '%s\n' "$output" > .local/installers/latest-dmg-path.txt
echo "Created $output"
