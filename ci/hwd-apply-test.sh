#!/usr/bin/env bash
# Run chiroptera-hwd apply for real in a throwaway Arch container and check it
# left a CachyOS system behind.
#
# This is what proves the two-transaction upgrade: Arch's pacman cannot install
# x86_64_v3 packages, so if the fork were not installed first, step 2 fails.
# The runner has no GPU worth the name; chwd picks whatever its virtual
# hardware matches, and only its exit status is checked.
#
# Needs root and network, and rewrites the system: container only.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
hwd=$repo_root/hwd/chiroptera-hwd

fail() { printf 'hwd apply test: %s\n' "$1" >&2; exit 1; }

[[ -f /.dockerenv || -f /run/.containerenv ]] || fail "refusing to run outside a container"

# lspci, for chwd.
pacman -Sy --needed --noconfirm pciutils >/dev/null

"$hwd" detect
level=$("$hwd" detect | sed -n 's/^  "level": "\(.*\)",$/\1/p')
[[ -n $level ]] || fail "detect printed no level"

HWD_BOOTLOADER=unknown "$hwd" apply --yes

pacman -Q linux-cachyos >/dev/null || fail "linux-cachyos is not installed"

# shellcheck source=../hwd/chiroptera-hwd
source "$hwd"
core_line=$(grep -nx '\[core\]' /etc/pacman.conf | cut -d: -f1)
for repo in $(repos_for "$level"); do
    line=$(grep -nxF "[$repo]" /etc/pacman.conf | cut -d: -f1)
    [[ -n $line ]] || fail "[$repo] is missing from pacman.conf"
    (( line < core_line )) || fail "[$repo] is not above [core]"
done

installed=$(pacman -Q pacman | cut -d' ' -f2)
synced=$(pacman -Si cachyos/pacman | awk -F': *' '/^Version/ { print $2 }')
[[ $installed == "$synced" ]] || fail "pacman is $installed, not cachyos/pacman $synced"

echo "ok: $level CachyOS system with linux-cachyos and the CachyOS pacman"
