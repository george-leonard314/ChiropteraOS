# ChiropteraOS Design

Date: 2026-09-09
Status: approved in discussion, pending written review

## 1. Goal

ChiropteraOS is a personal Arch Linux distribution. Booting its ISO gives a
live Hyprland desktop running Chiroptera Shell, with a Calamares installer
that produces a machine matching the author's current configuration. Installed
machines pull shell and dotfile updates through a pacman repository.

Performance targets CachyOS: the same kernel, the same optimized package
repositories, and the same system tuning, consumed from their repos rather
than rebuilt.

Chiroptera Shell is a native C++ Wayland desktop shell (no Qt, no GTK) with a
TOML config, a settings GUI, and Luau plugins. Measured on the author's laptop:
0.29 s to first bar and 183 MB proportional memory at start. Chiroptera's
identity lives in the theme, the bar composition, its own plugins (an AI
sidebar first), and native additions to the C++ core.

Non-goals for the first release: multi-user branding beyond the author, a
public website, secure boot, non-x86_64 targets, a workspace overview with
live window thumbnails (Hyprland's own overview covers it).

## 2. Decisions taken

| Question | Decision |
|---|---|
| Shell | Chiroptera Shell (C++, MIT), the author's own, with full history. |
| Naming | Everything is `chiroptera`: binary, config and state dirs, IPC, D-Bus names, layer namespaces, env vars, UI strings, docs. |
| Plugin API | `chiroptera.*` is the Luau global; an alias keeps existing third-party plugins working. |
| Bar layout | Horizontal top bar, composed from widgets: a bar configuration plus theme, not code. |
| Panels | Right sidebar: the built-in control center. Left AI sidebar: a Chiroptera Luau panel plugin. Workspace overview: dropped (see non-goals). |
| ISO experience | Live desktop with Chiroptera Shell running and an install button. |
| Installer | Calamares. |
| Login screen | `chiroptera-greeter`, built from `greeter/` in chiroptera-shell, branded by `chiroptera-boot`. |
| Package delivery | Signed pacman repo. GitHub Pages now, own Gitea Arch registry later. |
| Hardware target | Generic with hardware detection. |
| Repo layout | Three repos: chiroptera-shell, chiroptera-dots (the author's own dotfiles), ChiropteraOS. |
| Dotfiles | Start from the configs on the author's laptop. No upstream. |
| Upstream tracking | None. The shell and greeter do not follow the projects they were forked from (decided 2026-10-16). |
| Performance | Consume the CachyOS repositories: kernel, optimized v3/v4 packages, cachyos-settings, ananicy-cpp. Stock `linux` kept as fallback. |

## 3. Repositories

### 3.1 chiroptera-shell

C++23, Meson, MIT. Remote: `origin` is the author's hosting (GitHub now,
Gitea later). It also holds the greeter, `greeter/`, its own Meson project.

`chiroptera/check-rename.sh` fails if a name of the project the shell was
forked from appears outside the files allowed to keep it.
Binary `chiroptera`, config `~/.config/chiroptera/config.toml`, state
`~/.local/state/chiroptera/`, assets `/usr/share/chiroptera/`, IPC
`chiroptera msg ...`, D-Bus prefix `dev.chiroptera.`, layer namespaces
`chiroptera-*`, env vars `CHIROPTERA_*`, desktop entry
`dev.chiroptera.Chiroptera.desktop`.

The shell calls no web service of the project it was forked from; plugins
come only from local and user-added sources. The few old names installed
systems still hold, such as the plugin API's former global, live in
`src/legacy/legacy_names.h`. The Luau host registers the API table under
`chiroptera` and that compatibility alias.

### 3.2 chiroptera-dots

The author's own dotfiles, captured from the laptop: Hyprland config (legacy
`.conf` layout as currently used, every bind on Chiroptera IPC), fish, foot, starship, btop, fastfetch, and the
Chiroptera Shell `config.toml`. No upstream remote. Personal files never
enter it: no `monitors.conf`, keys, tokens, history.

```
chiroptera-dots/
  hypr/            hyprland.conf + hyprland/*.conf
  chiroptera/      config.toml, palettes/, plugins/ (the author's plugins)
  fish/ foot/ starship.toml btop/ fastfetch/
  scripts/apply.sh   copies into $XDG_CONFIG_HOME without clobbering changed files
```

### 3.3 ChiropteraOS (this repo)

```
ChiropteraOS/
  pkgs/<name>/PKGBUILD        one directory per package
  calamares/                  branding, modules, settings
  iso/                        archiso profile, based on releng
  scripts/                    build helpers, hardware detection tests
  .github/workflows/          packages, iso, nightly tests
  legacy/names.sh             the old names installed systems still hold
  docs/                       specs, plans, checklists
```

### 3.4 No upstream

None of the three repositories follows another project. The shell and greeter
were forked once; nothing is merged from their origins any more. Each repository
has a check that fails if one of the old names comes back outside its single
legacy-names place (`src/legacy/legacy_names.h` in the shell,
`legacy/names.sh` here, none at all in chiroptera-dots).

Moving hosting to Gitea is `git remote set-url origin` per repo plus a CI
target change.

## 4. Chiroptera Shell

### 4.1 Naming

Everything carries the `chiroptera` name: Meson project and targets, C++
identifiers, D-Bus interface names (`dev.chiroptera.*`), XDG directory names,
env vars used by hooks and templates (`CHIROPTERA_*`), the Luau API table,
translations, docs, the desktop entry, the logo and font asset file names, and
the tests. The Meson test suite must pass and the shell must start under
Hyprland.

### 4.2 Plugin API alias

`src/scripting/luau_host.cpp` registers the base library under `chiroptera`
and additionally binds the plugin API's former global name, from
`src/legacy/legacy_names.h`, to the same table. Plugin manifests keep their
`plugin_api` levels. Plugins already installed keep working from their
installed copies; new ones come from local and user-added sources.

### 4.3 Bar and panels

The top bar is configured in `config.toml`: workspaces left,
clock and active window center, tray, network, bluetooth, audio, battery,
and a control-center button right. The right sidebar is the built-in control
center. Launcher, notifications, OSDs, lock screen, dock, window switcher,
wallpaper manager, and settings GUI are the shell's own.

### 4.4 Left AI sidebar (plugin)

A Chiroptera plugin, `chiroptera/ai_sidebar`, in the chiroptera-dots
`chiroptera/plugins/` directory: a panel entry with a multiline input, a
scrollable markdown transcript, provider and model selects, and a clear
button. Streaming via `chiroptera.httpStream` against OpenAI-compatible
endpoints and Ollama; API keys read from `~/.config/chiroptera/secrets.toml`
(mode 0600), never from `config.toml`. A control-center shortcut and a bar
widget toggle it. Plugin-level settings: providers, default model, system
prompt.

### 4.5 Theme and branding

A Chiroptera palette under `~/.config/chiroptera/palettes/`, the bat logo
`assets/chiroptera.svg`, and the desktop entry name. Material You palettes are
generated from the wallpaper.

### 4.6 Later native work

Anything the plugin API cannot express (new surfaces, custom drawing, new
Wayland protocol use) is C++ in `chiroptera-shell`. None is planned for the
first release.

## 5. Dotfiles and user provisioning

The `chiroptera-dots` package installs `/usr/share/chiroptera/dots/` as the
pristine tree and the same trees into `/etc/skel/.config/`, so users created
by Calamares get them. `scripts/apply.sh` in the repo (installed as
`/usr/bin/chiroptera-dots`) copies from the pristine tree into the current
user's config without clobbering files that differ, and lists what it
skipped; `--force` overwrites; `--diff` shows differences.

Hyprland: the author's current `hyprland.conf` split, with `exec-once =
chiroptera --daemon`, IPC binds (`chiroptera msg panel-toggle launcher`,
`panel-toggle control-center`, `settings-toggle`, `window-switcher`, volume
and brightness), the Chiroptera layer rules for blur, and the settings-window
float rule. User overrides stay in `hypr/hyprland/user.conf`, sourced last.

Two behaviours the author keeps, both implemented in chiroptera-dots without
shell support:

- **Special-workspace toggles.** `scripts/chiroptera-toggle` (Python, stdlib
  only, installed as `/usr/bin/chiroptera-toggle`): for a named special workspace, launch the app into it if absent,
  move a running instance into it if configured, then
  `togglespecialworkspace`. Config in `chiroptera/toggles.toml` with entries
  for communication (Super+D), obsidian (Super+O), todo (Super+R), music
  (Super+M), sysmon (Ctrl+Shift+Escape), and the plain `specialws`
  (Super+S).
- **Super tap opens the launcher.** Press of `Super_L` arms a flag file in
  `$XDG_RUNTIME_DIR`, any other key or mouse button with Super held clears
  it (Hyprland `catchall` non-consuming binds), release of `Super_L` fires
  `chiroptera msg panel-toggle launcher` only if still armed. Implemented as
  `scripts/chiroptera-super-tap` and seven bind lines.

Personal files never enter any repo. Each repo has a `.gitignore` covering
them and a pre-commit hook that rejects files matching a secret pattern list.

## 6. Packaging and the pacman repository

### 6.1 Packages

| Package | Source | Contents |
|---|---|---|
| chiroptera-shell | chiroptera-shell tag | the `chiroptera` binary, `/usr/share/chiroptera/`, desktop entry, completions |
| chiroptera-dots | chiroptera-dots tag | `/usr/share/chiroptera/dots`, `/etc/skel` entries, `chiroptera-dots` apply script |
| chiroptera-greeter | chiroptera-shell tag, `greeter/` | the greetd login screen: greeter, its wlroots compositor, session wrapper, appearance-sync helper |
| chiroptera-meta | none | depends on everything a desktop needs, including linux-cachyos, cachyos-settings, ananicy-cpp, scx-manager |
| chiroptera-hwd | ChiropteraOS | hardware detection script and service |
| chiroptera-calamares-config | ChiropteraOS | Calamares settings, modules, branding |
| rebuilt AUR deps | AUR | calamares, and anything else the meta package pulls from AUR |

The shell PKGBUILD pins a git tag and builds with Meson (`just` recipes are
not required; plain `meson setup` and `meson install` suffice). A release is:
tag the source repo, bump `pkgver` here, push ChiropteraOS.

### 6.2 CI

Workflow `packages.yml` on push to main and on a schedule:

1. Start a clean `archlinux:base-devel` container.
2. Build every PKGBUILD in dependency order. Fail on `namcap` errors.
3. Sign each package with the repo GPG key from a CI secret.
4. `repo-add chiroptera.db.tar.gz` with signature.
5. Publish the repo directory to GitHub Pages.

### 6.3 Repository order

`pacman.conf` on installed systems, from top to bottom: `chiroptera`, the
CachyOS optimized repo for the detected CPU level (`cachyos-v3` or
`cachyos-v4` plus `cachyos-core-v3`/`cachyos-extra-v3` variants, or
`cachyos-znver4`), `cachyos`, then `core`, `extra`, `multilib`, and any user
repos such as `blackarch` last. The CachyOS signing key is installed by
`chiroptera-meta` from the `cachyos-keyring` package. Because pacman picks
by repo order, `chiroptera` packages always win, then CachyOS rebuilds,
then Arch.

### 6.4 Repo URL

One file holds the mirror: `iso/airootfs/etc/pacman.d/chiroptera-mirrorlist`.
The `chiroptera-meta` package installs the same file and the pacman.conf
snippet on target systems. Moving to Gitea means editing that file and
pointing step 5 at Gitea's Arch package registry.

## 7. ISO

### 7.1 Profile

Based on archiso `releng`. Changes:

- `packages.x86_64` adds hyprland, greetd, chiroptera-greeter, chiroptera-meta,
  chiroptera-shell, chiroptera-dots, chiroptera-hwd, calamares,
  chiroptera-calamares-config, linux-firmware, and the NVIDIA and AMD driver
  packages so the live session works on both.
- `pacman.conf` for the build includes the chiroptera repo and the CachyOS
  base repo only. The live session runs baseline x86-64 packages and the
  `linux-cachyos` kernel built for x86-64, because virtual machines and
  older CPUs may lack AVX2. Optimized repos are enabled on the target only.
- `airootfs` adds a `live` user with no password, greetd autologin into
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
enables greetd, NetworkManager, bluetooth. `shellprocess` runs
`chiroptera-hwd apply` in the target chroot.

### 7.3 Hardware detection (chiroptera-hwd)

Shell script with two commands: `detect` prints the package and service plan
as JSON, `apply` installs it. Detection from `lscpu` and `lspci -nn`:

- CPU vendor: `amd-ucode` or `intel-ucode`.
- CPU feature level from `/lib/ld-linux-x86-64.so.2 --help` output:
  x86-64-v4 with AVX-512 selects `cachyos-v4`, Zen 4 or newer selects
  `cachyos-znver4`, v3 with AVX2 selects `cachyos-v3`, anything lower keeps
  `cachyos` only. Writes the matching pacman.conf snippet and runs a full
  upgrade so v3 rebuilds replace baseline packages.
- NVIDIA GPU present: `nvidia-open`, `nvidia-utils`, `lib32-nvidia-utils`,
  and a Hyprland env snippet in `/etc/chiroptera/hypr-hwd.conf`. Hybrid with
  AMD or Intel adds the integrated driver and marks NVIDIA as secondary.
- AMD GPU: `mesa`, `vulkan-radeon`, `lib32-vulkan-radeon`.
- Intel GPU: `mesa`, `vulkan-intel`, `lib32-vulkan-intel`.
- Virtual machine: `qemu-guest-agent` or `virtualbox-guest-utils`, no
  proprietary drivers.

For NVIDIA the module package is the CachyOS prebuilt one for the selected
kernel, `linux-cachyos-nvidia-open`, so no DKMS build runs during install.
Stock `linux` and `nvidia-open` stay installed as a fallback boot entry.

Runnable on an already installed machine. The author's laptop, AMD Renoir plus
NVIDIA TU116 with nvidia-open, is the reference hybrid case and resolves to
`cachyos-v3` since Zen 2 has AVX2 but not AVX-512.

## 8. Performance layer

ChiropteraOS does not build a kernel or rebuild packages. It consumes the
CachyOS repositories, which are published for use on plain Arch.

- Kernel: `linux-cachyos` (EEVDF, Clang ThinLTO, AutoFDO and Propeller,
  1000 Hz, dynamic preemption, Cachy Sauce patches) as default boot entry.
  `linux` from Arch stays installed as fallback. `scx-manager` is installed so
  the user can switch to sched-ext schedulers such as scx_lavd at runtime.
- Userland: the optimized repo matching the CPU level, chosen by
  `chiroptera-hwd`. Packages there are built with LTO and, for core packages,
  PGO and BOLT.
- Tuning: `cachyos-settings` for sysctl, udev I/O schedulers, zram with zstd,
  transparent hugepage policy, systemd timeouts, journal cap, NVIDIA power
  management modprobe options, and audio realtime limits. `ananicy-cpp` with
  `cachyos-ananicy-rules` for process priorities.
- Local builds: `chiroptera-dots` ships an optional `makepkg.conf` with the
  v3 flags so AUR builds match, applied by `chiroptera-hwd` when the level is
  v3 or above.

Accepted costs, recorded from the discussion: CachyOS rebuilds may lag Arch
by up to a day for a given package, v3 and above binaries require AVX2 so a
disk cannot move to an older CPU, and the CachyOS signing key joins the
trust chain. Rollback is removing the repo entries and running
`pacman -Syuu`.

## 9. Error handling

- Shell: a failing plugin is isolated in its own Luau VM and logged; the
  bar must still appear. Missing secrets file disables the AI sidebar with a
  visible notice.
- Dots: `chiroptera-dots` never overwrites a changed file without `--force`
  and prints what it skipped.
- Packaging CI: any build or namcap failure fails the workflow and leaves the
  published repo untouched.
- Calamares: hwd failure is logged and the install continues; a first-boot
  notification tells the user to run `chiroptera-hwd apply`.
- hwd: unknown hardware installs only mesa and microcode, never guesses a
  proprietary driver. Unknown CPU level keeps baseline repos only.
- Kernel: if `linux-cachyos` fails to boot, the bootloader menu still offers
  stock `linux`.

## 10. Testing

- Shell: CI builds with Meson and runs the test suite (`meson test`); a nested Hyprland session starts `chiroptera` and
  fails if the bar layer does not appear within five seconds. Screenshots of
  bar and control center attached to runs.
- AI sidebar plugin: `chiroptera plugins lint` passes; a fake HTTP endpoint
  test checks streaming assembly of a reply.
- Packages: namcap plus a clean-container install of chiroptera-meta with only
  official repos and the chiroptera repo enabled.
- hwd: unit tests feed recorded `lscpu` and `lspci` output and assert the
  JSON plan. Fixtures: AMD-only, Intel-only, NVIDIA-only, AMD plus NVIDIA
  hybrid, QEMU, VirtualBox, and CPU levels v2, v3, v4, znver4.
- Performance: a benchmark script in `scripts/` records boot time, kernel
  compile time, and a browser startup on the laptop before and after the
  CachyOS layer, so the gain is measured rather than assumed.
- ISO nightly: build, boot in QEMU with OVMF, wait for the greeter, screenshot.
  Second job runs an unattended Calamares install to a disk image and boots
  the result to the login screen.
- Manual: `docs/install-checklist.md` run on the author's laptop before every
  release tag.

## 11. Build order

1. chiroptera-shell with the plugin-API alias, passing the Meson test
   suite, running on the laptop as the session shell. Package it.
2. chiroptera-dots from the laptop config, with Chiroptera binds; the
   `chiroptera-dots` apply script; the laptop runs from the repo.
3. Theme, logo, and bar composition: the Chiroptera look.
4. Packaging, CI, pacman repo on GitHub Pages.
5. chiroptera-hwd with tests, including CPU level detection and the CachyOS
   repo, kernel, and settings switch. Applied on the laptop, benchmarked
   before and after.
6. ISO with live desktop, greetd autologin, and Calamares; VM install end to
   end.
7. AI sidebar plugin.
8. Greeter rebrand: `chiroptera-greeter`. Done 2026-10-16, when the shell
   also stopped following the project it was forked from.

Steps 1 to 6 produce a bootable image that reinstalls the author's machine
with Chiroptera Shell. Each step gets its own implementation plan.
