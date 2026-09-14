#!/usr/bin/env bash
# Build the ChiropteraOS ISO from iso/. Run as root in a privileged
# archlinux container (mkarchiso needs root and loop-free mtools/xorriso).
#
#   PACKAGES_DIR  the built ChiropteraOS packages: CI's chiroptera-repo
#                 artifact plus chiroptera-calamares-config. Default ./repo.
#   OUT_DIR       where the .iso lands. Default /build/out.
#
# The work area is /build (about 15 GB); iso/pacman.conf reads the local
# repository from file:///build/repo, so that path is fixed.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PACKAGES_DIR=${PACKAGES_DIR:-$repo_root/repo}
OUT_DIR=${OUT_DIR:-/build/out}
CACHYOS_KEY=F3B607488DB35A47
# BlackArch's trusted signing keys (blackarch-keyring's blackarch-trusted).
BLACKARCH_KEYS=(8F9A9793CB8591147C2EC70566E0CDBD1E01F333 A0917C4147A37007CB54C1CFD295AA940EFDDF62
                4345771566D76038C7FEB43863EC0ADBEA87E4E3 F9A6E68A711354D84A9B91637533BAFE69A25079)

pacman -Sy --noconfirm --needed archiso >/dev/null

# [cachyos] supplies the greeter and [blackarch] the installer; trust their keys.
pacman-key --init &>/dev/null
for key in "$CACHYOS_KEY" "${BLACKARCH_KEYS[@]}"; do
    if ! pacman-key --list-keys "$key" &>/dev/null; then
        pacman-key --recv-keys "$key" --keyserver keyserver.ubuntu.com
        pacman-key --lsign-key "$key"
    fi
done

# CI's artifact keeps the two newest builds of each package. repo-add keeps
# the last file it is handed for a name, and a glob puts chiroptera-dots-0.1.10
# before 0.1.9, so copy only the newest of each.
declare -A best_file=() best_ver=()
for f in "$PACKAGES_DIR"/*.pkg.tar.zst; do
    [[ $(basename "$f") =~ ^(.+)-([^-]+-[^-]+)-[^-]+\.pkg\.tar\.zst$ ]] || continue
    name=${BASH_REMATCH[1]}
    ver=${BASH_REMATCH[2]}
    if [[ -z ${best_ver[$name]:-} ]] || (($(vercmp "$ver" "${best_ver[$name]}") > 0)); then
        best_ver[$name]=$ver
        best_file[$name]=$f
    fi
done
rm -rf /build/repo
mkdir -p /build/repo
cp "${best_file[@]}" /build/repo/
repo-add -q /build/repo/chiroptera.db.tar.zst /build/repo/*.pkg.tar.zst

# mkarchiso bind-mounts /dev, /proc and /sys into the work chroot. When a run
# is killed they stay mounted, and removing the work directory then deletes
# device nodes *through* the /dev bind mount -- in a privileged container that
# reaches the host and takes out /dev/null. So unmount deepest-first, and stay
# on one file system while deleting.
if [[ -d /build/work ]]; then
    while read -r mountpoint; do
        umount -l "$mountpoint" || true
    done < <(awk '$2 ~ "^/build/work" { print $2 }' /proc/self/mounts | sort -r)
    rm --one-file-system -rf /build/work
fi

mkarchiso -v -r -w /build/work -o "$OUT_DIR" "$repo_root/iso"
ls -lh "$OUT_DIR"
