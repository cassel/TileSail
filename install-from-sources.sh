#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# Preview and explicitly prepared installs never rebuild or activate anything.
rebuild=true
migration_args=()
build_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dont-rebuild) rebuild=false; shift ;;
        --dry-run) rebuild=false; migration_args+=("$1"); shift ;;
        --release|--applications|--system-applications|--cli|--compatibility-cli|--agents|--backups|--project)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
            migration_args+=("$1" "$2"); shift 2 ;;
        --build-version|--codesign-identity)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
            build_args+=("$1" "$2"); shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
if "$rebuild"; then ./build-release.sh "${build_args[@]}"; fi
exec python3 script/install-migration.py "${migration_args[@]}"
