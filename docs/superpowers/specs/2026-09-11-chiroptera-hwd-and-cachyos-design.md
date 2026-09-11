# Step 5 — chiroptera-hwd and the CachyOS switch

Design, 2026-09-11. Approved approach: `chiroptera-hwd` owns CPU level, the
CachyOS repositories, kernel, microcode and bootloader; GPU drivers are
delegated to CachyOS's `chwd`.

## Goal

One command, `chiroptera-hwd apply`, turns a stock Arch install into a CachyOS
install matched to its CPU, with the right graphics drivers, and leaves a
stock-kernel fallback that still boots. The same command runs in Calamares'
target chroot in step 6 and on the author's laptop in this step.

## Changes to the original spec

Section 7.3 of `2026-09-09-chiroptera-os-design.md` is superseded by this
document. Three decisions differ from it:

1. **No Hyprland GPU snippet.** hwd writes no `/etc/chiroptera/hypr-hwd.conf`
   and no Hyprland environment at all. The laptop's `env.conf` records nine
   hybrid-GPU attempts, several of which blacked out outputs; none is active
   today. GPU tuning for the session stays in `chiroptera-dots`.
2. **GPU driver choice belongs to `chwd`.** The original table installed
   `nvidia-open` for every NVIDIA GPU, but the open module supports Turing and
   newer only; Maxwell and Pascal need the 580xx branch. `chwd` maintains that
   table, its PRIME variants, and the prebuilt-module selection for
   `linux-cachyos`. Owning a copy of it would mean learning about new hardware
   by breaking it.
3. **The CachyOS package set moves out of `chiroptera-meta`.** Section 6.1 had
   `chiroptera-meta` depend on `linux-cachyos`, `cachyos-settings`,
   `ananicy-cpp` and `scx-manager`, which would make it uninstallable on any
   machine without the CachyOS repositories and would force them into the CI
   smoke test. hwd installs the set after adding the repositories.
   `scx-manager`, a GUI, is dropped in favour of `scx-scheds` and `scx-tools`,
   which the current CachyOS wiki recommends.

## Facts this design rests on

Verified 2026-09-11 against `mirror.cachyos.org`, the CachyOS wiki source and
the `chwd` repository.

| Level | Sections, above `[core]` | Mirrorlist |
|---|---|---|
| baseline | `[cachyos]` | `cachyos-mirrorlist` |
| x86-64-v3 | `[cachyos-v3]` `[cachyos-core-v3]` `[cachyos-extra-v3]` `[cachyos]` | `cachyos-v3-mirrorlist` for the first three |
| x86-64-v4 | `[cachyos-v4]` `[cachyos-core-v4]` `[cachyos-extra-v4]` `[cachyos]` | `cachyos-v4-mirrorlist` for the first three |
| znver4 | `[cachyos-znver4]` `[cachyos-core-znver4]` `[cachyos-extra-znver4]` `[cachyos]` | `cachyos-v4-mirrorlist` for the first three |

- `[cachyos]` carries CachyOS's pacman fork. Because pacman takes a package
  from the first repository that has it, the fork replaces Arch's pacman. This
  is accepted: it is what every CachyOS install runs, and it handles the
  `x86_64_v3`/`x86_64_v4` package architectures that stock pacman rejects under
  `Architecture = auto`.
- The signing key is `F3B607488DB35A47`; `cachyos-keyring` and all three
  mirrorlist packages are in `[cachyos]`.
- `chwd` is in `[cachyos]`, supports plain Arch, and is GPL-3.0-or-later.
  hwd invokes it and does not copy from it.
- `chwd`'s NVIDIA profiles add `<kernel>-nvidia-open` only for kernels whose
  `/usr/lib/modules/*/pkgbase` starts with `linux-cachyos`, falling back to
  `nvidia-open-dkms`. The kernel must therefore be installed before `chwd` runs.
- On a laptop chassis (DMI types 8, 9, 10, 11, 31) with an NVIDIA GPU, `chwd`
  picks the `.prime` profile: `nvidia-prime`, `switcheroo-control`, and
  `/etc/mkinitcpio.conf.d/10-chwd.conf`. It also exports
  `__EGL_VENDOR_LIBRARY_FILENAMES` pointing at Mesa, but only when the NVIDIA
  device is class 0302. The laptop's TU116 is class 0300, so that export is
  inert there.

## Components

| Path | Purpose |
|---|---|
| `hwd/chiroptera-hwd` | The script: `detect`, `apply`, `apply --dry-run` |
| `hwd/tests/*.bats` | Detection and `pacman.conf` edit tests |
| `hwd/tests/fixtures/<machine>/` | Captured command output per reference machine |
| `pkgs/chiroptera-hwd/PKGBUILD` | Packages the script from this repository |
| `ci/hwd-apply-test.sh` | Runs `apply` for real in a fresh Arch container |
| `docs/hwd.md` | Usage, what `apply` changes, and the manual undo |

`chiroptera-hwd` depends on `bash`, `gawk`, `diffutils`, `pciutils` and
`systemd` only. It must not depend on `chwd` or anything else in `[cachyos]`:
hwd is what adds that repository, so such a dependency would be unresolvable
from the `chiroptera` repository alone.

## `detect`

Reads the hardware and prints a plan as JSON. Changes nothing.

Inputs, each overridable by an environment variable so tests can substitute a
fixture file:

| Input | Source | Override |
|---|---|---|
| ISA levels | `/lib/ld-linux-x86-64.so.2 --help` | `HWD_LDSO_HELP` |
| CPU vendor and flags | `/proc/cpuinfo` | `HWD_CPUINFO` |
| Virtualisation | `systemd-detect-virt` | `HWD_VIRT` |
| Bootloader | `/boot/grub/grub.cfg`, `bootctl is-installed` | `HWD_BOOTLOADER` |

Decisions:

- **Level.** An ISA level counts only when the loader marks it
  `(supported, searched)`.
  - v4 and vendor `AuthenticAMD` gives `znver4`. Zen 4 and Zen 5 are the only
    AMD CPUs with AVX-512, so no compiler is needed; CachyOS's own script uses
    `gcc -march=native`, which is absent from `base`.
  - v4 on any other vendor gives `v4`. The loader tests the AVX-512 CPUID bits
    themselves, so Intel parts with AVX-512 fused off report v3 and land there.
  - v3 gives `v3`.
  - Anything lower gives `baseline`: `[cachyos]` alone.
- **Microcode.** `amd-ucode` for `AuthenticAMD`, `intel-ucode` for
  `GenuineIntel`, none otherwise.
- **Bootloader.** `grub`, `systemd-boot`, or `unknown`.
- **Guest tools.** `kvm` or `qemu` adds `qemu-guest-agent`; `oracle` adds
  `virtualbox-guest-utils`. `chwd` handles VM graphics.
- **GPU.** Reported for information only. `chwd`'s choice is final.

Output for the author's laptop:

```json
{
  "level": "v3",
  "repos": ["cachyos-v3", "cachyos-core-v3", "cachyos-extra-v3", "cachyos"],
  "packages": ["linux-cachyos", "linux-cachyos-headers", "amd-ucode",
               "cachyos-settings", "cachyos-ananicy-rules",
               "scx-scheds", "scx-tools", "chwd"],
  "bootloader": "grub",
  "virt": "none",
  "gpu": "chwd"
}
```

`gpu` is always `chwd`: the profile is chwd's decision. `apply --dry-run`
shows it only once chwd is installed, which does not happen until step 3;
before that the dry run says so instead of guessing.

## `apply`

Runs as root. Each step is idempotent, so a failed run is fixed and re-run
rather than rolled back.

1. **Repositories.**
   - `pacman-key --init`, which creates a master key only when none exists.
   - Copy `/etc/pacman.conf` to `/etc/pacman.conf.hwd-<timestamp>`.
   - `pacman-key --recv-keys F3B607488DB35A47` and `--lsign-key`, then install
     `cachyos-keyring` and the mirrorlists for the level. These are fetched as
     package files from `mirror.cachyos.org` because the repository they would
     come from is not configured yet.
   - Insert the level's sections, in the order of the table above, directly
     above `[core]`. A `[chiroptera]` section above `[core]` stays above them;
     `[blackarch]` and any other section stays where it is.
   - Set `Architecture = auto`.
   - A section already present is not added again.
   - A `pacman.conf` with no `[options]` section, and no existing
     Architecture line to convert, is refused rather than guessed at: there
     is no reliable place to anchor an inserted `Architecture = auto` line.
2. **Upgrade, in two transactions.**
   - `pacman -Syy --needed cachyos/pacman` first. The `-Syy` forces a fresh
     sync of every database, refreshing the `cachyos.db` the bootstrap step
     fetched from `mirror.cachyos.org` with what the level's mirrorlist
     actually serves. Arch's pacman rejects packages whose architecture is
     `x86_64_v3` or `x86_64_v4` under `Architecture = auto`, so it cannot
     perform the upgrade itself; the fork's own package is plain `x86_64`
     and installs fine. CachyOS's `cachyos-repo.sh` orders it the same way
     for the same reason.
   - `pacman -Syu` with the fork. The level's rebuilds replace Arch's packages.
3. **Packages.** `pacman -S --needed` the `packages` list from `detect`, plus
   guest tools on a VM.
4. **Graphics.** `chwd -a`, now that `linux-cachyos` is installed. `chwd`
   chooses the profile and installs it itself, without prompting; it is the
   one step in apply that pacman does not ask about.
5. **Boot.**
   - GRUB: set `GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"` in
     `/etc/default/grub`, then `grub-mkconfig -o /boot/grub/grub.cfg`.
     `GRUB_DEFAULT` is left alone; top-level makes the CachyOS kernel entry 0.
   - systemd-boot: write `loader/entries/linux-cachyos.conf` with the root and
     options copied from the existing default entry, and set
     `default linux-cachyos.conf` in `loader/loader.conf`.
   - Unknown: skip and print what to do by hand.

Invariants:

- **Never removes stock `linux` or `nvidia-open`.** They remain installed and
  bootable as the fallback entry.
- **The fallback's NVIDIA module can still lag.** After the upgrade,
  packages such as `nvidia-open` come from CachyOS's rebuilds, because the
  CachyOS sections sit above `[core]` and `[extra]`, while stock `linux`
  still comes from Arch. When CachyOS's `nvidia-open` lags an Arch kernel
  update, the fallback kernel can be without the NVIDIA module until
  CachyOS catches up; it still boots on the integrated GPU.
- **Never edits or deletes a file it did not write,** apart from the
  `pacman.conf` and `/etc/default/grub` changes above, both of which it backs
  up. On the laptop that leaves `/etc/modprobe.d/nvidia.conf`, the `MODULES`
  line in `mkinitcpio.conf` and all of `~/.config/hypr` as they are. The
  `MODULES` duplicated by `chwd`'s `10-chwd.conf` is harmless.
  `pacman-key --init` may add missing default options to pacman's own
  keyring `gpg.conf`; that file is managed by pacman-key.
- **Writes no session environment.**

`apply --dry-run` prints each command in order instead of running it.

## Failures

- `apply` stops at the first failing step and names it; the exit code is
  non-zero. Nothing is rolled back.
- In Calamares, `shellprocess` marks the hwd step non-fatal: the failure is
  logged and the install continues with the packages copied from the live
  image. The first-boot notice pointing at `chiroptera-hwd apply` is step 6
  work.
- No network: step 1 fails before `pacman.conf` is changed, because the key and
  keyring are fetched before the file is edited.

## Undo

Documented in `docs/hwd.md`, not shipped as a command:

1. Boot the stock `linux` entry (on GRUB it is under "Advanced options for
   Arch Linux").
2. `chwd --list-installed`, then `chwd -r <profile>` for each installed
   profile (on the author's laptop, `nvidia-open-dkms.prime`). Do this
   first, while chwd is still installed: it removes
   `linux-cachyos-nvidia-open` and the files chwd's hooks wrote
   (`/etc/mkinitcpio.conf.d/10-chwd.conf`,
   `/etc/profile.d/nvidia-rtd3-workaround.sh`,
   `/usr/lib/systemd/user-environment-generators/20-nvidia-rtd3-workaround`),
   which no package owns.
3. Restore the oldest `/etc/pacman.conf.hwd-*` backup over
   `/etc/pacman.conf`.
4. `pacman -Suuy`, then `pacman -S core/pacman`, then `pacman -Qqn | pacman -S -`
   to reinstall every native package from Arch's repositories.
5. Remove `linux-cachyos-nvidia-open`, `linux-cachyos*`, `chwd`, `cachyos-*`
   and the CachyOS keyring, and `pacman-key --delete F3B607488DB35A47`.
6. Boot entry. GRUB: remove `GRUB_TOP_LEVEL` and regenerate `grub.cfg`.
   systemd-boot: delete `loader/entries/linux-cachyos.conf` and restore
   `loader/loader.conf` from its `.hwd-*` backup.

A `revert` command would be a second system to test for a path that should
not be needed. If it is ever needed twice, it becomes a command.

## Testing

Three layers, cheapest first:

1. **bats, on every push.** Fixtures for five machines: the author's laptop
   (Zen 2, v3, hybrid NVIDIA TU116 + AMD Renoir, GRUB), a Zen 4 desktop, an
   Intel v3 laptop, a pre-v3 CPU, and a KVM guest. Each asserts the `detect`
   JSON. The `pacman.conf` edit is tested against a stock Arch file, a file
   with `[blackarch]` below `[multilib]`, a file with `[chiroptera]` above
   `[core]`, and a second run over its own output, which must be byte-identical.
2. **Container apply, in CI.** `ci/hwd-apply-test.sh` runs `apply` for real in
   a fresh `archlinux:base-devel` container with `HWD_BOOTLOADER=unknown`.
   `chwd` sees the runner's virtual hardware and picks whatever profile that
   matches; the test asserts only that it exits 0. It asserts that
   `linux-cachyos` is installed, `pacman.conf` has the level's sections above
   `[core]`, and the installed `pacman` version equals `cachyos/pacman`'s.
   This is also the check that the two-transaction upgrade in step 2 is
   needed and sufficient. The container runs `--privileged` so pacman's hooks
   run, and the test asserts `/boot/initramfs-linux-cachyos.img` exists,
   because pacman does not fail a transaction over a failed hook.
3. **The laptop, by hand, gated.** See below.

## On the author's laptop

1. `chiroptera-hwd detect` and `chiroptera-hwd apply --dry-run`; the output is
   shown to the author. Nothing is applied until the author approves.
2. Before-benchmarks: boot time (`systemd-analyze`), a `chiroptera-shell`
   clean build, and a GPU run.
3. `apply`, reboot.
4. Check: `uname -r` shows `-cachyos`; eDP-1, HDMI-A-1 and DP-1 all light up;
   `nvidia-smi` sees the TU116; the stock `linux` entry still boots.
5. After-benchmarks, recorded in `docs/STATUS.md`.

## Notes for step 6

- Run hwd after Calamares' bootloader module, not before: otherwise
  `/boot/grub/grub.cfg` does not exist yet and the bootloader is detected as
  `unknown`.
- After hwd, run `gpgconf --homedir /etc/pacman.d/gnupg --kill all` in the
  chroot. `pacman-key` leaves `gpg-agent` and `dirmngr` running there, and
  the target cannot be unmounted while they are.

## Out of scope

The ISO and Calamares (step 6), beyond making `apply` runnable in a chroot.
Any change to `chiroptera-dots`, including the hybrid-GPU notes in `env.conf`.
Publishing `chiroptera-hwd` to a hosted repository, which waits on the step 4
hosting decision like every other package.

## Refinements made while planning

Settled from `chwd`'s source and CachyOS's `cachyos-repo.sh`; the plan is
`docs/superpowers/plans/2026-09-11-step5-chiroptera-hwd.md`.

1. `detect` reports `"gpu": "chwd"` rather than a profile name: `chwd --list`
   prints a table for people, not an interface. `apply --dry-run` prints it
   verbatim once chwd is installed, and otherwise says plainly that chwd
   will pick the profile unprompted at step 4. The `HWD_CHWD_PROFILE`
   override is dropped.
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
7. Step 1 runs `pacman-key --init` before importing the CachyOS key.
   `--lsign-key` needs a local master key, which the official Arch container
   image lacks and a fresh chroot may lack; `--init` creates one only when
   none exists and otherwise changes nothing. Found by the container apply
   test.
