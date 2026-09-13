# The ISO (step 6)

`iso/` is an archiso profile based on `releng`. Booting it gives a live
Hyprland desktop running Chiroptera Shell, logged in as the user `live`, with
**Install ChiropteraOS** in the launcher. The installer is Calamares
(BlackArch's `calamares`), configured by `calamares/`, which is packaged as
`chiroptera-calamares-config`.

## Build

```sh
# Packages: CI's chiroptera-repo artifact plus chiroptera-calamares-config.
gh run download <run-id> -n chiroptera-repo -D pkgs-out
(cd pkgs/chiroptera-calamares-config && makepkg -f --nodeps) && cp pkgs/chiroptera-calamares-config/*.pkg.tar.zst pkgs-out/

docker run --rm --privileged -v "$PWD":/src:ro -v "$HOME/.cache/chiroptera-iso":/build \
  archlinux:base-devel env PACKAGES_DIR=/src/pkgs-out /src/ci/build-iso.sh
```

The ISO lands in `~/.cache/chiroptera-iso/out/`. `/build` needs about 15 GB.

**Never delete the work directory by hand after killing a build.** mkarchiso
bind-mounts `/dev`, `/proc` and `/sys` into its chroot, and a killed run
leaves them mounted; `rm -rf` then deletes device nodes through the `/dev`
bind mount, which in a privileged container reaches the host and removes
`/dev/null` (restore it with `mknod -m 666 /dev/null c 1 3`). `build-iso.sh`
now unmounts everything under the work directory first and deletes with
`--one-file-system`.

## How the pieces fit

- **The live image is plain x86-64 Arch** with the stock `linux` kernel, so
  it boots in virtual machines and on CPUs without AVX2. Only what Arch lacks
  (the Noctalia greeter) comes from `[cachyos]`, which sits after Arch's
  repositories in the build's `pacman.conf`. Calamares comes from
  `[blackarch]`, last: CachyOS's `cachyos-calamares` is linked against
  Boost 1.91, which both Arch and CachyOS have replaced with 1.92, so it
  does not start. BlackArch's build does not use Boost. Because that package
  ships no configs, `calamares/modules/` carries every module config the
  sequence needs (the plain-named ones are copied from CachyOS). `nvidia-open` is included so NVIDIA machines
  get a working live session.
- **DisplayLink docks work in the live session.** `evdi-dkms` and
  `displaylink` are vendored from the AUR into `pkgs/` (see
  `docs/repository.md`; `displaylink` is proprietary). evdi is a DKMS module,
  so `dkms` and `linux-headers` ship too and the module is compiled during the
  image build -- about 600 MB uncompressed, which the squashfs absorbs. Since
  the install is a copy of this filesystem, DKMS is also what rebuilds evdi on
  the installed system after the user's first kernel update.
- **The install is offline.** Calamares copies the live squashfs to the
  disk (`unpackfs`), then `chiroptera-live-cleanup` strips everything that
  made it a live session: archiso's initramfs hooks, the `live` user,
  autologin, passwordless sudo and polkit, the tmpfs keyring and releng's
  live-medium tweaks. It also removes the installer itself.
- **Then `chiroptera-hwd apply --yes` runs in the target**, the same code
  path that converted the author's laptop: CachyOS repositories for the CPU
  level, the CachyOS pacman, `linux-cachyos`, microcode, `chwd` graphics
  drivers, and `GRUB_TOP_LEVEL`. Stock `linux` stays as the fallback entry.
  The step needs the internet. If it fails, the install still finishes on
  stock Arch, and `sudo chiroptera-hwd apply` retries after the first boot.
- **GRUB on both UEFI and BIOS.** The spec asked for systemd-boot on UEFI,
  but hwd's systemd-boot path has only been tested in containers, and its
  GRUB path is the one proven on real hardware. The ESP is `/boot/efi`, and
  LUKS is version 1 because GRUB must unlock `/boot` and cannot open LUKS2's
  argon2 keyslots.
- **All three package sources are set up by the install.** Arch (with
  multilib) comes from the image's `pacman.conf`, CachyOS from
  `chiroptera-hwd`, and BlackArch from `chiroptera-blackarch`, which
  bootstraps that keyring over HTTPS and adds the repository. `paru`, in the
  apps box, covers the AUR. Each step is skipped without the internet and can
  be re-run by hand afterwards.
- **One tick box installs the extra apps.** The installer's "Extra apps" page
  (`netinstall`, ticked by default) holds five packages, listed in
  `calamares/chiroptera-netinstall.yaml`: VSCodium, OnlyOffice, GIMP, and
  `base-devel` plus `paru` so the AUR works. Its `packages` job
  runs after `chiroptera-hwd`, when the CachyOS repositories those come from
  exist. AUR-only apps cannot be installed from there.
- **The browser is a choice.** The installer's "Browser" page
  (`packagechooser`, `calamares/modules/chiroptera-packagechooser-browser.conf`)
  takes exactly one of Firefox (preselected), Zen Browser and Brave. The same
  `packages` job installs it, so without the internet no browser is
  installed. Win+W runs `chiroptera-browser` from `chiroptera-dots`, which
  opens whichever of the three is installed.
- **The account starts with its home folders.** Right after the user is
  created, `shellprocess@userdirs` runs `chiroptera-user-dirs`, which runs
  `xdg-user-dirs-update` as that user: Desktop, Documents, Downloads, Music,
  Pictures, Projects, Public, Templates and Videos, named in the system
  locale. It also enables `xdg-user-dirs.service` globally, so accounts
  added later get them at their first login.
- **The desktop is in the image** (`chiroptera-meta`): the shell, the
  dotfiles, Thunar with archive, thumbnail, trash and mounting support,
  nwg-displays and nano among them, and KMG for notes (`pkgs/kmg`, a rebrand
  of SiYuan built on the system Electron). `chiroptera-apps`, from
  `chiroptera-dots`, installs what no repository carries after first boot.
- **The installer opens by itself.** The live user's Hyprland overrides file
  is a symlink to `/etc/chiroptera-live/user.conf`, which execs
  `chiroptera-install` a few seconds after the desktop appears. It is also in
  the launcher as "Install ChiropteraOS", and `chiroptera-install` works from
  a terminal.
- **Login:** greetd. The live image logs straight into
  `/usr/local/bin/chiroptera-live-session`, a wrapper that sets
  `AQ_DRM_DEVICES` to the real GPUs and leaves DisplayLink's evdi cards out of
  it. Without that, a machine with a dock attached at boot can have Hyprland
  pick a non-rendering evdi node as its primary device and show nothing at all
  on any output, with VT switching dead too. Installed systems get
  `noctalia-greeter`, branded by `chiroptera-themes`.

  The wrapper is live-only: `chiroptera-live-cleanup` rewrites
  `/etc/greetd/config.toml` on the target, so an installed machine starts
  Hyprland through the greeter without it. The same guard belongs in
  `chiroptera-dots` (`hypr/hyprland/env.conf`) and is still owed.

## Look: `chiroptera-themes`

`themes/` in this repository, packaged as `chiroptera-themes`:

- **GRUB:** the author's Dark Matter theme (VandalByte, GPL-3.0), installed
  to `/usr/share/grub/themes/darkmatter`. The installer's `grubcfg` sets
  `GRUB_THEME` to it.
- **Login screen:** `noctalia-greeter` with the bat logo. greetd starts it
  with `NOCTALIA_GREETER_ASSETS_DIR=/usr/share/chiroptera/greeter/assets`,
  a bundle holding the bat as `noctalia.svg` plus the greeter's own icon
  font. On first install the package seeds `/var/lib/noctalia-greeter/`
  with `sync.toml` (the Chiroptera palette and wallpaper) and `greeter.toml`
  (default session Hyprland). Appearance lives in `sync.toml` on purpose:
  the shell's **Settings -> Security -> Greeter -> Sync Now** writes there,
  and a palette in `greeter.toml` would override it for good.

## Calamares configuration

`calamares/settings.conf` is `/etc/calamares/settings.conf`. Every module we
configure is an instance (`partition@chiroptera` and so on) whose config file
is `chiroptera-<module>.conf`, a naming habit kept from when the installer was `cachyos-calamares`, which
shipped its own configs there.

Defaults chosen without the author's input, all easy to change:

| Setting | Value |
|---|---|
| Time zone | Europe/Amsterdam, overridden by GeoIP |
| File systems | ext4 (default) or btrfs, optional LUKS1 |
| Swap | none or a swap file |
| User | shell fish; groups wheel, audio, video, input, storage; root password reused |
| Hostname | `chiroptera` |
| Services | NetworkManager, systemd-resolved, greetd, bluetooth, timesyncd, fstrim, displaylink |
| Finish | "Restart now" ticked |

## Verified in QEMU

A full UEFI install on 2026-09-11/12 (`ci/build-iso.sh`, then QEMU with OVMF):
live session, Calamares through to "succeeded", first boot of the installed
system, GRUB with the Dark Matter theme, the branded greeter, and login as
the created user. What that run exposed, all fixed here:

- `cachyos-calamares` cannot start (Boost 1.91 vs 1.92) -> BlackArch's
  `calamares`, which ships no configs, so `calamares/modules/` carries them.
- That package also omits runtime tools CachyOS's build pulled in; the config
  package now depends on `rsync` (unpackfs uses it), `gptfdisk`, `dmidecode`,
  `upower` and `qt6-imageformats`.
- archiso ships no separate microcode images, so `unpackfs` must not copy
  them; mkinitcpio's `microcode` hook embeds them in the target initramfs.
- The seeded greeter state must be world-readable: the greetd account often
  does not exist yet when `chiroptera-themes` is installed, and an unreadable
  `greeter.toml` leaves the login screen showing a configuration error.
- `chiroptera-hwd` runs twice: the first `pacman -Syu` can lose a package to
  a CachyOS mirror that is briefly out of sync, which aborts the upgrade. In
  that QEMU run it did exactly that, the step was ignored as designed, and
  the install finished on stock Arch.

## Found on real hardware

The first install on a real laptop (mainLaptop, 2026-09-13) went wrong in four
ways QEMU never showed. All are fixed here.

- **The installer could not find the system image.** archiso's boot hook
  copies the image into RAM when it is under 4 GiB and the machine has
  2 GiB more free memory than that. It then unmounts the boot medium and
  deletes `/run/archiso/bootmnt`, where `unpackfs` reads the image and the
  kernel. Every boot entry now passes `copytoram=n`.
- **The extra apps were skipped without a word.** Calamares checks the
  internet once, on the welcome page. The live session opens the installer
  seconds after the desktop appears, before a laptop has joined Wi-Fi, and
  the `packages` module skips everything when that first check said no.
  `chiroptera-netcheck`, a small job module in `calamares/job-modules`,
  checks again just before the online steps.
- **BlackArch and the extra apps had no DNS.** The hwd step pointed
  `/etc/resolv.conf` back at systemd-resolved's stub before those steps ran.
  The stub lives under `/run`, an empty tmpfs inside the chroot.
  `shellprocess@resolv` now does that after the last online step.
- **The CachyOS upgrade failed on conflicting firmware files.** Arch's
  20260910 firmware release split `linux-firmware-ti` and
  `linux-firmware-amd` out of `linux-firmware-other`. CachyOS still ships
  the older layout under a higher epoch, so its `linux-firmware-other`
  carries files those two already own, and pacman refused the whole
  upgrade. `chiroptera-hwd` now removes such packages first; see
  `docs/hwd.md`.

Every online step may fail without stopping the install, so the installer
log is now kept on the target as `/var/log/chiroptera-installer.log`.

## Testing it in a virtual machine

QEMU with OVMF is what the install above was verified on. In VirtualBox the
image boots too, but **set Graphics Controller to VBoxSVGA**: with VMSVGA the
guest kernel logs `vmwgfx ... running on an unsupported hypervisor` and the
live session never draws, leaving a black screen. Enable EFI, give it 6 GB,
4 CPUs, a 40 GB disk and NAT networking (the CachyOS, BlackArch and app steps
all need the internet).

## Not done yet

- A CI job that builds the ISO and boots it in QEMU.
- A launcher/bar button beyond the desktop entry, and a first-boot notice
  when hwd was skipped.
- Installed systems have no `[chiroptera]` repository until step 4 publishes
  one, so the ChiropteraOS packages cannot update through pacman.
