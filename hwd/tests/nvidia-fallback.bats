#!/usr/bin/env bats
# The mkinitcpio drop-in that keeps the stock fallback kernel off the NVIDIA
# modules it has no matching driver for, and step_fallback_nvidia's dry run.

setup() {
    HWD="$BATS_TEST_DIRNAME/../chiroptera-hwd"
    FIX="$BATS_TEST_DIRNAME/fixtures"
    WORK=$(mktemp -d)
}

teardown() {
    rm -rf "$WORK"
}

# nvidia_dropin's output with /usr/lib/modules rewritten under $WORK, so a
# test can build a fake kernel module tree without root.
dropin_at() {  # dest-file
    ( source "$HWD"; nvidia_dropin ) | sed "s#/usr/lib/modules#$WORK/modules#g" > "$1"
}

# Source the drop-in in a throwaway bash with the given KERNELVERSION (empty
# means unset) and starting MODULES, then print the resulting MODULES.
run_dropin() {  # kernelversion modules...
    local kv=$1
    shift
    DROPIN="$WORK/dropin.sh" bash -c '
        if [[ -n $1 ]]; then export KERNELVERSION=$1; fi
        shift
        MODULES=("$@")
        source "$DROPIN"
        printf "%s\n" "${MODULES[*]}"
    ' bash "$kv" "$@"
}

@test "kernel dir with no nvidia.ko drops the nvidia modules" {
    dropin_at "$WORK/dropin.sh"
    run run_dropin 6.10.0-cachyos amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm
    [ "$status" -eq 0 ]
    [ "$output" = amdgpu ]
}

@test "kernel with a prebuilt module under extramodules is left unchanged" {
    dropin_at "$WORK/dropin.sh"
    mkdir -p "$WORK/modules/6.10.0-cachyos/extramodules"
    touch "$WORK/modules/6.10.0-cachyos/extramodules/nvidia.ko.zst"
    run run_dropin 6.10.0-cachyos amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm
    [ "$status" -eq 0 ]
    [ "$output" = "amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm" ]
}

@test "kernel with a dkms module under updates/dkms is left unchanged" {
    dropin_at "$WORK/dropin.sh"
    mkdir -p "$WORK/modules/6.10.0-cachyos/updates/dkms"
    touch "$WORK/modules/6.10.0-cachyos/updates/dkms/nvidia.ko.zst"
    run run_dropin 6.10.0-cachyos amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm
    [ "$status" -eq 0 ]
    [ "$output" = "amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm" ]
}

@test "optional (?-suffixed) nvidia entries are also dropped when there is no module" {
    dropin_at "$WORK/dropin.sh"
    run run_dropin 6.10.0-cachyos amdgpu 'nvidia?' 'nvidia_drm?'
    [ "$status" -eq 0 ]
    [ "$output" = amdgpu ]
}

@test "KERNELVERSION unset leaves MODULES unchanged" {
    dropin_at "$WORK/dropin.sh"
    run run_dropin '' amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm
    [ "$status" -eq 0 ]
    [ "$output" = "amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm" ]
}

@test "the drop-in parses under bash -n" {
    dropin_at "$WORK/dropin.sh"
    run bash -n "$WORK/dropin.sh"
    [ "$status" -eq 0 ]
}

# ---- step_fallback_nvidia's dry run, laptop-shaped root as in apply.bats ----

laptop_root() {
    mkdir -p "$WORK/root/etc/default" "$WORK/root/boot/grub"
    cp "$FIX/pacman-conf/blackarch.conf" "$WORK/root/etc/pacman.conf"
    cp "$FIX/boot/default-grub" "$WORK/root/etc/default/grub"
    touch "$WORK/root/boot/grub/grub.cfg"
}

dry_run_laptop() {
    HWD_ROOT="$WORK/root" HWD_VIRT=none HWD_INSTALLED="$WORK/installed" \
        HWD_LDSO_HELP="$FIX/laptop-zen2/ldso-help" HWD_CPUINFO="$FIX/laptop-zen2/cpuinfo" \
        "$HWD" apply --dry-run
}

line_of() {  # fixed-string -> first line number in $output
    grep -nF -- "$1" <<<"$output" | head -n1 | cut -d: -f1
}

@test "dry run with nvidia-open installed: drop-in, removal, and mkinitcpio, in order" {
    laptop_root
    printf 'linux\nnvidia-open\nlinux-cachyos-nvidia-open\n' > "$WORK/installed"

    run dry_run_laptop
    [ "$status" -eq 0 ]

    grep -qF '+# Written by chiroptera-hwd' <<<"$output"
    grep -qF '+ pacman -R nvidia-open' <<<"$output"
    grep -qF '+ mkinitcpio -p linux' <<<"$output"

    chwd=$(line_of '+ chwd -a')
    dropin=$(line_of '+# Written by chiroptera-hwd')
    rm=$(line_of '+ pacman -R nvidia-open')
    mkinitcpio=$(line_of '+ mkinitcpio -p linux')
    step5=$(line_of ':: step 5/5')
    [ "$chwd" -lt "$dropin" ]
    [ "$dropin" -lt "$rm" ]
    [ "$rm" -lt "$mkinitcpio" ]
    [ "$mkinitcpio" -lt "$step5" ]

    [ -z "$(find "$WORK/root" -name '*.hwd-*')" ]
    [ ! -e "$WORK/root/etc/mkinitcpio.conf.d/90-chiroptera-hwd.conf" ]
}

@test "dry run with only linux-cachyos-nvidia-open installed: no removal, drop-in and mkinitcpio still appear" {
    laptop_root
    printf 'linux\nlinux-cachyos-nvidia-open\n' > "$WORK/installed"

    run dry_run_laptop
    [ "$status" -eq 0 ]

    grep -qF '+# Written by chiroptera-hwd' <<<"$output"
    grep -qF '+ mkinitcpio -p linux' <<<"$output"
    [ "$(grep -c 'pacman -R nvidia-open' <<<"$output")" -eq 0 ]
}

@test "dry run without linux-cachyos-nvidia-open: note only, no removal, no mkinitcpio" {
    laptop_root
    printf 'linux\nnvidia-open\n' > "$WORK/installed"

    run dry_run_laptop
    [ "$status" -eq 0 ]

    grep -qF 'linux-cachyos-nvidia-open is not installed yet: chwd installs it at step 4, and hwd then removes nvidia-open and writes the mkinitcpio drop-in.' <<<"$output"
    [ "$(grep -c 'pacman -R nvidia-open' <<<"$output")" -eq 0 ]
    [ "$(grep -c 'mkinitcpio -p linux' <<<"$output")" -eq 0 ]
}
