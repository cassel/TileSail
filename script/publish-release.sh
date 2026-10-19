#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -lt 2 || $# -gt 3 || "$1" != "--build-version" || ! "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    echo "Usage: $0 --build-version VERSION [--publish]" >&2
    exit 1
fi
release_version="$2"
if [[ $# = 3 && "$3" != --publish ]]; then
    echo "Unknown option: $3" >&2
    exit 1
fi
artifact=".local/installers/TileSail-${release_version}-universal.dmg"
for required in "$artifact" "$artifact.sha256" "$artifact.build-info.json"; do
    [[ -f "$required" ]] || { echo "Build the installer first: bash script/build-dmg.sh $release_version" >&2; exit 1; }
done
python3 - "$artifact.build-info.json" <<'PYVERIFY'
import json, subprocess, sys
info = json.load(open(sys.argv[1]))
head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
assert not info["working_tree_dirty"], "Refusing to publish a dirty preview build."
assert info["packaging_commit"] == head, "Rebuild the installer from the current commit."
assert info["configuration"] == "Release", "Publish a Release build."
assert set(info["architectures"]) == {"arm64", "x86_64"}, "Publish a universal build."
assert info["bundle_id"] == "us.cassel.tilesail", "Publish the Release bundle identity."
assert not subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], text=True).strip(), "Commit source changes before publishing."
PYVERIFY
(cd "$(dirname "$artifact")" && shasum -a 256 -c "$(basename "$artifact").sha256")
flags=(--repo cassel/TileSail --title "TileSail $release_version" --verify-tag)
if [[ "${3:-}" != --publish ]]; then flags+=(--draft); fi
if [[ "$release_version" = *-* ]]; then flags+=(--prerelease); fi
notes="dev-docs/releases/${release_version}.md"
if [[ -f "$notes" ]]; then flags+=(--notes-file "$notes"); else flags+=(--generate-notes); fi
gh release create "v${release_version}" "$artifact" "$artifact.sha256" "$artifact.build-info.json" "${flags[@]}"
