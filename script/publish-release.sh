#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$#" -ne 2 || "$1" != "--build-version" ]]; then
    echo "Usage: $0 --build-version VERSION" >&2
    exit 1
fi
release_version="$2"
artifact=".release/TileSail-v${release_version}.zip"
[[ -f "$artifact" ]] || { echo "Build $artifact first." >&2; exit 1; }
gh release create "v${release_version}" "$artifact" --repo cassel/TileSail --draft --generate-notes
