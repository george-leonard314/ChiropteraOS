#!/usr/bin/env bats
# Making linux-cachyos the default boot entry, for GRUB and systemd-boot.

setup() {
    source "$BATS_TEST_DIRNAME/../chiroptera-hwd"
    BOOT="$BATS_TEST_DIRNAME/fixtures/boot"
}

@test "GRUB: a commented GRUB_TOP_LEVEL is replaced in place, GRUB_DEFAULT kept" {
    run edit_default_grub < "$BOOT/default-grub"
    [ "$status" -eq 0 ]
    [ "$(tail -n1 <<<"$output")" = 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"' ]
    [ "$(grep -c GRUB_TOP_LEVEL <<<"$output")" -eq 1 ]
    grep -qx 'GRUB_DEFAULT=0' <<<"$output"
}

@test "GRUB: without any GRUB_TOP_LEVEL line one is appended" {
    run edit_default_grub <<<'GRUB_DEFAULT=0'
    [ "$output" = 'GRUB_DEFAULT=0
GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"' ]
}

@test "GRUB: a second run changes nothing" {
    first=$(edit_default_grub < "$BOOT/default-grub")
    second=$(edit_default_grub <<<"$first")
    [ "$first" = "$second" ]
}

@test "systemd-boot: the stock entry is the normal one, not the fallback" {
    run stock_sdboot_entry "$BOOT/esp"
    [ "$status" -eq 0 ]
    [ "$output" = "$BOOT/esp/loader/entries/arch.conf" ]
}

@test "systemd-boot: no stock entry is a failure" {
    run stock_sdboot_entry "$(mktemp -d)"
    [ "$status" -ne 0 ]
}

@test "systemd-boot: the new entry keeps root and options, swaps the kernel" {
    run sdboot_entry_from < "$BOOT/esp/loader/entries/arch.conf"
    [ "$output" = 'title   ChiropteraOS (linux-cachyos)
linux   /vmlinuz-linux-cachyos
initrd  /initramfs-linux-cachyos.img
options root=UUID=0a1b2c3d-1111-2222-3333-444455556666 rw quiet' ]
}

@test "systemd-boot: loader.conf default is replaced, other lines kept" {
    run edit_loader_conf < "$BOOT/esp/loader/loader.conf"
    [ "$output" = 'timeout 3
default linux-cachyos.conf
editor no' ]
}

@test "systemd-boot: loader.conf without a default gets one" {
    run edit_loader_conf <<<'timeout 3'
    [ "$output" = 'timeout 3
default linux-cachyos.conf' ]
}
