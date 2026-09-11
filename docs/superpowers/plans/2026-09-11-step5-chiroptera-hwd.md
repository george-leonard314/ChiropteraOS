# Step 5: chiroptera-hwd Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `chiroptera-hwd`, a bash script whose `apply` turns a stock Arch install into a CachyOS install matched to its CPU, with `chwd` choosing graphics drivers and a stock-kernel fallback left bootable; package it, test it in CI, then apply it to the author's laptop once the author approves the dry run.

**Architecture:** One script, `hwd/chiroptera-hwd`, with `detect` (prints a JSON plan), `apply` and `apply --dry-run`. Every hardware input is replaceable through an `HWD_*` variable and every path is prefixed by `HWD_ROOT`, so bats tests drive it with captured machines. The script can be sourced; its `main` runs only when executed, so tests call its functions directly. A second CI job runs `apply` for real in a throwaway Arch container.

**Tech Stack:** bash, gawk, diffutils, bats 1.14 (Arch `extra`), pacman/makepkg, Docker, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-11-chiroptera-hwd-and-cachyos-design.md`

## Global Constraints

- `chiroptera-hwd` must not depend on `chwd` or anything else in `[cachyos]`: hwd is what adds that repository.
- Never removes stock `linux` or `nvidia-open`. Never edits or deletes a file it did not write, apart from `/etc/pacman.conf`, `/etc/default/grub` and systemd-boot's `loader.conf`, each backed up to `<file>.hwd-<YYYYmmdd-HHMMSS>` before the first change.
- Writes no Hyprland or session environment.
- CachyOS signing key `F3B607488DB35A47`, fetched from `keyserver.ubuntu.com`. Bootstrap server `https://mirror.cachyos.org/repo/$arch/$repo`.
- Level to sections, in this order, inserted directly above `[core]`:
  - `baseline`: `[cachyos]`
  - `v3`: `[cachyos-v3]` `[cachyos-core-v3]` `[cachyos-extra-v3]` `[cachyos]`
  - `v4`: `[cachyos-v4]` `[cachyos-core-v4]` `[cachyos-extra-v4]` `[cachyos]`
  - `znver4`: `[cachyos-znver4]` `[cachyos-core-znver4]` `[cachyos-extra-znver4]` `[cachyos]`
- Mirrorlists: `[cachyos]` uses `cachyos-mirrorlist`; `*-v3` sections use `cachyos-v3-mirrorlist`; `*-v4` and `*-znver4` sections use `cachyos-v4-mirrorlist`. Each file is `/etc/pacman.d/<name>` and is installed by the package of the same name.
- Package set: `linux-cachyos linux-cachyos-headers <microcode> cachyos-settings cachyos-ananicy-rules scx-scheds scx-tools chwd`, plus `qemu-guest-agent` for `kvm`/`qemu` or `virtualbox-guest-utils` for `oracle`.
- `chiroptera-hwd` package: version `0.1.0`, `arch=('any')`, license MIT, maintainer line `# Maintainer: George (ChiropteraOS)`.
- Sudo has no terminal in this environment. Any step that needs root on the laptop is handed to the author as a command to run.
- Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019bmStvMZ5Qh4JVo1rAi3GC
  ```

## Refinements over the spec

Settled while planning, from reading `chwd`'s source and CachyOS's `cachyos-repo.sh`. Task 7 writes them back into the spec.

1. **`detect` reports `"gpu": "chwd"`**, not a profile name. `chwd --list` prints a human table whose layout is not an interface; `apply --dry-run` prints it verbatim for review instead. The `HWD_CHWD_PROFILE` override is dropped.
2. **Keyring and mirrorlists are bootstrapped through a throwaway pacman config** pointing `[cachyos]` at the mirror directly, instead of version-pinned package URLs like `cachyos-keyring-20240331-1-any.pkg.tar.zst`, which go stale. It still runs before `pacman.conf` is edited, so an offline machine fails with the file untouched.
3. **`apply --yes`** passes `--noconfirm` to pacman. Calamares and CI use it; the laptop run does not.
4. **Dependencies are `bash gawk diffutils pciutils systemd`.** `util-linux` was listed for `lscpu`, which detection no longer uses; `gawk` and `diffutils` are what the script calls.
5. **The systemd-boot entry is copied from the entry whose initrd is `/initramfs-linux.img`**, which singles out the stock kernel's normal entry from its fallback.
6. **Undo restores the oldest `pacman.conf` backup, not the newest.** The oldest is the file before hwd first ran; re-runs make no backup when nothing changes, but any later change would make the newest an intermediate state. Undo also follows `cachyos-repo.sh --remove`'s order: `-Suuy`, `core/pacman`, then reinstall all native packages.

---

## File Structure

```
hwd/
  chiroptera-hwd                  the script: detection, edits, apply
  tests/
    detect.bats                   CPU level, microcode, JSON plan
    pacman-conf.bats              repository insertion
    boot.bats                     GRUB and systemd-boot edits
    apply.bats                    replace_file, apply --dry-run
    fixtures/
      laptop-zen2/{ldso-help,cpuinfo,expected.json}
      zen4-desktop/{ldso-help,cpuinfo}
      intel-v3-laptop/{ldso-help,cpuinfo}
      intel-v4-server/{ldso-help,cpuinfo}
      pre-v3/{ldso-help,cpuinfo}
      pacman-conf/{stock,blackarch,chiroptera,arch-explicit,no-core}.conf
      pacman-conf/{stock.v3,stock.znver4,stock.baseline,blackarch.v3,chiroptera.v3}.expected
      boot/default-grub
      boot/esp/loader/loader.conf
      boot/esp/loader/entries/{arch,arch-fallback}.conf
pkgs/chiroptera-hwd/
  PKGBUILD
  chiroptera-hwd -> ../../hwd/chiroptera-hwd
ci/test-hwd.sh                    bats runner (CI and local-in-docker)
ci/hwd-apply-test.sh              real apply in a throwaway container
ci/build-repo.sh                  modified: builds chiroptera-hwd
ci/smoke-test.sh                  modified: chiroptera-hwd resolves alone
.github/workflows/packages.yml    modified: hwd-tests and hwd-apply jobs
docs/hwd.md                       usage, what apply changes, undo
docs/STATUS.md                    modified: step 5 progress
```

Running the tests locally: bats is not installed on the laptop and there is no
sudo, so the suite always runs in a container:

```bash
docker run --rm -v "$PWD:/work:ro" -w /work archlinux:base-devel \
    bash -c 'pacman -Sy --needed --noconfirm bats >/dev/null && ci/test-hwd.sh'
```

Referred to below as **the test command**. To run one file, append its path:
`... && ci/test-hwd.sh hwd/tests/detect.bats'`.

---

### Task 1: Detection and the JSON plan

**Files:**
- Create: `hwd/chiroptera-hwd`
- Create: `ci/test-hwd.sh`
- Create: `hwd/tests/detect.bats`
- Create: `hwd/tests/fixtures/{laptop-zen2,zen4-desktop,intel-v3-laptop,intel-v4-server,pre-v3}/*`

**Interfaces:**
- Produces: `detect_level` → prints `baseline|v3|v4|znver4`; `detect_microcode` → `amd-ucode|intel-ucode|` (empty); `detect_virt` → `systemd-detect-virt` value, `none` when absent; `detect_bootloader` → `grub|systemd-boot|unknown`; `sdboot_esp` → prints `$HWD_ROOT<esp>` or returns 1; `repos_for LEVEL` → space-separated section names; `mirrorlist_for_repo REPO` → mirrorlist package name; `mirrorlists_for LEVEL` → one name per line, deduplicated, in first-use order; `packages_for MICROCODE VIRT` → one package per line; `cmd_detect` → JSON on stdout; `die MSG`.
- Environment: `HWD_LDSO_HELP` (file), `HWD_CPUINFO` (file), `HWD_VIRT` (value), `HWD_BOOTLOADER` (value), `HWD_ROOT` (path prefix, default empty).

- [ ] **Step 1: Create the test runner**

`ci/test-hwd.sh`:

```bash
#!/usr/bin/env bash
# Run chiroptera-hwd's bats suite.
#
# CI runs this inside the Arch container. Locally bats is not assumed, so run
# it through docker -- see docs/hwd.md. Pass test files to run a subset.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

bash -n "$repo_root/hwd/chiroptera-hwd"

if (($#)); then
    exec bats "$@"
fi
exec bats "$repo_root/hwd/tests"
```

Run: `chmod +x ci/test-hwd.sh`

- [ ] **Step 2: Create the fixtures**

`hwd/tests/fixtures/laptop-zen2/ldso-help` (captured from the author's laptop, header trimmed):

```
This program interpreter self-identifies as: /usr/lib/ld-linux-x86-64.so.2

Shared library search path:
  (libraries located via /etc/ld.so.cache)
  /usr/lib (system search path)

Subdirectories of glibc-hwcaps directories, in priority order:
  x86-64-v4
  x86-64-v3 (supported, searched)
  x86-64-v2 (supported, searched)
```

`hwd/tests/fixtures/laptop-zen2/cpuinfo`:

```
processor	: 0
vendor_id	: AuthenticAMD
cpu family	: 23
model		: 96
model name	: AMD Ryzen 7 4800H with Radeon Graphics
```

`hwd/tests/fixtures/laptop-zen2/expected.json`:

```json
{
  "level": "v3",
  "repos": ["cachyos-v3", "cachyos-core-v3", "cachyos-extra-v3", "cachyos"],
  "packages": ["linux-cachyos", "linux-cachyos-headers", "amd-ucode", "cachyos-settings", "cachyos-ananicy-rules", "scx-scheds", "scx-tools", "chwd"],
  "bootloader": "grub",
  "virt": "none",
  "gpu": "chwd"
}
```

`hwd/tests/fixtures/zen4-desktop/ldso-help`:

```
Subdirectories of glibc-hwcaps directories, in priority order:
  x86-64-v4 (supported, searched)
  x86-64-v3 (supported, searched)
  x86-64-v2 (supported, searched)
```

`hwd/tests/fixtures/zen4-desktop/cpuinfo`:

```
processor	: 0
vendor_id	: AuthenticAMD
cpu family	: 25
model		: 97
model name	: AMD Ryzen 9 7950X 16-Core Processor
```

`hwd/tests/fixtures/intel-v3-laptop/ldso-help` — v4 listed but not supported, as on Alder Lake with AVX-512 fused off:

```
Subdirectories of glibc-hwcaps directories, in priority order:
  x86-64-v4
  x86-64-v3 (supported, searched)
  x86-64-v2 (supported, searched)
```

`hwd/tests/fixtures/intel-v3-laptop/cpuinfo`:

```
processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 154
model name	: 12th Gen Intel(R) Core(TM) i7-1260P
```

`hwd/tests/fixtures/intel-v4-server/ldso-help`:

```
Subdirectories of glibc-hwcaps directories, in priority order:
  x86-64-v4 (supported, searched)
  x86-64-v3 (supported, searched)
  x86-64-v2 (supported, searched)
```

`hwd/tests/fixtures/intel-v4-server/cpuinfo`:

```
processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 106
model name	: Intel(R) Xeon(R) Gold 6338 CPU @ 2.00GHz
```

`hwd/tests/fixtures/pre-v3/ldso-help`:

```
Subdirectories of glibc-hwcaps directories, in priority order:
  x86-64-v4
  x86-64-v3
  x86-64-v2 (supported, searched)
```

`hwd/tests/fixtures/pre-v3/cpuinfo`:

```
processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 58
model name	: Intel(R) Core(TM) i5-3570 CPU @ 3.40GHz
```

- [ ] **Step 3: Write the failing tests**

`hwd/tests/detect.bats`:

```bash
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
```

- [ ] **Step 4: Run the tests to verify they fail**

Run the test command with `hwd/tests/detect.bats`.
Expected: `bash -n` fails with `No such file or directory` for `hwd/chiroptera-hwd`.

- [ ] **Step 5: Write the detection half of the script**

`hwd/chiroptera-hwd`:

```bash
#!/usr/bin/env bash
# chiroptera-hwd -- match an Arch install to its hardware.
#
#   chiroptera-hwd detect                 print the plan as JSON; changes nothing
#   chiroptera-hwd apply [--yes]          carry the plan out (root)
#   chiroptera-hwd apply --dry-run        print what apply would run and write
#
# CPU level, CachyOS repositories, kernel, microcode and the boot entry are
# handled here. Graphics drivers are chwd's job: its profiles track which
# NVIDIA generation needs which driver, and a copy of that table here would
# only learn about new hardware by breaking on it.
#
# Every hardware input can be replaced through an HWD_* variable and every
# path is prefixed by HWD_ROOT, so the tests run against captured machines
# without touching this one. Sourcing the file defines the functions only.

HWD_ROOT=${HWD_ROOT:-}

die() { printf 'chiroptera-hwd: %s\n' "$1" >&2; exit 1; }

usage() {
    cat <<'EOF'
usage: chiroptera-hwd detect
       chiroptera-hwd apply [--yes] [--dry-run]
EOF
}

# ---- detection ---------------------------------------------------------------

ldso_help() {
    if [[ -n ${HWD_LDSO_HELP:-} ]]; then
        cat "$HWD_LDSO_HELP"
    else
        /lib/ld-linux-x86-64.so.2 --help
    fi
}

# The loader marks a level "(supported, searched)" only when the CPU has every
# feature the level requires -- AVX-512 included for v4, so Intel parts with
# AVX-512 fused off correctly stop at v3.
isa_supported() {  # level help-text
    grep -qF "$1 (supported, searched)" <<<"$2"
}

cpu_vendor() {
    awk -F': *' '/^vendor_id/ { print $2; exit }' "${HWD_CPUINFO:-/proc/cpuinfo}"
}

detect_level() {
    local help vendor
    help=$(ldso_help)
    vendor=$(cpu_vendor)
    if isa_supported x86-64-v4 "$help"; then
        # Zen 4 and Zen 5 are the only AMD CPUs with AVX-512. CachyOS's own
        # script asks gcc instead, which a base install does not have.
        if [[ $vendor == AuthenticAMD ]]; then echo znver4; else echo v4; fi
    elif isa_supported x86-64-v3 "$help"; then
        echo v3
    else
        echo baseline
    fi
}

detect_microcode() {
    case $(cpu_vendor) in
        AuthenticAMD) echo amd-ucode ;;
        GenuineIntel) echo intel-ucode ;;
    esac
}

detect_virt() {
    if [[ -n ${HWD_VIRT:-} ]]; then
        echo "$HWD_VIRT"
        return
    fi
    local virt
    # Prints "none" and exits 1 on bare metal.
    virt=$(systemd-detect-virt 2>/dev/null) || true
    echo "${virt:-none}"
}

sdboot_esp() {
    local esp
    for esp in /boot /efi /boot/efi; do
        if [[ -f $HWD_ROOT$esp/loader/loader.conf ]]; then
            echo "$HWD_ROOT$esp"
            return 0
        fi
    done
    return 1
}

detect_bootloader() {
    if [[ -n ${HWD_BOOTLOADER:-} ]]; then
        echo "$HWD_BOOTLOADER"
    elif [[ -f $HWD_ROOT/boot/grub/grub.cfg ]]; then
        echo grub
    elif sdboot_esp >/dev/null; then
        echo systemd-boot
    else
        echo unknown
    fi
}

# ---- the plan ----------------------------------------------------------------

repos_for() {  # level
    case $1 in
        baseline) echo cachyos ;;
        v3)       echo cachyos-v3 cachyos-core-v3 cachyos-extra-v3 cachyos ;;
        v4)       echo cachyos-v4 cachyos-core-v4 cachyos-extra-v4 cachyos ;;
        znver4)   echo cachyos-znver4 cachyos-core-znver4 cachyos-extra-znver4 cachyos ;;
        *)        die "unknown level: $1" ;;
    esac
}

# v4 and znver4 share a mirrorlist: both live under the mirror's x86_64_v4 tree.
mirrorlist_for_repo() {  # repo
    case $1 in
        cachyos) echo cachyos-mirrorlist ;;
        *-v3)    echo cachyos-v3-mirrorlist ;;
        *)       echo cachyos-v4-mirrorlist ;;
    esac
}

mirrorlists_for() {  # level
    local repo
    for repo in $(repos_for "$1"); do
        mirrorlist_for_repo "$repo"
    done | awk '!seen[$0]++'
}

packages_for() {  # microcode virt
    local -a pkgs=(linux-cachyos linux-cachyos-headers)
    if [[ -n $1 ]]; then pkgs+=("$1"); fi
    pkgs+=(cachyos-settings cachyos-ananicy-rules scx-scheds scx-tools chwd)
    case $2 in
        kvm|qemu) pkgs+=(qemu-guest-agent) ;;
        oracle)   pkgs+=(virtualbox-guest-utils) ;;
    esac
    printf '%s\n' "${pkgs[@]}"
}

json_array() {  # words...
    local out='' word
    for word in "$@"; do
        out+="${out:+, }\"$word\""
    done
    printf '[%s]' "$out"
}

cmd_detect() {
    local level microcode virt bootloader
    level=$(detect_level)
    microcode=$(detect_microcode)
    virt=$(detect_virt)
    bootloader=$(detect_bootloader)

    local -a repos pkgs
    read -r -a repos <<<"$(repos_for "$level")"
    mapfile -t pkgs < <(packages_for "$microcode" "$virt")

    printf '{\n'
    printf '  "level": "%s",\n' "$level"
    printf '  "repos": %s,\n' "$(json_array "${repos[@]}")"
    printf '  "packages": %s,\n' "$(json_array "${pkgs[@]}")"
    printf '  "bootloader": "%s",\n' "$bootloader"
    printf '  "virt": "%s",\n' "$virt"
    printf '  "gpu": "chwd"\n'
    printf '}\n'
}

# ---- entry point -------------------------------------------------------------

main() {
    case ${1:-} in
        detect) shift; cmd_detect "$@" ;;
        *)      usage >&2; exit 2 ;;
    esac
}

# Strict mode only when executed: bats sources this file, and set -u would
# leak into the test harness.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -euo pipefail
    main "$@"
fi
```

Run: `chmod +x hwd/chiroptera-hwd`

- [ ] **Step 6: Run the tests to verify they pass**

Run the test command with `hwd/tests/detect.bats`.
Expected: `10 tests, 0 failures`.

- [ ] **Step 7: Check the real laptop by hand**

Run: `./hwd/chiroptera-hwd detect`
Expected: identical to `hwd/tests/fixtures/laptop-zen2/expected.json`. If it is not, the fixture misrepresents the reference machine; fix the fixture, not the script.

- [ ] **Step 8: Commit**

```bash
git add hwd/ ci/test-hwd.sh
git commit -m "hwd: detect CPU level, microcode, bootloader and print the plan"
```

---

### Task 2: Inserting the CachyOS repositories into pacman.conf

**Files:**
- Modify: `hwd/chiroptera-hwd` (add after `packages_for`)
- Create: `hwd/tests/pacman-conf.bats`
- Create: `hwd/tests/fixtures/pacman-conf/*`

**Interfaces:**
- Consumes: `repos_for`, `mirrorlist_for_repo` from Task 1.
- Produces: `repo_block LEVEL` → section text on stdout, no trailing blank line; `edit_pacman_conf LEVEL < in > out` → edited file on stdout, exit 3 when there is no `[core]` section.

- [ ] **Step 1: Create the fixtures**

`hwd/tests/fixtures/pacman-conf/stock.conf`:

```
[options]
HoldPkg     = pacman glibc
Architecture = auto
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

#[core-testing]
#Include = /etc/pacman.d/mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist
```

`hwd/tests/fixtures/pacman-conf/stock.v3.expected`:

```
[options]
HoldPkg     = pacman glibc
Architecture = auto
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

#[core-testing]
#Include = /etc/pacman.d/mirrorlist

[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist
```

`hwd/tests/fixtures/pacman-conf/stock.znver4.expected`:

```
[options]
HoldPkg     = pacman glibc
Architecture = auto
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

#[core-testing]
#Include = /etc/pacman.d/mirrorlist

[cachyos-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-core-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-extra-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist
```

`hwd/tests/fixtures/pacman-conf/stock.baseline.expected`:

```
[options]
HoldPkg     = pacman glibc
Architecture = auto
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

#[core-testing]
#Include = /etc/pacman.d/mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist
```

`hwd/tests/fixtures/pacman-conf/blackarch.conf` — the shape of the author's laptop:

```
[options]
HoldPkg     = pacman glibc
Architecture = auto
IgnorePkg   = equicord-openasar
SigLevel    = Required DatabaseOptional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist

[blackarch]
Include = /etc/pacman.d/blackarch-mirrorlist
```

`hwd/tests/fixtures/pacman-conf/blackarch.v3.expected`:

```
[options]
HoldPkg     = pacman glibc
Architecture = auto
IgnorePkg   = equicord-openasar
SigLevel    = Required DatabaseOptional

[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist

[blackarch]
Include = /etc/pacman.d/blackarch-mirrorlist
```

`hwd/tests/fixtures/pacman-conf/chiroptera.conf`:

```
[options]
Architecture = auto
SigLevel    = Required DatabaseOptional

[chiroptera]
SigLevel = Never
Server = https://example.invalid/chiroptera

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
```

`hwd/tests/fixtures/pacman-conf/chiroptera.v3.expected`:

```
[options]
Architecture = auto
SigLevel    = Required DatabaseOptional

[chiroptera]
SigLevel = Never
Server = https://example.invalid/chiroptera

[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
```

`hwd/tests/fixtures/pacman-conf/arch-explicit.conf`:

```
[options]
Architecture = x86_64 x86_64_v3

[core]
Include = /etc/pacman.d/mirrorlist
```

`hwd/tests/fixtures/pacman-conf/no-core.conf`:

```
[options]
Architecture = auto

[extra]
Include = /etc/pacman.d/mirrorlist
```

- [ ] **Step 2: Write the failing tests**

`hwd/tests/pacman-conf.bats`:

```bash
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run the test command with `hwd/tests/pacman-conf.bats`.
Expected: 9 failures, `edit_pacman_conf: command not found` / `repo_block: command not found`.

- [ ] **Step 4: Implement**

Add to `hwd/chiroptera-hwd`, directly after `packages_for`:

```bash
# ---- pacman.conf -------------------------------------------------------------

repo_block() {  # level
    local repo first=1
    for repo in $(repos_for "$1"); do
        if (( ! first )); then echo; fi
        first=0
        printf '[%s]\nInclude = /etc/pacman.d/%s\n' "$repo" "$(mirrorlist_for_repo "$repo")"
    done
}

# Print pacman.conf with the level's sections inserted directly above [core]
# and Architecture set to auto, which the CachyOS pacman needs to accept its
# x86_64_v3/v4 packages. A [cachyos] section already present means a CachyOS
# setup exists: the sections are then left exactly as they are, which is what
# makes a second run a no-op. Exits 3 when there is no [core] to anchor on.
edit_pacman_conf() {  # level < pacman.conf
    HWD_BLOCK=$(repo_block "$1") awk '
        /^Architecture[[:space:]]*=/ { $0 = "Architecture = auto" }
        $0 == "[cachyos]" { present = 1 }
        { lines[++n] = $0 }
        END {
            for (i = 1; i <= n; i++) {
                if (!present && !done && lines[i] == "[core]") {
                    print ENVIRON["HWD_BLOCK"]
                    print ""
                    done = 1
                }
                print lines[i]
            }
            if (!present && !done) exit 3
        }'
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the test command.
Expected: `19 tests, 0 failures` (detect and pacman-conf).

- [ ] **Step 6: Commit**

```bash
git add hwd/
git commit -m "hwd: insert the CachyOS sections for the CPU level into pacman.conf"
```

---

### Task 3: Boot entry edits

**Files:**
- Modify: `hwd/chiroptera-hwd` (add after `edit_pacman_conf`)
- Create: `hwd/tests/boot.bats`
- Create: `hwd/tests/fixtures/boot/*`

**Interfaces:**
- Produces: `edit_default_grub < in > out`; `stock_sdboot_entry ESP` → path of the stock kernel's normal entry, or return 1; `sdboot_entry_from < entry > out`; `edit_loader_conf < in > out`.

- [ ] **Step 1: Create the fixtures**

`hwd/tests/fixtures/boot/default-grub` (the laptop's settings):

```
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Arch"
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_RECOVERY=true
#GRUB_TOP_LEVEL=""
```

`hwd/tests/fixtures/boot/esp/loader/loader.conf`:

```
timeout 3
default arch.conf
editor no
```

`hwd/tests/fixtures/boot/esp/loader/entries/arch.conf`:

```
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=0a1b2c3d-1111-2222-3333-444455556666 rw quiet
```

`hwd/tests/fixtures/boot/esp/loader/entries/arch-fallback.conf` — sorts before `arch.conf`, so a naive "first entry with /vmlinuz-linux" picks it:

```
title   Arch Linux (fallback initramfs)
linux   /vmlinuz-linux
initrd  /initramfs-linux-fallback.img
options root=UUID=0a1b2c3d-1111-2222-3333-444455556666 rw
```

- [ ] **Step 2: Write the failing tests**

`hwd/tests/boot.bats`:

```bash
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run the test command with `hwd/tests/boot.bats`.
Expected: 8 failures, `command not found`.

- [ ] **Step 4: Implement**

Add to `hwd/chiroptera-hwd`, directly after `edit_pacman_conf`:

```bash
# ---- boot entry --------------------------------------------------------------

# GRUB_TOP_LEVEL (GRUB 2.12+) moves the named kernel to the top of the menu, so
# GRUB_DEFAULT=0 now means linux-cachyos while stock linux stays listed below.
edit_default_grub() {  # < /etc/default/grub
    awk -v line='GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"' '
        /^#?GRUB_TOP_LEVEL=/ { if (!done) print line; done = 1; next }
        { print }
        END { if (!done) print line }'
}

# The stock kernel's normal entry, identified by its initramfs: the fallback
# entry boots the same /vmlinuz-linux and must not be the one copied.
stock_sdboot_entry() {  # esp
    local entry
    for entry in "$1"/loader/entries/*.conf; do
        if grep -qsE '^initrd[[:space:]]+/initramfs-linux\.img$' "$entry"; then
            echo "$entry"
            return 0
        fi
    done
    return 1
}

sdboot_entry_from() {  # < stock entry
    sed -E \
        -e 's|^title[[:space:]].*|title   ChiropteraOS (linux-cachyos)|' \
        -e 's|^(linux[[:space:]]+)/vmlinuz-linux$|\1/vmlinuz-linux-cachyos|' \
        -e 's|^(initrd[[:space:]]+)/initramfs-linux\.img$|\1/initramfs-linux-cachyos.img|'
}

edit_loader_conf() {  # < loader.conf
    awk '
        /^default[[:space:]]/ { if (!done) print "default linux-cachyos.conf"; done = 1; next }
        { print }
        END { if (!done) print "default linux-cachyos.conf" }'
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the test command.
Expected: `27 tests, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add hwd/
git commit -m "hwd: make linux-cachyos the default entry on GRUB and systemd-boot"
```

---

### Task 4: `apply` and `apply --dry-run`

**Files:**
- Modify: `hwd/chiroptera-hwd` (add an apply section before the entry point; extend `main`)
- Create: `hwd/tests/apply.bats`

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces: `runcmd CMD...` (prints `+ CMD` when `DRY_RUN=1`, else runs it; deliberately not named `run`, which would shadow bats's `run` in every test that sources the script); `pac ARGS...` (pacman with `--noconfirm` when `ASSUME_YES=1`); `replace_file TARGET NEWFILE` (backs up to `TARGET.hwd-$STAMP`, then writes; diff only in a dry run; no-op when identical); `cmd_apply [--yes] [--dry-run]`.
- Globals: `DRY_RUN`, `ASSUME_YES`, `STAMP`, `TMPD`, `CURRENT_STEP`.

- [ ] **Step 1: Write the failing tests**

`hwd/tests/apply.bats`:

```bash
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
    printf 'new\n' > "$WORK/new"
    replace_file "$WORK/f" "$WORK/new"
    [ "$(cat "$WORK/f")" = new ]
    [ "$(cat "$WORK/f.hwd-20260911-120000")" = old ]

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

    grep -qF '+ pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com' <<<"$output"
    grep -qF 'cachyos-keyring cachyos-v3-mirrorlist cachyos-mirrorlist' <<<"$output"
    grep -qx '+\[cachyos-v3\]' <<<"$output"
    grep -qx '+GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"' <<<"$output"

    keys=$(line_of '+ pacman-key --recv-keys')
    conf=$(line_of '+[cachyos-v3]')
    fork=$(line_of '+ pacman -Sy --needed cachyos/pacman')
    upgrade=$(line_of '+ pacman -Syu')
    pkgs=$(line_of '+ pacman -S --needed linux-cachyos linux-cachyos-headers amd-ucode')
    chwd=$(line_of '+ chwd -a')
    grub=$(line_of '+GRUB_TOP_LEVEL=')
    mkconfig=$(line_of '+ grub-mkconfig -o /boot/grub/grub.cfg')
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
    ! grep -qF -- '--noconfirm' <<<"$output"
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command with `hwd/tests/apply.bats`.
Expected: failures — `replace_file: command not found`, and `apply` prints usage with status 2.

- [ ] **Step 3: Implement**

Add to `hwd/chiroptera-hwd`, directly before the `# ---- entry point` line:

```bash
# ---- apply -------------------------------------------------------------------

CACHYOS_KEY=F3B607488DB35A47
CACHYOS_BOOTSTRAP_SERVER='https://mirror.cachyos.org/repo/$arch/$repo'
DRY_RUN=0
ASSUME_YES=0
STAMP=
TMPD=
CURRENT_STEP=

# Not named `run`: bats defines run(), and the tests source this file.
runcmd() {
    if (( DRY_RUN )); then
        printf '+ %s\n' "$*"
    else
        "$@"
    fi
}

pac() {
    local -a flags=()
    if (( ASSUME_YES )); then flags+=(--noconfirm); fi
    runcmd pacman "${flags[@]}" "$@"
}

step() {
    CURRENT_STEP=$1
    printf '\n:: step %s\n' "$1"
}

# Put NEWFILE's content in TARGET, keeping a timestamped backup of what was
# there. Identical content is left alone, so re-runs create no backups. A dry
# run shows the change as a diff instead.
replace_file() {  # target newfile
    local old=$1
    if [[ ! -e $1 ]]; then old=/dev/null; fi
    if (( DRY_RUN )); then
        diff -u --label "$1" --label "$1 (after)" "$old" "$2" || true
        return 0
    fi
    if cmp -s "$old" "$2"; then return 0; fi
    if [[ -e $1 ]]; then cp -a "$1" "$1.hwd-$STAMP"; fi
    cat "$2" > "$1"
}

step_repositories() {  # level
    local conf=$HWD_ROOT/etc/pacman.conf
    local -a mirrorlists
    mapfile -t mirrorlists < <(mirrorlists_for "$1")

    runcmd pacman-key --recv-keys "$CACHYOS_KEY" --keyserver keyserver.ubuntu.com
    runcmd pacman-key --lsign-key "$CACHYOS_KEY"

    # The mirrorlists come from [cachyos] itself, which pacman.conf cannot name
    # until they exist. A throwaway config pointing straight at the mirror
    # breaks the loop. It runs before pacman.conf is touched, so an offline
    # machine fails here with the file unchanged.
    local boot=$TMPD/bootstrap.conf
    cat > "$boot" <<EOF
[options]
Architecture = auto
SigLevel = Required DatabaseOptional

[cachyos]
Server = $CACHYOS_BOOTSTRAP_SERVER
EOF
    pac --config "$boot" -Sy --needed cachyos-keyring "${mirrorlists[@]}"

    local new=$TMPD/pacman.conf
    edit_pacman_conf "$1" < "$conf" > "$new" || die "no [core] section in $conf"
    replace_file "$conf" "$new"
}

step_graphics() {
    # For review only: the table chwd prints is for people, not parsing.
    if (( DRY_RUN )) && command -v chwd >/dev/null; then
        chwd --list || true
    fi
    runcmd chwd -a
}

step_boot() {  # bootloader
    local new=$TMPD/boot
    case $1 in
        grub)
            edit_default_grub < "$HWD_ROOT/etc/default/grub" > "$new"
            replace_file "$HWD_ROOT/etc/default/grub" "$new"
            runcmd grub-mkconfig -o /boot/grub/grub.cfg
            ;;
        systemd-boot)
            local esp stock
            esp=$(sdboot_esp) || die "systemd-boot detected but no loader.conf found"
            stock=$(stock_sdboot_entry "$esp") \
                || die "no entry with initrd /initramfs-linux.img in $esp/loader/entries to copy"
            sdboot_entry_from < "$stock" > "$new"
            replace_file "$esp/loader/entries/linux-cachyos.conf" "$new"
            edit_loader_conf < "$esp/loader/loader.conf" > "$new.loader"
            replace_file "$esp/loader/loader.conf" "$new.loader"
            ;;
        *)
            echo "bootloader not recognised: make linux-cachyos the default entry by hand"
            ;;
    esac
}

cmd_apply() {
    while (($#)); do
        case $1 in
            --dry-run) DRY_RUN=1 ;;
            --yes)     ASSUME_YES=1 ;;
            *)         die "unknown option: $1" ;;
        esac
        shift
    done
    if (( ! DRY_RUN )) && [[ $EUID -ne 0 ]]; then
        die "apply must run as root (or pass --dry-run)"
    fi

    STAMP=$(date +%Y%m%d-%H%M%S)
    TMPD=$(mktemp -d)
    # A failed step is fixed and re-run, never rolled back: every step is
    # idempotent, so naming where it stopped is all the recovery needed.
    trap 'rc=$?; rm -rf "$TMPD"
          if (( rc )) && [[ -n $CURRENT_STEP ]]; then
              printf "chiroptera-hwd: stopped at step %s; fix the cause and run apply again\n" "$CURRENT_STEP" >&2
          fi' EXIT

    local level microcode virt bootloader
    level=$(detect_level)
    microcode=$(detect_microcode)
    virt=$(detect_virt)
    bootloader=$(detect_bootloader)
    local -a pkgs
    mapfile -t pkgs < <(packages_for "$microcode" "$virt")

    step "1/5: CachyOS repositories ($level)"
    step_repositories "$level"

    # Arch's pacman rejects x86_64_v3/v4 packages, so it cannot perform the
    # upgrade itself. The fork's own package is plain x86_64 and installs fine.
    step "2/5: CachyOS pacman, then the upgrade"
    pac -Sy --needed cachyos/pacman
    pac -Syu

    step "3/5: kernel and CachyOS packages"
    pac -S --needed "${pkgs[@]}"

    # After step 3 on purpose: chwd picks the prebuilt NVIDIA module only for
    # kernels it can already see installed.
    step "4/5: graphics drivers (chwd)"
    step_graphics

    step "5/5: boot entry ($bootloader)"
    step_boot "$bootloader"

    CURRENT_STEP=
    printf '\nchiroptera-hwd: done. Reboot into linux-cachyos; stock linux remains in the boot menu.\n'
}
```

Replace `main` with:

```bash
main() {
    case ${1:-} in
        detect) shift; cmd_detect "$@" ;;
        apply)  shift; cmd_apply "$@" ;;
        *)      usage >&2; exit 2 ;;
    esac
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command.
Expected: `35 tests, 0 failures`.

- [ ] **Step 5: Dry-run the real laptop**

Run: `./hwd/chiroptera-hwd apply --dry-run`
Expected: exit 0; the pacman.conf diff inserts the four v3 sections above `[core]` with `[blackarch]` untouched; the `/etc/default/grub` diff adds only `GRUB_TOP_LEVEL`; no `.hwd-*` file appears under `/etc`. This output is what Task 8 shows the author.

- [ ] **Step 6: Commit**

```bash
git add hwd/
git commit -m "hwd: apply the plan in five idempotent steps, with a dry run"
```

---

### Task 5: Package `chiroptera-hwd` and put it in the repository build

**Files:**
- Create: `pkgs/chiroptera-hwd/PKGBUILD`
- Create: `pkgs/chiroptera-hwd/chiroptera-hwd` (symlink)
- Modify: `ci/build-repo.sh:18-35`
- Modify: `ci/smoke-test.sh` (after the `for required in ...` loop)

**Interfaces:**
- Produces: package `chiroptera-hwd-0.1.0-1-any.pkg.tar.zst` installing `/usr/bin/chiroptera-hwd`.

- [ ] **Step 1: Write the PKGBUILD and the source link**

`pkgs/chiroptera-hwd/PKGBUILD`:

```bash
# Maintainer: George (ChiropteraOS)

pkgname=chiroptera-hwd
pkgver=0.1.0
pkgrel=1
pkgdesc='Match an Arch install to its hardware: CachyOS repositories, kernel, microcode, boot entry'
arch=('any')
url='https://github.com/george-leonard314/ChiropteraOS'
license=('MIT')
# chwd and everything else from [cachyos] is deliberately absent: hwd is what
# adds that repository, so depending on it would make this package
# unresolvable from the chiroptera repository alone.
depends=('bash' 'gawk' 'diffutils' 'pciutils' 'systemd')
# The script lives in this repository under hwd/; the symlink beside this
# PKGBUILD makes it a local source. It changes with this repository, so there
# is no checksum to keep -- bump pkgver whenever it changes, since CI skips any
# version it has already built.
source=('chiroptera-hwd')
sha256sums=('SKIP')

package() {
    install -Dm755 "$srcdir/chiroptera-hwd" "$pkgdir/usr/bin/chiroptera-hwd"
}
```

Run:

```bash
ln -s ../../hwd/chiroptera-hwd pkgs/chiroptera-hwd/chiroptera-hwd
```

- [ ] **Step 2: Build it locally and check the payload**

Run:

```bash
cd pkgs/chiroptera-hwd && makepkg --nodeps --force --cleanbuild && \
    bsdtar -tvf chiroptera-hwd-0.1.0-1-any.pkg.tar.zst usr/bin/chiroptera-hwd; cd -
```

Expected: one line starting `-rwxr-xr-x` for `usr/bin/chiroptera-hwd` — a regular file, not a symlink (`l`). Then `rm -rf pkgs/chiroptera-hwd/{src,pkg} pkgs/chiroptera-hwd/*.pkg.tar.zst`.

- [ ] **Step 3: Add it to the repository build**

In `ci/build-repo.sh`, change the default package list:

```bash
read -r -a packages <<<"${PACKAGES:-app2unit chiroptera-shell chiroptera-dots chiroptera-meta chiroptera-hwd}"
```

In the comment block above `extra_flags`, change the `--nodeps` line to:

```
#   --nodeps    chiroptera-dots, chiroptera-meta and chiroptera-hwd have no
#               build() at all.
```

and add to `extra_flags`:

```bash
    [chiroptera-hwd]="--nodeps"
```

- [ ] **Step 4: Make the smoke test resolve it on its own**

In `ci/smoke-test.sh`, insert before the final `echo "ok: ..."` line:

```bash
# chiroptera-hwd adds the CachyOS repositories, so it must resolve without
# them: from Arch plus this repository alone.
echo "resolving chiroptera-hwd"
if ! resolution=$(pac -Sp --noconfirm chiroptera-hwd 2>&1); then
    printf '%s\n' "$resolution" >&2
    fail "chiroptera-hwd does not resolve; it must not need [cachyos]"
fi
grep -q "/chiroptera-hwd-" <<<"$resolution" \
    || fail "chiroptera-hwd was not served by the built repository"
```

and change the final line to:

```bash
echo "ok: $TARGET and chiroptera-hwd resolve against the built repository"
```

- [ ] **Step 5: Run lint and the full container pipeline**

Run: `./ci/lint-pkgbuilds.sh`
Expected: five `ok` lines, including `chiroptera-hwd: ok`.

Run: `SOURCES=$HOME/git REPO_OUT=$(mktemp -d) ./ci/run-in-container.sh`
Expected: all five packages build, and the run ends with `ok: chiroptera-meta and chiroptera-hwd resolve against the built repository`. The fresh `REPO_OUT` keeps the laptop's own `repo/` out of it.

- [ ] **Step 6: Commit**

```bash
git add pkgs/chiroptera-hwd ci/build-repo.sh ci/smoke-test.sh
git commit -m "Package chiroptera-hwd and prove it resolves without CachyOS"
```

---

### Task 6: CI — the bats job and a real apply in a container

**Files:**
- Create: `ci/hwd-apply-test.sh`
- Modify: `.github/workflows/packages.yml`

**Interfaces:**
- Consumes: `chiroptera-hwd detect`, `apply --yes`, and `repos_for` via sourcing.

- [ ] **Step 1: Write the container apply test**

`ci/hwd-apply-test.sh`:

```bash
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
```

Run: `chmod +x ci/hwd-apply-test.sh`

- [ ] **Step 2: Run it locally in a container**

Run:

```bash
docker run --rm -v "$PWD:/work:ro" -w /work archlinux:base-devel ci/hwd-apply-test.sh
```

Expected: ends with `ok: <level> CachyOS system with linux-cachyos and the CachyOS pacman`. The level is the laptop's, `v3`. Takes several minutes: it is a full upgrade of the container onto CachyOS packages.

If `linux-cachyos`'s mkinitcpio hook fails inside the container, stop and report the exact error to the author before changing anything. Do not add a switch to skip the initramfs: the Calamares chroot runs the same hook, so a container failure may be a real one.

- [ ] **Step 3: Add the two jobs to the workflow**

In `.github/workflows/packages.yml`, add `'hwd/**'` to both `paths` lists:

```yaml
  push:
    branches: [main]
    paths: ['pkgs/**', 'ci/**', 'hwd/**', '.github/workflows/packages.yml']
  pull_request:
    paths: ['pkgs/**', 'ci/**', 'hwd/**', '.github/workflows/packages.yml']
```

Add these jobs after `lint` and before `build`:

```yaml
  hwd-tests:
    name: chiroptera-hwd tests
    runs-on: ubuntu-latest
    container: archlinux:base-devel
    steps:
      - name: Install git and bats
        run: pacman -Sy --needed --noconfirm git bats

      - uses: actions/checkout@v7

      - name: Run the bats suite
        run: ./ci/test-hwd.sh

  hwd-apply:
    name: chiroptera-hwd apply in a container
    needs: hwd-tests
    runs-on: ubuntu-latest
    container: archlinux:base-devel
    steps:
      - name: Install git
        run: pacman -Sy --needed --noconfirm git

      - uses: actions/checkout@v7

      - name: Apply for real and check the result
        run: ./ci/hwd-apply-test.sh
```

These jobs need no secret, so they run on pull requests too, and they stay green while `build` waits on `SOURCE_REPO_TOKEN`.

- [ ] **Step 4: Check the workflow parses**

Run: `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add ci/hwd-apply-test.sh .github/workflows/packages.yml
git commit -m "CI: test chiroptera-hwd, and run apply for real in a container"
```

---

### Task 7: Documentation

**Files:**
- Create: `docs/hwd.md`
- Modify: `docs/STATUS.md`
- Modify: `docs/superpowers/specs/2026-09-11-chiroptera-hwd-and-cachyos-design.md`

- [ ] **Step 1: Write `docs/hwd.md`**

```markdown
# chiroptera-hwd

Turns a stock Arch install into a CachyOS install matched to its CPU, with
graphics drivers chosen by CachyOS's `chwd`. Design:
`docs/superpowers/specs/2026-09-11-chiroptera-hwd-and-cachyos-design.md`.

## Use

    chiroptera-hwd detect              # the plan as JSON; changes nothing
    chiroptera-hwd apply --dry-run     # every command and file diff, in order
    sudo chiroptera-hwd apply          # do it; pacman asks before each transaction
    sudo chiroptera-hwd apply --yes    # unattended (Calamares, CI)

Read the dry run before applying. It is the whole change.

## What apply changes

1. Imports and locally signs CachyOS key `F3B607488DB35A47`, installs
   `cachyos-keyring` and the mirrorlists, then inserts the CachyOS sections for
   the CPU level directly above `[core]` in `/etc/pacman.conf`.
2. Installs CachyOS's pacman, then runs a full upgrade onto CachyOS packages.
3. Installs `linux-cachyos`, its headers, microcode, `cachyos-settings`,
   `cachyos-ananicy-rules`, `scx-scheds`, `scx-tools` and `chwd`.
4. Runs `chwd -a` for graphics drivers.
5. Makes `linux-cachyos` the default boot entry: `GRUB_TOP_LEVEL` plus
   `grub-mkconfig` on GRUB; a copied entry plus `default` in `loader.conf` on
   systemd-boot.

Every file it changes is first copied to `<file>.hwd-<timestamp>`. It never
removes stock `linux` or `nvidia-open`, and writes no Hyprland or session
environment.

If a step fails, apply names it and stops. Fix the cause and run apply again;
every step is safe to repeat.

## Undo

1. Boot the stock `linux` entry.
2. `sudo cp /etc/pacman.conf.hwd-<timestamp> /etc/pacman.conf`, using the
   oldest backup: it is the file as it was before hwd first ran.
3. `sudo pacman -Suuy` to move back onto Arch's builds, then
   `sudo pacman -S core/pacman`, then `pacman -Qqn | sudo pacman -S -` to
   reinstall every native package from Arch's repositories. This is the order
   CachyOS's own `cachyos-repo.sh --remove` uses.
4. `sudo pacman -Rns linux-cachyos linux-cachyos-headers chwd cachyos-settings cachyos-ananicy-rules cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist`
   (or the `-v4-` mirrorlist), and `sudo pacman-key --delete F3B607488DB35A47`.
5. Remove the `GRUB_TOP_LEVEL` line from `/etc/default/grub` and run
   `sudo grub-mkconfig -o /boot/grub/grub.cfg`.

## Tests

    # bats suite, in a container (bats is not assumed on the host)
    docker run --rm -v "$PWD:/work:ro" -w /work archlinux:base-devel \
        bash -c 'pacman -Sy --needed --noconfirm bats >/dev/null && ci/test-hwd.sh'

    # a real apply in a throwaway container
    docker run --rm -v "$PWD:/work:ro" -w /work archlinux:base-devel ci/hwd-apply-test.sh

Both run in CI on every push that touches `hwd/`, `ci/` or `pkgs/`.
```

- [ ] **Step 2: Record the refinements in the spec**

Append to `docs/superpowers/specs/2026-09-11-chiroptera-hwd-and-cachyos-design.md`:

```markdown
## Refinements made while planning

Settled from `chwd`'s source and CachyOS's `cachyos-repo.sh`; the plan is
`docs/superpowers/plans/2026-09-11-step5-chiroptera-hwd.md`.

1. `detect` reports `"gpu": "chwd"` rather than a profile name: `chwd --list`
   prints a table for people, not an interface. `apply --dry-run` prints it
   verbatim. The `HWD_CHWD_PROFILE` override is dropped.
2. The keyring and mirrorlists are installed through a throwaway pacman config
   pointing `[cachyos]` at `https://mirror.cachyos.org/repo/$arch/$repo`,
   instead of version-pinned package URLs, which go stale. It still precedes
   the `pacman.conf` edit.
3. `apply --yes` passes `--noconfirm` to pacman; Calamares and CI use it.
4. Package dependencies are `bash gawk diffutils pciutils systemd`;
   `util-linux` is dropped because detection does not use `lscpu`.
5. The systemd-boot entry is copied from the entry whose initrd is
   `/initramfs-linux.img`, which excludes the fallback entry.
6. Undo restores the oldest `pacman.conf` backup, which is the file before hwd
   first ran, and follows `cachyos-repo.sh --remove`'s order: `-Suuy`,
   `core/pacman`, then reinstall every native package.
```

Then make the body of the spec agree with those refinements:

- In the `detect` inputs table, delete the row whose first cell is `GPU profile`.
- In the example JSON, replace the line `"gpu_profile": "none"` with `"gpu": "chwd"`.
- Replace the two-line sentence under the example JSON, which says the GPU profile reads none until chwd is installed, with: "`gpu` is always `chwd`: the profile is chwd's decision, and `apply --dry-run` shows it."
- In the Undo section, change "Restore the newest" to "Restore the oldest", and replace step 3 with: "`pacman -Suuy`, then `pacman -S core/pacman`, then `pacman -Qqn | pacman -S -` to reinstall every native package from Arch's repositories."
- In the Components section, change "`chiroptera-hwd` depends on `bash`, `pciutils` and `util-linux` only" to "`chiroptera-hwd` depends on `bash`, `gawk`, `diffutils`, `pciutils` and `systemd` only".

- [ ] **Step 3: Update `docs/STATUS.md`**

Change the date line to `Updated 2026-09-11.` Replace the step 5 row of the Remaining table with:

```
| 5 | `chiroptera-hwd` is built and tested; applying it to the laptop awaits the author's review of the dry run |
```

Add under `## Done`, after step 2:

```markdown
**Step 5, build half — chiroptera-hwd.** `hwd/chiroptera-hwd` detects the CPU
level and applies the CachyOS repositories, pacman, kernel, microcode and boot
entry, with graphics delegated to `chwd`. Packaged as `chiroptera-hwd`; a bats
suite and a real apply in a container run in CI. See `docs/hwd.md`.
```

- [ ] **Step 4: Commit**

```bash
git add docs/
git commit -m "Document chiroptera-hwd and fold the planning refinements into the spec"
```

---

### Task 8: The author's laptop (gated)

Nothing in this task changes the laptop until the author says yes. Root steps are the author's to run: sudo has no terminal here.

- [ ] **Step 1: Show the plan and the dry run**

Run:

```bash
./hwd/chiroptera-hwd detect
./hwd/chiroptera-hwd apply --dry-run
```

Show the author both outputs in full and ask for an explicit yes. Point out: the four v3 sections above `[core]`, `[blackarch]` untouched, `GRUB_TOP_LEVEL` the only GRUB change, `chwd -a` running after the kernel install. **Stop here until the author approves.**

- [ ] **Step 2: Before-benchmarks (after approval)**

Run, and record each number:

```bash
systemd-analyze
( rm -rf /tmp/hwd-bench && git -C ~/git/chiroptera-shell worktree add -f /tmp/hwd-bench HEAD >/dev/null &&
  cd /tmp/hwd-bench && meson setup build >/dev/null && time ninja -C build >/dev/null;
  git -C ~/git/chiroptera-shell worktree remove --force /tmp/hwd-bench )
```

Record the `real` time. For the GPU run, hand the author `! sudo pacman -S --needed glmark2`, then run:

```bash
__NV_PRIME_RENDER_OFFLOAD=1 __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json \
    glmark2-wayland --off-screen 2>&1 | grep -E 'GL_RENDERER|Score'
```

`GL_RENDERER` must name the GTX 1660 Ti; if it names the Radeon, the offload did not take and the score measures the wrong GPU. Record the score.

- [ ] **Step 3: Hand over the apply**

Give the author:

```
! sudo ./hwd/chiroptera-hwd apply
```

pacman will ask before each transaction. Then the author reboots.

- [ ] **Step 4: Check after reboot**

Run:

```bash
uname -r                                  # ends in -cachyos
nvidia-smi --query-gpu=name --format=csv  # GeForce GTX 1660 Ti ...
pacman -Q linux nvidia-open               # both still installed
hyprctl monitors | grep -E '^Monitor'     # eDP-1, HDMI-A-1, DP-1 when connected
```

Ask the author to confirm all three displays light up, and that the stock `linux` entry still boots (one reboot into it from the GRUB menu, then back).

- [ ] **Step 5: After-benchmarks and record**

Repeat Step 2's measurements. Add a table to `docs/STATUS.md` under the step 5 entry with before and after for boot time, shell build time and the glmark2 score, change the step 5 row to done, and commit:

```bash
git add docs/STATUS.md
git commit -m "Step 5 applied to the laptop: CachyOS v3 with before and after numbers"
```
