#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" != "--dont-rebuild" ]]; then
    ./build-release.sh "$@"
fi
app_source=".release/TileSail.app"
app_destination="$HOME/Applications/TileSail.app"
[[ -d "$app_source" ]] || { echo "Build TileSail first." >&2; exit 1; }
mkdir -p "$HOME/Applications" .backups
if [[ -d "$app_destination" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$app_destination" ".backups/TileSail-$(date +%Y%m%d-%H%M%S).zip"
fi
ditto "$app_source" "$app_destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/$app_source"
echo "Installed $app_destination. Open it and grant Accessibility permission if requested."
