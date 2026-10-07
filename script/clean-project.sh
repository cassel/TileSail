#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

clean_flags=-fdX
case "${1:-}" in
    "") ;;
    --dry-run) clean_flags=-ndX ;;
    *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
    echo "Usage: $0 [--dry-run]" >&2
    exit 2
fi

# Limit cleanup to ignored build outputs. Never double-force nested repositories
# or clean the entire checkout: local tools, backup archives and source copies
# may be untracked. Xcode project regeneration is a separate operation.
git clean "$clean_flags" -- \
    .build .debug .release .shell-completion .site .man .deps .swiftpm \
    xcode/.xcode-build
