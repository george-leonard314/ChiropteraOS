#!/usr/bin/env bash
# Check every PKGBUILD parses and yields usable metadata.
#
# Runs offline: --printsrcinfo evaluates the PKGBUILD but fetches no sources.
# This is the cheapest CI layer and the one that catches an edit that leaves a
# PKGBUILD unparseable.

set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
status=0
found=0

shopt -s nullglob
for pkgbuild in "$repo_root"/pkgs/*/PKGBUILD; do
    dir=$(dirname "$pkgbuild")
    name=$(basename "$dir")
    found=$((found + 1))

    if ! err=$(bash -n "$pkgbuild" 2>&1); then
        printf '%s: does not parse\n%s\n\n' "$name" "$err" >&2
        status=1
        continue
    fi

    if ! err=$(cd "$dir" && makepkg --printsrcinfo 2>&1 >/dev/null); then
        printf '%s: metadata could not be generated\n%s\n\n' "$name" "$err" >&2
        status=1
        continue
    fi

    printf '%s: ok\n' "$name"
done

if [[ $found -eq 0 ]]; then
    echo "no PKGBUILDs found under pkgs/" >&2
    exit 1
fi

exit "$status"
