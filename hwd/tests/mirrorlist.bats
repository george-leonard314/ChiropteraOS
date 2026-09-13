#!/usr/bin/env bats
# Taking cdn77.cachyos.org out of the CachyOS mirrorlists.

setup() {
    source "$BATS_TEST_DIRNAME/../chiroptera-hwd"
    FIX="$BATS_TEST_DIRNAME/fixtures/mirrorlist"
    WORK=$(mktemp -d)
}

teardown() {
    rm -rf "$WORK"
}

@test "cdn77 servers are commented out, everything else is kept" {
    run without_cdn_mirror < "$FIX/cachyos-v3-mirrorlist"
    [ "$status" -eq 0 ]
    diff -u "$FIX/cachyos-v3-mirrorlist.expected" <(printf '%s\n' "$output")
}

@test "a second run over its own output changes nothing" {
    first=$(without_cdn_mirror < "$FIX/cachyos-v3-mirrorlist")
    second=$(without_cdn_mirror <<<"$first")
    [ "$first" = "$second" ]
}

@test "dry run names each mirrorlist it will edit, before the upgrade" {
    mkdir -p "$WORK/root/etc/default" "$WORK/root/boot/grub"
    cp "$BATS_TEST_DIRNAME/fixtures/pacman-conf/blackarch.conf" "$WORK/root/etc/pacman.conf"
    cp "$BATS_TEST_DIRNAME/fixtures/boot/default-grub" "$WORK/root/etc/default/grub"
    touch "$WORK/root/boot/grub/grub.cfg"
    run env HWD_ROOT="$WORK/root" HWD_VIRT=none \
        HWD_LDSO_HELP="$BATS_TEST_DIRNAME/fixtures/laptop-zen2/ldso-help" \
        HWD_CPUINFO="$BATS_TEST_DIRNAME/fixtures/laptop-zen2/cpuinfo" \
        "$BATS_TEST_DIRNAME/../chiroptera-hwd" apply --dry-run
    [ "$status" -eq 0 ]
    grep -qF "+ comment out cdn77.cachyos.org in $WORK/root/etc/pacman.d/cachyos-v3-mirrorlist" <<<"$output"
    grep -qF "+ comment out cdn77.cachyos.org in $WORK/root/etc/pacman.d/cachyos-mirrorlist" <<<"$output"
    note=$(grep -nF '+ comment out cdn77' <<<"$output" | head -n1 | cut -d: -f1)
    fork=$(grep -nF '+ pacman -Syy --needed cachyos/pacman' <<<"$output" | head -n1 | cut -d: -f1)
    [ "$note" -lt "$fork" ]
}

@test "an existing mirrorlist is shown as a diff in a dry run and left unchanged" {
    DRY_RUN=1
    cp "$FIX/cachyos-v3-mirrorlist" "$WORK/list"
    without_cdn_mirror < "$WORK/list" > "$WORK/new"
    run replace_file "$WORK/list" "$WORK/new"
    grep -qx '+#Server = https://cdn77.cachyos.org/repo/$arch_v3/$repo' <<<"$output"
    cmp -s "$FIX/cachyos-v3-mirrorlist" "$WORK/list"
}
