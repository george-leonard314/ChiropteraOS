# ChiropteraOS Design

Date: 2026-09-09
Status: approved in discussion, pending written review

## 1. Goal

ChiropteraOS is a personal Arch Linux distribution. Booting its ISO gives a
live Hyprland desktop running Chiroptera Shell, with a Calamares installer
that produces a machine matching the author's current configuration. Installed
machines pull shell and dotfile updates through a pacman repository.

Chiroptera Shell is a Quickshell desktop shell derived from caelestia-shell,
with a top bar, two sidebars, and a workspace overview ported from end-4's
illogical-impulse dotfiles.

Non-goals for the first release: multi-user branding beyond the author, a
public website, secure boot, non-x86_64 targets.

## 2. Decisions taken

| Question | Decision |
|---|---|
| Shell origin | Copy of caelestia-shell with an `upstream` git remote. Not a GitHub fork. |
| Bar layout | Horizontal top bar in the end-4 style. Left bar disabled by default. |
| end-4 parts ported | Right sidebar, left AI sidebar, workspace overview. |
| ISO experience | Live desktop with Chiroptera Shell running and an install button. |
| Installer | Calamares. |
| Package delivery | Signed pacman repo. GitHub Pages now, own Gitea Arch registry later. |
| Hardware target | Generic with hardware detection. |
| Repo layout | Three repos: chiroptera-shell, chiroptera-dots, ChiropteraOS. |
| Upstream tracking | Optional. A sync script plus a weekly assisted review. Never automatic. |

## 3. Repositories

### 3.1 chiroptera-shell

Copy of caelestia-shell's source tree. Remotes: `origin` is the author's
hosting (GitHub now, Gitea later), `upstream` is
`https://github.com/caelestia-dots/shell`.

Installs to `/etc/xdg/quickshell/chiroptera/`. Started with
`chiroptera shell -d` or `qs -c chiroptera`. Can coexist with caelestia-shell
during the transition.

### 3.2 chiroptera-dots

Copy of the caelestia dotfiles repo and the caelestia-cli repo, merged into one
tree:

```
chiroptera-dots/
  cli/          Python package `chiroptera`, renamed from caelestia-cli
  hypr/         Hyprland config split into hyprland/*.conf
  fish/ foot/ starship.toml btop/ fastfetch/ ...
  install.fish  local install script for development machines
```

Remotes: `origin` the author's, `upstream-dots` caelestia-dots/caelestia,
`upstream-cli` caelestia-dots/cli.

### 3.3 ChiropteraOS (this repo)

```
ChiropteraOS/
  pkgs/<name>/PKGBUILD        one directory per package
  calamares/
    branding/chiroptera/      slideshow, logo, strings
    modules/*.conf            module configuration
    settings.conf             module sequence
  iso/                        archiso profile, based on releng
    airootfs/                 files copied into the live root
    packages.x86_64
    profiledef.sh
  scripts/                    build helpers, hardware detection tests
  .github/workflows/          packages, iso, nightly tests
  docs/                       this spec, install checklist, sync ritual
```

### 3.4 Upstream sync

Each source repo has `scripts/sync-upstream.sh`. It fetches every
`upstream*` remote and prints the commits since the recorded last sync,
grouped by top-level directory, with a marker for files the author has
modified. It never merges.

A weekly scheduled routine runs the script, reads the output, and reports:
changes worth taking, changes that touch author-modified files, changes to
ignore. The author approves before anything is applied. The last-sync commit
is recorded in `.upstream-sync` in each repo.

Moving hosting to Gitea is `git remote set-url origin` per repo plus a CI
target change. Nothing else references the hosting provider.

## 4. Chiroptera Shell

### 4.1 Layout

Upstream structure is kept: `modules/` for UI, `services/` for system state,
`config/` for the JSON schema, `utils/` for helpers, `assets/` for icons and
fonts. Upstream files are edited only where a hook is needed to mount a new
module. All new code lives in new directories:

```
modules/topbar/         horizontal bar
modules/sidebar-right/  quick settings, calendar, notifications
modules/sidebar-left/   AI chat, translator, utilities
modules/overview/       workspace grid
```

The upstream left bar stays in the tree and is disabled by config.

### 4.2 Top bar

Full width at the top of every monitor. Left: workspace indicators. Center:
clock and active window title. Right: system tray, network, bluetooth, audio,
battery, and a button that opens the right sidebar. Reserves an exclusive zone
so windows do not overlap it. Bar height, position (top or bottom), and
which widgets appear are configurable.

### 4.3 Right sidebar

Slides in from the right edge on toggle or keybind. Contains quick toggles
(wifi, bluetooth, do-not-disturb, night light), volume and brightness sliders,
a calendar, and the notification list with clear-all. Reuses caelestia's
existing services for audio, network, and notifications.

### 4.4 Left AI sidebar

Slides in from the left edge. Tabs: chat, translator, utilities. Chat supports
multiple providers configured in the shell config; API keys are read from a
file outside the repo (`~/.config/chiroptera/secrets.json`, mode 0600), never
from the shell config. Ported from end-4's QML and adapted to caelestia's
service layer.

### 4.5 Workspace overview

Keybind opens a grid of workspaces with live window thumbnails. Click focuses
a window, drag moves it to another workspace, escape closes. Uses Hyprland's
IPC through the existing Hyprland service.

### 4.6 Configuration

Defaults ship in the package. The JSON schema gains a `chiroptera` section:

```json
{
  "chiroptera": {
    "bar": { "position": "top", "height": 36, "widgets": { "left": [], "center": [], "right": [] } },
    "sidebarLeft": { "width": 420, "providers": [] },
    "sidebarRight": { "width": 380 },
    "overview": { "columns": 5, "scale": 0.15 }
  }
}
```

User overrides live in `~/.config/chiroptera/shell.json` and are deep-merged
over the defaults. Unknown keys log a warning and are ignored.

### 4.7 Kept from caelestia unchanged

Launcher, dashboard, on-screen displays, lock screen, session menu, wallpaper
handling, Material You colour scheme generation.

## 5. Dotfiles and user provisioning

The `chiroptera-dots` package installs:

- `/usr/share/chiroptera/dots/` pristine copy of every config tree.
- `/etc/skel/.config/` the same trees, so new users get them on creation.

`chiroptera` CLI additions:

- `chiroptera dots apply [--force]` copies from the pristine tree into the
  current user's home. Without `--force`, files that differ from the pristine
  copy are left alone and listed.
- `chiroptera dots diff` shows differences between home and pristine.

Existing caelestia CLI commands (shell, scheme, wallpaper, screenshot,
record, clipboard, emoji, toggle, resizer) are kept with the new name.

Hyprland config keeps the split into `hyprland/*.conf`. User overrides:
`~/.config/chiroptera/hypr-user.conf` and `hypr-vars.conf`. The exec line
becomes `exec-once = chiroptera shell -d`.

Personal files never enter any repo: `monitors.conf`, keys, tokens, shell
history, browser profiles. Each repo has a `.gitignore` covering these and a
pre-commit hook that rejects files matching a secret pattern list.

## 6. Packaging and the pacman repository

### 6.1 Packages

| Package | Source | Contents |
|---|---|---|
| chiroptera-shell | chiroptera-shell tag | Quickshell config under `/etc/xdg/quickshell/chiroptera` |
| chiroptera-cli | chiroptera-dots tag | Python package and `chiroptera` executable |
| chiroptera-dots | chiroptera-dots tag | `/usr/share/chiroptera/dots`, `/etc/skel` entries |
| chiroptera-meta | none | depends on everything a desktop needs |
| chiroptera-hwd | ChiropteraOS | hardware detection script and service |
| chiroptera-calamares-config | ChiropteraOS | Calamares settings, modules, branding |
| chiroptera-sddm-theme | ChiropteraOS | login screen theme |
| rebuilt AUR deps | AUR | quickshell-git, calamares, and anything else caelestia-meta pulls from AUR |

Shell and dots PKGBUILDs pin a git tag. A release is: tag the source repo,
bump `pkgver` in the PKGBUILD, push ChiropteraOS.

### 6.2 CI

Workflow `packages.yml` on push to main and on a schedule:

1. Start a clean `archlinux:base-devel` container.
2. Build every PKGBUILD in dependency order. Fail on `namcap` errors.
3. Sign each package with the repo GPG key from a CI secret.
4. `repo-add chiroptera.db.tar.gz` with signature.
5. Publish the repo directory to GitHub Pages.

### 6.3 Repo URL

One file holds the mirror: `iso/airootfs/etc/pacman.d/chiroptera-mirrorlist`.
The `chiroptera-meta` package installs the same file and the pacman.conf
snippet on target systems. Moving to Gitea means editing that file and
pointing step 5 at Gitea's Arch package registry.

## 7. ISO

### 7.1 Profile

Based on archiso `releng`. Changes:

- `packages.x86_64` adds hyprland, sddm, chiroptera-meta, chiroptera-shell,
  chiroptera-dots, chiroptera-cli, chiroptera-hwd, calamares,
  chiroptera-calamares-config, linux-firmware, and the NVIDIA and AMD driver
  packages so the live session works on both.
- `pacman.conf` for the build includes the chiroptera repo.
- `airootfs` adds a `live` user with no password, SDDM autologin into
  Hyprland, the chiroptera mirrorlist, and a desktop entry plus a top bar
  button that launch Calamares with `pkexec`.
- Boot menus show the Chiroptera name and logo.

### 7.2 Calamares

Module sequence: welcome, locale, keyboard, partition, users, summary,
then partition, mount, unpackfs, machineid, fstab, locale, keyboard,
localecfg, users, networkcfg, hwclock, services-systemd, packages,
shellprocess (hwd), bootloader, umount, finished.

Partition offers ext4 and btrfs, optional LUKS, systemd-boot on UEFI and GRUB
on BIOS. The `packages` module removes live-only packages and installs the
list generated at ISO build so target and image match. `services-systemd`
enables sddm, NetworkManager, bluetooth. `shellprocess` runs
`chiroptera-hwd apply` in the target chroot.

### 7.3 Hardware detection (chiroptera-hwd)

Shell script with two commands: `detect` prints the package and service plan
as JSON, `apply` installs it. Detection from `lscpu` and `lspci -nn`:

- CPU vendor: `amd-ucode` or `intel-ucode`.
- NVIDIA GPU present: `nvidia-open`, `nvidia-utils`, `lib32-nvidia-utils`,
  and a Hyprland env snippet in `/etc/chiroptera/hypr-hwd.conf`. Hybrid with
  AMD or Intel adds the integrated driver and marks NVIDIA as secondary.
- AMD GPU: `mesa`, `vulkan-radeon`, `lib32-vulkan-radeon`.
- Intel GPU: `mesa`, `vulkan-intel`, `lib32-vulkan-intel`.
- Virtual machine: `qemu-guest-agent` or `virtualbox-guest-utils`, no
  proprietary drivers.

Runnable on an already installed machine. The author's laptop, AMD Renoir plus
NVIDIA TU116 with nvidia-open, is the reference hybrid case.

## 8. Error handling

- Shell: a failing module logs and is skipped; the bar must still appear.
  Missing secrets file disables the AI tab with a visible notice.
- CLI: `dots apply` never overwrites a changed file without `--force` and
  prints what it skipped.
- Packaging CI: any build or namcap failure fails the workflow and leaves the
  published repo untouched.
- Calamares: hwd failure is logged and the install continues; a first-boot
  notification tells the user to run `chiroptera-hwd apply`.
- hwd: unknown hardware installs only mesa and microcode, never guesses a
  proprietary driver.

## 9. Testing

- Shell: CI loads `qs -c chiroptera` in a nested Hyprland or cage session
  and fails on QML errors. Screenshots of bar and sidebars attached to runs.
- Packages: namcap plus a clean-container install of chiroptera-meta with only
  official repos and the chiroptera repo enabled.
- hwd: unit tests feed recorded `lscpu` and `lspci` output and assert the
  JSON plan. Fixtures: AMD-only, Intel-only, NVIDIA-only, AMD plus NVIDIA
  hybrid, QEMU, VirtualBox.
- ISO nightly: build, boot in QEMU with OVMF, wait for SDDM, screenshot.
  Second job runs an unattended Calamares install to a disk image and boots
  the result to the login screen.
- Manual: `docs/install-checklist.md` run on the author's laptop before every
  release tag.

## 10. Build order

1. Copy the three source trees, set remotes, rename the CLI, get
   `chiroptera shell -d` running on the author's laptop as a pure rename.
2. Top bar, left bar disabled by default.
3. Packaging, CI, pacman repo on GitHub Pages. Laptop switches from AUR
   caelestia packages to the chiroptera repo.
4. chiroptera-hwd with tests, applied on the laptop.
5. ISO with live desktop and Calamares, VM install end to end.
6. Right sidebar, workspace overview, left AI sidebar, one release each.
7. Upstream sync script and weekly routine.

Steps 1 to 5 produce a bootable image that reinstalls the author's machine
with Chiroptera Shell. Each step gets its own implementation plan.
