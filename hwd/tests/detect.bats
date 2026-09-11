#!/usr/bin/env bats
# CPU level, microcode, virtualisation and the JSON plan, against captured
# machines. The KVM case reuses the laptop's CPU: a guest sees its host's ISA.

setup() {
    HWD="$BATS_TEST_DIRNAME/../chiroptera-hwd"
    FIX="$BATS_TEST_DIRNAME/fixtures"
}

detect_on() {  # machine virt bootloader
    HWD_LDSO_HELP="$FIX/$1/ldso-help" HWD_CPUINFO="$FIX/$1/cpuinfo" \
        HWD_VIRT="$2" HWD_BOOTLOADER="$3" "$HWD" detect
}

@test "author's laptop: Zen 2 is v3, AMD microcode, GRUB -- exact plan" {
    run detect_on laptop-zen2 none grub
    [ "$status" -eq 0 ]
    diff -u "$FIX/laptop-zen2/expected.json" <(printf '%s\n' "$output")
}

@test "Zen 4 with AVX-512 gets znver4, not v4" {
    run detect_on zen4-desktop none systemd-boot
    [ "$status" -eq 0 ]
    grep -qF '"level": "znver4"' <<<"$output"
    grep -qF '"repos": ["cachyos-znver4", "cachyos-core-znver4", "cachyos-extra-znver4", "cachyos"]' <<<"$output"
    grep -qF '"bootloader": "systemd-boot"' <<<"$output"
}

@test "Intel with v4 listed but unsupported is v3 with Intel microcode" {
    run detect_on intel-v3-laptop none grub
    [ "$status" -eq 0 ]
    grep -qF '"level": "v3"' <<<"$output"
    grep -qF '"intel-ucode"' <<<"$output"
    ! grep -qF '"amd-ucode"' <<<"$output"
}

@test "Intel with AVX-512 gets v4" {
    run detect_on intel-v4-server none unknown
    [ "$status" -eq 0 ]
    grep -qF '"level": "v4"' <<<"$output"
    grep -qF '"repos": ["cachyos-v4", "cachyos-core-v4", "cachyos-extra-v4", "cachyos"]' <<<"$output"
}

@test "a CPU below v3 gets the baseline repository only" {
    run detect_on pre-v3 none grub
    [ "$status" -eq 0 ]
    grep -qF '"level": "baseline"' <<<"$output"
    grep -qF '"repos": ["cachyos"]' <<<"$output"
}

@test "KVM guest adds the QEMU guest agent" {
    run detect_on laptop-zen2 kvm unknown
    [ "$status" -eq 0 ]
    grep -qF '"virt": "kvm"' <<<"$output"
    grep -qF '"qemu-guest-agent"' <<<"$output"
}

@test "VirtualBox guest adds the VirtualBox guest utilities" {
    run detect_on laptop-zen2 oracle unknown
    [ "$status" -eq 0 ]
    grep -qF '"virtualbox-guest-utils"' <<<"$output"
}

@test "mirrorlist packages follow the sections, deduplicated" {
    source "$HWD"
    run mirrorlists_for v3
    [ "$output" = $'cachyos-v3-mirrorlist\ncachyos-mirrorlist' ]
    run mirrorlists_for znver4
    [ "$output" = $'cachyos-v4-mirrorlist\ncachyos-mirrorlist' ]
    run mirrorlists_for baseline
    [ "$output" = "cachyos-mirrorlist" ]
}

@test "bootloader detection: grub.cfg wins, then loader.conf, else unknown" {
    source "$HWD"
    root=$(mktemp -d)
    HWD_ROOT=$root
    run detect_bootloader
    [ "$output" = "unknown" ]
    mkdir -p "$root/efi/loader" && touch "$root/efi/loader/loader.conf"
    run detect_bootloader
    [ "$output" = "systemd-boot" ]
    run sdboot_esp
    [ "$output" = "$root/efi" ]
    mkdir -p "$root/boot/grub" && touch "$root/boot/grub/grub.cfg"
    run detect_bootloader
    [ "$output" = "grub" ]
    rm -rf "$root"
}

@test "no command prints usage and exits 2" {
    run "$HWD"
    [ "$status" -eq 2 ]
    grep -qF 'usage:' <<<"$output"
}
