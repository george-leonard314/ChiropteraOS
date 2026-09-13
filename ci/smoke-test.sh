#!/usr/bin/env bash
# Prove the built repository is actually installable.
#
# This is the check that catches a dependency that exists nowhere pacman can
# reach it -- the class of failure that made chiroptera-meta uninstallable
# while app2unit was AUR-only. It resolves rather than installs: the failure
# being guarded against is an unsatisfiable dependency, not a bad file list.
#
# Needs root, because pacman -Sy does. In CI that is the container's root; run
# it locally inside a container rather than as your own user.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REPO_NAME=${REPO_NAME:-chiroptera}
REPO_DIR=${REPO_DIR:-$repo_root/repo}
TARGET=${TARGET:-chiroptera-meta}

fail() { printf 'smoke test: %s\n' "$1" >&2; exit 1; }

[[ -d $REPO_DIR ]] || fail "no repository at $REPO_DIR"

# Static hosts do not serve symlinks. repo-add creates the bare .db and .files
# as links, so publishing them unresolved yields a repository that works over
# file:// and 404s over HTTP -- a failure that would only appear after deploy.
for ext in db files; do
    f="$REPO_DIR/$REPO_NAME.$ext"
    [[ -e $f ]] || fail "$REPO_NAME.$ext is missing"
    [[ -L $f ]] && fail "$REPO_NAME.$ext is a symlink; static hosting would 404 on it"
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/db" "$work/cache"

cat > "$work/pacman.conf" <<CONF
[options]
Architecture = auto
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[$REPO_NAME]
SigLevel = Never
Server = file://$REPO_DIR
CONF

pac() { pacman --config "$work/pacman.conf" --dbpath "$work/db" --cachedir "$work/cache" "$@"; }

echo "syncing databases"
pac -Sy --noconfirm >/dev/null

echo "resolving $TARGET"
if ! resolution=$(pac -Sp --noconfirm "$TARGET" 2>&1); then
    printf '%s\n' "$resolution" >&2
    fail "$TARGET does not resolve; a dependency is unsatisfiable"
fi

# Every package this repository exists to provide must come from it, not be
# quietly satisfied by something else.
for required in app2unit pacseek chiroptera-shell chiroptera-dots; do
    grep -q "/$required-" <<<"$resolution" \
        || fail "$required was not part of resolving $TARGET"
done

# chiroptera-hwd adds the CachyOS repositories, so it must resolve without
# them: from Arch plus this repository alone.
echo "resolving chiroptera-hwd"
if ! resolution=$(pac -Sp --noconfirm chiroptera-hwd 2>&1); then
    printf '%s\n' "$resolution" >&2
    fail "chiroptera-hwd does not resolve; it must not need [cachyos]"
fi
grep -q "/chiroptera-hwd-" <<<"$resolution" \
    || fail "chiroptera-hwd was not served by the built repository"

# The live image installs displaylink, whose only dependency that pacman cannot
# otherwise reach is evdi. Both are AUR packages this repository vendors, and
# displaylink pins evdi<1.16 -- exactly the shape of dependency that made
# chiroptera-meta uninstallable before app2unit was carried here. Resolve it so
# a version bump that breaks the pin fails the build rather than the ISO.
echo "resolving displaylink"
if ! resolution=$(pac -Sp --noconfirm displaylink 2>&1); then
    printf '%s\n' "$resolution" >&2
    fail "displaylink does not resolve; check the evdi<1.16 pin against evdi-dkms"
fi
for required in displaylink evdi-dkms; do
    grep -q "/$required-" <<<"$resolution" \
        || fail "$required was not served by the built repository"
done

echo "ok: $TARGET, chiroptera-hwd and displaylink resolve against the built repository"
