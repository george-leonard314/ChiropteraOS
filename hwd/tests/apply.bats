#!/usr/bin/env bats
# apply's file handling and its dry run against a laptop-shaped root. Nothing
# here runs pacman: the real transaction is ci/hwd-apply-test.sh's job.

setup() {
    HWD="$BATS_TEST_DIRNAME/../chiroptera-hwd"
    FIX="$BATS_TEST_DIRNAME/fixtures"
    WORK=$(mktemp -d)
}

teardown() {
    rm -rf "$WORK"
}

@test "replace_file backs up, writes, and skips identical content" {
    source "$HWD"
    DRY_RUN=0 STAMP=20260911-120000
    printf 'old\n' > "$WORK/f"
    chmod 600 "$WORK/f"
    printf 'new\n' > "$WORK/new"
    replace_file "$WORK/f" "$WORK/new"
    [ "$(cat "$WORK/f")" = new ]
    [ "$(cat "$WORK/f.hwd-20260911-120000")" = old ]
    [ "$(stat -c %a "$WORK/f")" = 600 ]
    [ ! -e "$WORK/f.hwd-new" ]

    STAMP=20260911-130000
    replace_file "$WORK/f" "$WORK/new"
    [ ! -e "$WORK/f.hwd-20260911-130000" ]
}

@test "replace_file creates a missing file without a backup" {
    source "$HWD"
    DRY_RUN=0 STAMP=20260911-120000
    printf 'entry\n' > "$WORK/new"
    replace_file "$WORK/created" "$WORK/new"
    [ "$(cat "$WORK/created")" = entry ]
    [ -z "$(ls "$WORK" | grep hwd-)" ]
}

laptop_root() {
    mkdir -p "$WORK/root/etc/default" "$WORK/root/boot/grub"
    cp "$FIX/pacman-conf/blackarch.conf" "$WORK/root/etc/pacman.conf"
    cp "$FIX/boot/default-grub" "$WORK/root/etc/default/grub"
    touch "$WORK/root/boot/grub/grub.cfg"
}

dry_run_laptop() {  # extra apply args
    HWD_ROOT="$WORK/root" HWD_VIRT=none \
        HWD_LDSO_HELP="$FIX/laptop-zen2/ldso-help" HWD_CPUINFO="$FIX/laptop-zen2/cpuinfo" \
        "$HWD" apply --dry-run "$@"
}

line_of() {  # fixed-string -> first line number in $output
    grep -nF -- "$1" <<<"$output" | head -n1 | cut -d: -f1
}

@test "dry run on the laptop: steps in order, diffs shown, nothing written" {
    laptop_root
    before=$(cat "$WORK/root/etc/pacman.conf" "$WORK/root/etc/default/grub" | sha256sum)

    run dry_run_laptop
    [ "$status" -eq 0 ]

    grep -qF '+ pacman-key --init' <<<"$output"
    grep -qF '+ pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com' <<<"$output"
    grep -qF 'cachyos-keyring cachyos-v3-mirrorlist cachyos-mirrorlist' <<<"$output"
    grep -qx '+\[cachyos-v3\]' <<<"$output"
    grep -qx '+GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"' <<<"$output"
    grep -qF 'chwd is not installed yet' <<<"$output"
    grep -qF 'dry run complete; nothing was changed' <<<"$output"
    [ "$(grep -c 'done. Reboot' <<<"$output")" -eq 0 ]

    init=$(line_of '+ pacman-key --init')
    keys=$(line_of '+ pacman-key --recv-keys')
    conf=$(line_of '+[cachyos-v3]')
    fork=$(line_of '+ pacman -Syy --needed cachyos/pacman')
    upgrade=$(line_of '+ pacman -Syu')
    pkgs=$(line_of '+ pacman -S --needed linux-cachyos linux-cachyos-headers amd-ucode')
    chwd=$(line_of '+ chwd -a')
    grub=$(line_of '+GRUB_TOP_LEVEL=')
    mkconfig=$(line_of '+ grub-mkconfig -o /boot/grub/grub.cfg')
    [ "$init" -lt "$keys" ]
    [ "$keys" -lt "$conf" ]
    [ "$conf" -lt "$fork" ]
    [ "$fork" -lt "$upgrade" ]
    [ "$upgrade" -lt "$pkgs" ]
    [ "$pkgs" -lt "$chwd" ]
    [ "$chwd" -lt "$grub" ]
    [ "$grub" -lt "$mkconfig" ]

    after=$(cat "$WORK/root/etc/pacman.conf" "$WORK/root/etc/default/grub" | sha256sum)
    [ "$before" = "$after" ]
    [ -z "$(find "$WORK/root" -name '*.hwd-*')" ]
}

@test "without --yes pacman is interactive; with --yes it is not" {
    laptop_root
    run dry_run_laptop
    [ "$(grep -cF -- '--noconfirm' <<<"$output")" -eq 0 ]
    run dry_run_laptop --yes
    grep -qF '+ pacman --noconfirm -Syu' <<<"$output"
}

@test "dry run on systemd-boot shows the new entry and the loader default" {
    mkdir -p "$WORK/root/etc"
    cp "$FIX/pacman-conf/stock.conf" "$WORK/root/etc/pacman.conf"
    cp -r "$FIX/boot/esp" "$WORK/root/boot"
    run env HWD_ROOT="$WORK/root" HWD_VIRT=none \
        HWD_LDSO_HELP="$FIX/zen4-desktop/ldso-help" HWD_CPUINFO="$FIX/zen4-desktop/cpuinfo" \
        "$HWD" apply --dry-run
    [ "$status" -eq 0 ]
    grep -qx '+linux   /vmlinuz-linux-cachyos' <<<"$output"
    grep -qx '+default linux-cachyos.conf' <<<"$output"
    [ ! -e "$WORK/root/boot/loader/entries/linux-cachyos.conf" ]
}

@test "unknown bootloader is reported, not guessed" {
    laptop_root
    rm "$WORK/root/boot/grub/grub.cfg"
    run dry_run_laptop
    [ "$status" -eq 0 ]
    grep -qF 'bootloader not recognised' <<<"$output"
    ! grep -qF 'grub-mkconfig' <<<"$output"
}

@test "a pacman.conf without [core] stops apply at step 1" {
    laptop_root
    cp "$FIX/pacman-conf/no-core.conf" "$WORK/root/etc/pacman.conf"
    run dry_run_laptop
    [ "$status" -ne 0 ]
    grep -qF 'no [core] section' <<<"$output"
    grep -qF 'step 1/5' <<<"$output"
    ! grep -qF 'cachyos/pacman' <<<"$output"
}

@test "unknown apply option is refused" {
    run "$HWD" apply --frobnicate
    [ "$status" -ne 0 ]
    grep -qF 'unknown option: --frobnicate' <<<"$output"
}
