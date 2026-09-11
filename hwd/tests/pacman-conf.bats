#!/usr/bin/env bats
# Inserting the CachyOS sections into pacman.conf. The edit is a pure
# stdin-to-stdout function, so every case is an input file and the exact
# expected output.

setup() {
    source "$BATS_TEST_DIRNAME/../chiroptera-hwd"
    CONF="$BATS_TEST_DIRNAME/fixtures/pacman-conf"
}

expect_edit() {  # input level expected
    run edit_pacman_conf "$2" < "$CONF/$1.conf"
    [ "$status" -eq 0 ]
    diff -u "$CONF/$3.expected" <(printf '%s\n' "$output")
}

@test "stock Arch file, v3: four sections directly above [core]" {
    expect_edit stock v3 stock.v3
}

@test "stock Arch file, znver4: znver4 sections use the v4 mirrorlist" {
    expect_edit stock znver4 stock.znver4
}

@test "stock Arch file, baseline: [cachyos] alone" {
    expect_edit stock baseline stock.baseline
}

@test "[blackarch] below [multilib] stays where it is" {
    expect_edit blackarch v3 blackarch.v3
}

@test "[chiroptera] above [core] stays above the CachyOS sections" {
    expect_edit chiroptera v3 chiroptera.v3
}

@test "a second run over its own output changes nothing" {
    first=$(edit_pacman_conf v3 < "$CONF/stock.conf")
    second=$(edit_pacman_conf v3 <<<"$first")
    [ "$first" = "$second" ]
}

@test "an explicit Architecture list becomes auto" {
    run edit_pacman_conf v3 < "$CONF/arch-explicit.conf"
    [ "$status" -eq 0 ]
    grep -qx 'Architecture = auto' <<<"$output"
    ! grep -q 'x86_64_v3' <<<"$output"
}

@test "a file without [core] is refused" {
    run edit_pacman_conf v3 < "$CONF/no-core.conf"
    [ "$status" -eq 3 ]
}

@test "a file with [core] but no [options] section is refused" {
    run edit_pacman_conf v3 < "$CONF/no-options.conf"
    [ "$status" -eq 4 ]
}

@test "repo_block v4 names every section with its mirrorlist" {
    run repo_block v4
    [ "$output" = "[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-core-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-extra-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist" ]
}

@test "a file with no Architecture line gets one directly after [options]" {
    run edit_pacman_conf v3 < "$CONF/no-arch.conf"
    [ "$status" -eq 0 ]
    [ "$(sed -n 2p <<<"$output")" = "Architecture = auto" ]
    [ "$(grep -c '^Architecture' <<<"$output")" -eq 1 ]
    second=$(edit_pacman_conf v3 <<<"$output")
    [ "$output" = "$second" ]
}
