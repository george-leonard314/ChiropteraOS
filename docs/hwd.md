# chiroptera-hwd

Turns a stock Arch install into a CachyOS install matched to its CPU, with
graphics drivers chosen by CachyOS's `chwd`. Design:
`docs/superpowers/specs/2026-09-11-chiroptera-hwd-and-cachyos-design.md`.

## Use

    chiroptera-hwd detect              # the plan as JSON; changes nothing
    chiroptera-hwd apply --dry-run     # every command and file diff, in order
    sudo chiroptera-hwd apply          # do it; pacman asks before each
                                        # transaction except chwd's at step 4
    sudo chiroptera-hwd apply --yes    # unattended (Calamares, CI)

Read the dry run before applying. It is the whole change.

## What apply changes

1. Initialises pacman's keyring if it has no master key (`pacman-key --init`,
   a no-op on an initialised system), then imports and locally signs CachyOS
   key `F3B607488DB35A47`, installs `cachyos-keyring` and the mirrorlists,
   then inserts the CachyOS sections for the CPU level directly above
   `[core]` in `/etc/pacman.conf`.
2. Installs CachyOS's pacman with `pacman -Syy --needed` -- the `-Syy` forces
   a fresh sync, refreshing the database the bootstrap step fetched -- then
   runs a full upgrade onto CachyOS packages.
3. Installs `linux-cachyos`, its headers, microcode, `cachyos-settings`,
   `cachyos-ananicy-rules`, `scx-scheds`, `scx-tools` and `chwd`.
4. Runs `chwd -a` for graphics drivers. `chwd` chooses the profile itself and
   installs it without prompting; it is the one step pacman does not ask
   about. `chwd --list` after step 3 previews the profile it will pick; the
   dry run cannot show it, because chwd is not installed until step 3 runs.
5. Makes `linux-cachyos` the default boot entry: `GRUB_TOP_LEVEL` plus
   `grub-mkconfig` on GRUB; a copied entry plus `default` in `loader.conf` on
   systemd-boot. With no recognised bootloader it changes nothing and prints
   what to do by hand.

Every file it changes is first copied to `<file>.hwd-<timestamp>`. It never
removes stock `linux` or `nvidia-open`, and writes no Hyprland or session
environment.

After the upgrade, packages such as `nvidia-open` come from CachyOS's
rebuilds, because the CachyOS sections sit above `[core]` and `[extra]`,
while stock `linux` still comes from Arch. When CachyOS's `nvidia-open` lags
an Arch kernel update, the fallback kernel can be without the NVIDIA module
until CachyOS catches up; it still boots on the integrated GPU.

If a step fails, apply names it and stops. Fix the cause and run apply again;
every step is safe to repeat.

### Expected noise

Step 3 may print mkinitcpio's `ERROR: module not found: 'nvidia'` while
building the `linux-cachyos` image. `linux-cachyos-nvidia-open` arrives only
at step 4; installing it rebuilds the image and the error goes away.

## Undo

1. Boot the stock `linux` entry (on GRUB it is under "Advanced options for
   Arch Linux").
2. `sudo chwd --list-installed`, then `sudo chwd -r <profile>` for each
   installed profile (on the author's laptop, `nvidia-open-dkms.prime`). Do
   this first, while chwd is still installed: it removes
   `linux-cachyos-nvidia-open` and the files chwd's hooks wrote
   (`/etc/mkinitcpio.conf.d/10-chwd.conf`,
   `/etc/profile.d/nvidia-rtd3-workaround.sh`,
   `/usr/lib/systemd/user-environment-generators/20-nvidia-rtd3-workaround`),
   which no package owns.
3. Restore the oldest `/etc/pacman.conf.hwd-*` backup over
   `/etc/pacman.conf`: it is the file as it was before hwd first ran.
4. `sudo pacman -Suuy` to move back onto Arch's builds, then
   `sudo pacman -S core/pacman`, then `pacman -Qqn | sudo pacman -S -` to
   reinstall every native package from Arch's repositories. This is the order
   CachyOS's own `cachyos-repo.sh --remove` uses.
5. `sudo pacman -Rns linux-cachyos-nvidia-open linux-cachyos linux-cachyos-headers chwd cachyos-settings cachyos-ananicy-rules scx-scheds scx-tools cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist`
   (or the `-v4-` mirrorlist), and `sudo pacman-key --delete F3B607488DB35A47`.
6. Boot entry. GRUB: remove the `GRUB_TOP_LEVEL` line from
   `/etc/default/grub` and run `sudo grub-mkconfig -o /boot/grub/grub.cfg`.
   systemd-boot: delete `loader/entries/linux-cachyos.conf` and restore
   `loader/loader.conf` from its `.hwd-*` backup.

## Tests

    # bats suite, in a container (bats is not assumed on the host)
    docker run --rm -v "$PWD:/work:ro" -w /work archlinux:base-devel \
        bash -c 'pacman -Sy --needed --noconfirm bats >/dev/null && ci/test-hwd.sh'

    # a real apply in a throwaway container
    docker run --rm -v "$PWD:/work:ro" -w /work archlinux:base-devel ci/hwd-apply-test.sh

Both run in CI on every push that touches `hwd/`, `ci/` or `pkgs/`.

The container apply test runs without privileges, so pacman's post-transaction
hooks cannot run and no initramfs is built. It proves the repositories, the
pacman switch, the upgrade and the package install, not the boot image.
Closing that gap takes both running the container `--privileged` (so hooks
run) and asserting `/boot/initramfs-linux-cachyos.img` exists, because pacman
does not fail on a failed hook. Until then, the first real initramfs build is
the laptop apply.
