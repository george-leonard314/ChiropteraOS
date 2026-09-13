#!/usr/bin/env bats
# Arch's split firmware packages that CachyOS does not carry are removed
# before the upgrade, and put back if the upgrade fails.

setup() {
    HWD="$BATS_TEST_DIRNAME/../chiroptera-hwd"
    FIX="$BATS_TEST_DIRNAME/fixtures"
    WORK=$(mktemp -d)
    printf '%s\n' linux linux-firmware linux-firmware-amd linux-firmware-amdgpu \
        linux-firmware-other linux-firmware-ti linux-firmware-whence > "$WORK/installed"
    printf '%s\n' linux-cachyos linux-firmware linux-firmware-amdgpu \
        linux-firmware-other linux-firmware-whence > "$WORK/cachyos"
}

teardown() {
    rm -rf "$WORK"
}

@test "split_firmware names installed firmware packages CachyOS lacks" {
    source "$HWD"
    run split_firmware "$WORK/installed" "$WORK/cachyos"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'linux-firmware-amd\nlinux-firmware-ti')" ]
}

@test "split_firmware names nothing once CachyOS carries every package" {
    source "$HWD"
    cp "$WORK/installed" "$WORK/cachyos"
    run split_firmware "$WORK/installed" "$WORK/cachyos"
    [ -z "$output" ]
}

@test "unsynced CachyOS databases remove nothing" {
    source "$HWD"
    : > "$WORK/empty"
    DRY_RUN=1 ASSUME_YES=0 TMPD=$WORK HWD_INSTALLED=$WORK/installed HWD_CACHYOS_PKGS=$WORK/empty
    run step_drop_split_firmware
    [ "$status" -eq 0 ]
    ! grep -qF -- '-Rdd' <<<"$output"
    grep -qF 'not synced yet' <<<"$output"
}

@test "a failed upgrade reinstalls the removed packages" {
    source "$HWD"
    mkdir -p "$WORK/bin"
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/calls"\n' "$WORK" > "$WORK/bin/pacman"
    chmod +x "$WORK/bin/pacman"
    PATH="$WORK/bin:$PATH" DRY_RUN=0 ASSUME_YES=1 TMPD=$WORK
    HWD_INSTALLED=$WORK/installed HWD_CACHYOS_PKGS=$WORK/cachyos
    step_drop_split_firmware
    restore_split_firmware 2>/dev/null
    [ "$(sed -n 1p "$WORK/calls")" = "--noconfirm -Rdd linux-firmware-amd linux-firmware-ti" ]
    [ "$(sed -n 2p "$WORK/calls")" = "--noconfirm -S --needed linux-firmware-amd linux-firmware-ti" ]
}

@test "apply's dry run removes them after CachyOS's pacman and before the upgrade" {
    mkdir -p "$WORK/root/etc/default" "$WORK/root/boot/grub"
    cp "$FIX/pacman-conf/blackarch.conf" "$WORK/root/etc/pacman.conf"
    cp "$FIX/boot/default-grub" "$WORK/root/etc/default/grub"
    touch "$WORK/root/boot/grub/grub.cfg"
    run env HWD_ROOT="$WORK/root" HWD_VIRT=none HWD_INSTALLED="$WORK/installed" \
        HWD_CACHYOS_PKGS="$WORK/cachyos" \
        HWD_LDSO_HELP="$FIX/laptop-zen2/ldso-help" HWD_CPUINFO="$FIX/laptop-zen2/cpuinfo" \
        "$HWD" apply --dry-run
    [ "$status" -eq 0 ]
    line_of() { grep -nF -- "$1" <<<"$output" | head -n1 | cut -d: -f1; }
    pacman_line=$(line_of '+ pacman -Syy --needed cachyos/pacman')
    rdd=$(line_of '+ pacman -Rdd linux-firmware-amd linux-firmware-ti')
    syu=$(line_of '+ pacman -Syu')
    [ -n "$rdd" ]
    [ "$pacman_line" -lt "$rdd" ]
    [ "$rdd" -lt "$syu" ]
}
