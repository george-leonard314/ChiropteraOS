# ChiropteraOS

A personal Arch Linux distribution. Booting its ISO gives a live Hyprland
desktop running Chiroptera Shell, with a Calamares installer that produces a
machine matching the author's configuration. Installed machines take shell and
dotfile updates through a pacman repository.

Three repositories make it up:

| Repository | What it is |
|---|---|
| [chiroptera-shell](https://github.com/george-leonard314/chiroptera-shell) | Chiroptera Shell, the native C++ Wayland desktop shell: bar, launcher, control center, notifications, lock screen, wallpaper and Material You theming, Luau plugins |
| [chiroptera-dots](https://github.com/george-leonard314/chiroptera-dots) | The dotfiles: Hyprland, the shell's `config.toml`, fish, foot, fastfetch, theme templates |
| ChiropteraOS (this one) | Packages, the pacman repository's CI, hardware detection, boot and login, the ISO and its installer |

## What you get

- **Chiroptera Shell** as the session shell, with the bat logo, the Chiroptera
  palette, and colours that follow the wallpaper across GTK, the terminal and
  the apps the dots theme.
- **Performance from the CachyOS repositories.** `chiroptera-hwd` detects the
  CPU level and switches the machine to the matching optimized repositories,
  the `linux-cachyos` kernel, microcode and boot entry, with graphics drivers
  chosen by `chwd`. Stock `linux` stays as a fallback. See `docs/hwd.md`.
- **Boot and login:** the Dark Matter GRUB theme, a greetd login screen with
  the bat logo and the shell's palette, and the "ChiropteraOS" session, which
  orders GPUs so DisplayLink docks work.
- **DisplayLink docks** work in the live session and after install.

## Packages

| Package | From |
|---|---|
| `chiroptera-shell` | a chiroptera-shell tag, built with Meson |
| `chiroptera-greeter` | the same tag's `greeter/`: the greetd login screen, built with Meson |
| `chiroptera-dots` | a chiroptera-dots tag |
| `chiroptera-meta` | this repository: depends on everything a desktop needs |
| `chiroptera-hwd` | `hwd/` |
| `chiroptera-boot` | `boot/`: GRUB theme, login screen, session |
| `app2unit`, `pacseek`, `linux-wallpaperengine-git`, `evdi-dkms`, `displaylink` | vendored from the AUR, because `pacman` cannot resolve AUR-only dependencies |

`.github/workflows/packages.yml` builds them in a clean Arch container, proves
`chiroptera-meta` installable, and uploads a ready-to-serve repository. Where
it is published is still open: see `docs/repository.md`.

## Install on an existing Arch machine

Append `ci/chiroptera.conf` to `/etc/pacman.conf` below `[core]` and `[extra]`,
set its `Server` to the published repository, then:

```sh
sudo pacman -Sy chiroptera-meta
sudo chiroptera-hwd apply --dry-run   # read it; it is the whole change
sudo chiroptera-hwd apply
```

## Build the ISO

```sh
gh run download <run-id> -n chiroptera-repo -D pkgs-out
docker run --rm --privileged -v "$PWD":/src:ro -v "$HOME/.cache/chiroptera-iso":/build \
  archlinux:base-devel env PACKAGES_DIR=/src/pkgs-out /src/ci/build-iso.sh
```

The image lands in `~/.cache/chiroptera-iso/out/`. `docs/iso.md` covers the
profile, the installer, and the QEMU end-to-end test.

## Layout

```
pkgs/<name>/PKGBUILD   one directory per package
hwd/                   chiroptera-hwd and its bats suite
boot/                  GRUB theme, greeter config, the ChiropteraOS session
iso/                   archiso profile
calamares/             installer settings, modules, branding, staged files
ci/                    container builds, lint, name check, smoke and hwd tests, ISO build
legacy/names.sh        the only place the names of the projects the shell and greeter
                       were forked from may appear (see ci/check-names.sh)
docs/                  hwd, iso, repository, status, design specs
```

## Releasing

Tag the source repository, bump `pkgver` (and `_tag`) in its PKGBUILD here,
push. CI rebuilds what changed.

For the shell, tags are `v<version>-chiroptera<N>` and `pkgver` is the tag
without the leading `v` and with `-` replaced by `.` (`v5.2.0-chiroptera3`
becomes `5.2.0.chiroptera3`). `chiroptera-greeter` builds from the same tag:
move its `_tag` along with the shell's, and bump its `pkgver` to the version in
`greeter/meson.build`, or its `pkgrel` when only the tag moved. Push the tag by
name, push this repository so CI rebuilds, install, then check the laptop:

```sh
pkill -x chiroptera; chiroptera --daemon
hyprctl layers | grep -o 'namespace: chiroptera-[a-z-]*' | sort -u   # bar, panel, wallpaper
chiroptera --version
```

and by hand: tap Super (launcher opens), Super+period (settings opens), a
special-workspace key (the app opens in it), and log out once to see the
login screen.

The shell and the greeter no longer follow the projects they were forked
from. `ci/check-names.sh` (run in CI's lint job) fails if one of those names
shows up anywhere but `legacy/names.sh`, which holds the few that installed
systems still carry: the greeter package `chiroptera-greeter` replaces, and the
cache directory an already installed Zen palette template writes into.

## License

See `LICENSE`. `displaylink` is proprietary (Synaptics' EULA); see
`docs/repository.md` before redistributing the repository or the image.
