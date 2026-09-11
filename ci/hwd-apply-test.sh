#!/usr/bin/env bash
# Run chiroptera-hwd apply for real in a throwaway Arch container and check it
# left a CachyOS system behind, initramfs included.
#
# This is what proves the two-transaction upgrade: Arch's pacman cannot install
# x86_64_v3 packages, so if the fork were not installed first, step 2 fails.
# The runner has no GPU worth the name; chwd picks whatever its virtual
# hardware matches, and only its exit status is checked.
#
# Needs root and network, and rewrites the system: container only. Must also
# run --privileged: pacman's post-transaction hooks (mkinitcpio, depmod,
# systemd) each try to unshare the network sandbox, which an unprivileged
# container cannot grant, and pacman does not fail a transaction over a
# failed hook -- so without --privileged no initramfs is built and this test
# cannot see a broken one.
#
#   docker run --rm --privileged -v "$PWD:/work:ro" -w /work archlinux:base-devel \
#       ci/hwd-apply-test.sh

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
hwd=$repo_root/hwd/chiroptera-hwd

fail() { printf 'hwd apply test: %s\n' "$1" >&2; exit 1; }

[[ -f /.dockerenv || -f /run/.containerenv ]] || fail "refusing to run outside a container"

# unshare --net succeeds only with CAP_SYS_ADMIN (or a fully unprivileged
# user namespace, which pacman's hooks do not use); an unprivileged Docker
# container has neither, so this reliably detects the missing --privileged
# before wasting time on a run whose hooks cannot do real work.
unshare --net true 2>/dev/null || fail "container is not privileged; run it with docker run --privileged (pacman's hooks cannot run otherwise)"

# lspci, for chwd.
pacman -Sy --needed --noconfirm pciutils >/dev/null

"$hwd" detect
level=$("$hwd" detect | sed -n 's/^  "level": "\(.*\)",$/\1/p')
[[ -n $level ]] || fail "detect printed no level"

HWD_BOOTLOADER=unknown "$hwd" apply --yes

pacman -Q linux-cachyos >/dev/null || fail "linux-cachyos is not installed"

# pacman does not fail a transaction over a failed hook, so this file is the
# only evidence that mkinitcpio's post-transaction hook actually ran to
# completion, rather than failing silently as it does without --privileged.
[[ -s /boot/initramfs-linux-cachyos.img ]] ||
    fail "/boot/initramfs-linux-cachyos.img was not built (mkinitcpio's hook did not run)"

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

# A second apply must be a no-op: every step is meant to be idempotent, and
# this is the cheapest place that can prove pacman.conf specifically settles
# rather than growing a new backup or a new edit each time.
shopt -s nullglob
before_backup_files=(/etc/pacman.conf.hwd-*)
before_sum=$(sha256sum /etc/pacman.conf)
before_backups=${#before_backup_files[@]}

HWD_BOOTLOADER=unknown "$hwd" apply --yes

after_backup_files=(/etc/pacman.conf.hwd-*)
after_sum=$(sha256sum /etc/pacman.conf)
after_backups=${#after_backup_files[@]}
[[ $before_sum == "$after_sum" ]] || fail "a second apply changed /etc/pacman.conf"
[[ $before_backups == "$after_backups" ]] || fail "a second apply left a new pacman.conf backup"

echo "ok: $level CachyOS system with linux-cachyos, its initramfs and the CachyOS pacman; a second apply changed nothing"
