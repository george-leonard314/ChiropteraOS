# Removing Caelestia

ChiropteraOS started from the Caelestia dotfiles and shell. As of this writing
nothing on this machine reads from them anymore — see "Evidence" below — so
the packages and leftover directories can be removed. Run these yourself,
they need root; nothing in this document has been run for you.

## Evidence nothing still uses Caelestia

Live config is symlinked entirely into `chiroptera-dots`, not `caelestia`:

```
$ for f in hypr fish foot btop fastfetch starship.toml uwsm; do readlink ~/.config/$f; done
/home/g/git/chiroptera-dots/config/hypr
/home/g/git/chiroptera-dots/config/fish
/home/g/git/chiroptera-dots/config/foot
/home/g/git/chiroptera-dots/config/btop
/home/g/git/chiroptera-dots/config/fastfetch
/home/g/git/chiroptera-dots/config/starship.toml
/home/g/git/chiroptera-dots/config/uwsm
```

No running process, Hyprland keybind, systemd user unit, or autostart/desktop
entry mentions `caelestia`:

```
$ pgrep -af caelestia | grep -vE 'pgrep|bash -c'          # (nothing)
$ hyprctl binds | grep -c caelestia                        # 0
$ systemctl --user list-units --all | grep -i caelestia    # (nothing)
$ systemctl --user list-unit-files | grep -i caelestia     # (nothing)
$ grep -rli caelestia ~/.config/hypr/*.conf ~/.config/uwsm # (nothing)
$ find ~/.config/autostart -iname '*caelestia*'            # (nothing)
$ grep -rli caelestia /usr/share/applications ~/.local/share/applications  # (nothing)
```

A whole-config text search (excluding the `caelestia` directory and any
`.pre-dots`/`.pre-noctalia-spike` backup) does turn up hits, all of them
inert:

- Editor/app history and logs that merely contain the word, because they
  logged this migration: VS Code `logs/`, `workspaceStorage/`, `History/`;
  Obsidian's custom dictionary; Claude's local session/audit files; Zen
  browser prefs. None of these are read by anything at session start; they
  don't matter.
- `~/.config/qt5ct/qt5ct.conf`, `~/.config/qt6ct/qt6ct.conf`, and
  `~/.config/qtengine/config.json` point their `color_scheme_path` at files
  literally named `caelestia.colors`. Those `.colors` files live under
  `~/.config/qt5ct/colors/`, `~/.config/qt6ct/colors/`, and
  `~/.config/qtengine/`, **not** inside `~/.config/caelestia`, and no
  package owns them (`pacman -Qo` on each says "No package owns"). They're
  leftover output from the old shell's theming step, still wired up because
  the new shell hasn't regenerated a color scheme since the cutover.
  `chiroptera-shell`'s own Qt template (`/usr/share/chiroptera/assets/templates/qt/undo.sh`)
  writes to `qt5ct/colors/chiroptera.conf` / `qt6ct/colors/chiroptera.conf` —
  a different filename — so the next time a wallpaper/theme is applied,
  these `*.conf` files get regenerated and the `.conf` configs will point at
  them instead. **This is a cosmetic loose end, not a blocker**: removing
  the `caelestia` packages and directories below does not touch these three
  files at all, because they sit outside every path being removed.

The four Caelestia directories:

```
$ du -sh ~/.config/caelestia ~/.local/state/caelestia ~/.cache/caelestia ~/.local/share/caelestia
100K    /home/g/.config/caelestia
48K     /home/g/.local/state/caelestia
123M    /home/g/.cache/caelestia
1.7M    /home/g/.local/share/caelestia
```

`~/.config/caelestia` and `~/.local/share/caelestia` are both **plain
directories now**, not symlinks to each other — that changed since this
migration was planned. `~/.local/share/caelestia` is the old dotfiles
checkout; its contents now live in `chiroptera-dots`.

## 1. The shared dependencies are already covered

`caelestia-meta` depends on:

```
caelestia-cli caelestia-shell hyprland xdg-desktop-portal-hyprland
xdg-desktop-portal-gtk hyprpicker wl-clipboard cliphist inotify-tools
app2unit wireplumber trash-cli foot fish eza fastfetch starship btop jq
adw-gtk-theme papirus-icon-theme qt5ct-kde qt6ct-kde ttf-jetbrains-mono-nerd
```

Every one of those except the two Caelestia-only packages is also required
by `chiroptera-meta` — verified against the real dependency graph, not just
by comparing package-name lists:

```
$ pacman -Qi qt5ct-kde | grep -E 'Required By|Provides'
Provides        : qt5ct
Required By     : caelestia-meta  chiroptera-meta
```

`chiroptera-meta` depends on `qt5ct`/`qt6ct` by name; the installed packages
are `qt5ct-kde`/`qt6ct-kde`, which `Provides:` those names, so pacman
resolves it correctly and both metapackages show up in `Required By`. Every
other shared package (checked individually with `pacman -Qi`) shows the same
pattern: `Required By: caelestia-meta chiroptera-meta`.

**No gap was found.** Every package `caelestia-meta` pulls in that the
desktop still needs is also a `chiroptera-meta` dependency.

`chiroptera-meta` is **already installed** on this machine (installed
2026-09-09), so this protection is already in place — a live dry run
confirms it:

```
$ pacman -Rs --print caelestia-meta caelestia-shell caelestia-cli
caelestia-meta-r151.cadf1e2-1
caelestia-shell-2.4.0-1
ttf-rubik-vf-2.3.0-3
ttf-cascadia-code-nerd-3.5.1-2
quickshell-git-0.3.1.r10.g2d3b3e9-1
cpptrace-1.0.4-2
libdwarf-1:2.3.2-1
power-profiles-daemon-0.30-1
libcava-1.0.0-1
aubio-0.4.9-25
caelestia-cli-1.1.2-1
python-materialyoucolor-3.0.2-1
python-pillow-12.3.0-1
gpu-screen-recorder-6.1.0-1
fuzzel-1.15.0-1
resvg-0.48.1-1
dart-sass-1.104.0-1
swappy-1.8.0-1
```

None of `foot`, `fish`, `fastfetch`, `starship`, `btop`, `wireplumber`, the
portals, the clipboard tools, the fonts, or the GTK/Qt themes appear —
`chiroptera-meta` already holds them. The packages that *would* go
(`fuzzel`, `swappy`, `quickshell-git`, `power-profiles-daemon`, ...) belong
to Caelestia's own Quickshell-based UI, which `chiroptera-shell` replaced
with a standalone binary (`pacman -Qi chiroptera-shell` shows no dependency
on Quickshell at all). The one remaining reference to `fuzzel`/`swappy` in
`chiroptera-dots` — a Hyprland `windowrule` matching their window classes in
`config/hypr/hyprland/rules.conf` — is a harmless leftover; it never
launches or requires either binary.

**Route A — if `chiroptera-meta` is already installed** (true on this
machine right now): skip straight to step 2, the dry run above already
proves it's safe.

**Route B — if you ever do this before installing `chiroptera-meta`**, mark
the shared dependencies explicit first so a naive `pacman -Rns` doesn't take
them with it:

```sh
sudo pacman -D --asexplicit xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  hyprpicker wl-clipboard cliphist inotify-tools app2unit wireplumber trash-cli \
  foot fish eza fastfetch starship btop jq adw-gtk-theme papirus-icon-theme \
  qt5ct-kde qt6ct-kde ttf-jetbrains-mono-nerd
```

(`pacman -D` has no dry-run/`--print` mode — it only flips the installed
metadata flag, it can't remove or install anything — so this was checked by
confirming every name above resolves to a currently installed package and
reading its current `Install Reason`/`Required By` rather than by a
simulated run.)

## 2. Remove the packages

```sh
sudo pacman -Rns caelestia-meta caelestia-shell caelestia-cli
```

Per the dry run above, this also takes: `ttf-rubik-vf`,
`ttf-cascadia-code-nerd`, `quickshell-git` (plus its `cpptrace`/`libdwarf`
dependencies), `power-profiles-daemon`, `libcava`, `aubio`,
`python-materialyoucolor`, `python-pillow`, `gpu-screen-recorder`, `fuzzel`,
`resvg`, `dart-sass`, and `swappy` — 18 packages, about **352 MiB**
(`caelestia-shell` 17.9 MiB + `caelestia-cli` 1.3 MiB +
`ttf-cascadia-code-nerd` 99.0 MiB + `quickshell-git` 194.9 MiB + the rest
totaling roughly 39 MiB). None of them are used by the live Chiroptera
session (see above).

Installing `chiroptera-meta` (if not already done) accomplishes the same
protection as the `--asexplicit` step in section 1, since it now owns the
same shared dependencies.

## 3. Remove the leftover directories

Check first that nothing you want is inside:

```sh
ls ~/.config/caelestia ~/.local/state/caelestia ~/.local/share/caelestia
rm -rf ~/.cache/caelestia                    # ~123 MB image cache, always safe
rm -rf ~/.config/caelestia ~/.local/state/caelestia ~/.local/share/caelestia
```

`~/.local/share/caelestia` was the old dotfiles checkout. Its contents now
live in `chiroptera-dots`, so removing it is safe once `./install.sh --link`
has run and the session works (confirmed: launcher, screenshots, the `faah`
error sound, media and brightness keys).

**Do this after you're sure the session works, not before**: most of the
`.pre-dots-*` backups left in `~/.config` (see below) are themselves
symlinks pointing *into* `~/.local/share/caelestia` (e.g.
`~/.config/hypr.pre-dots-20260909-214034 -> /home/g/.local/share/caelestia/hypr`).
Deleting `~/.local/share/caelestia` first turns those into dangling
symlinks — harmless, but it means you lose the ability to inspect what the
old config actually contained. Look at them now if you ever want to compare
before removing this directory.

## 4. Backups

`install.sh` backed up every replaced config path as
`<path>.pre-dots-<timestamp>` in `~/.config` before symlinking it into
`chiroptera-dots`. On this machine that's:

```
chiroptera.pre-dots-20260909-214034   (a real directory — a prior config, not a symlink)
foot.pre-dots-20260909-214034         -> ~/.local/share/caelestia/foot
fish.pre-dots-20260909-214034         -> ~/.local/share/caelestia/fish
btop.pre-dots-20260909-214034         -> ~/.local/share/caelestia/btop
starship.toml.pre-dots-20260909-214034 -> ~/.local/share/caelestia/starship.toml
hypr.pre-dots-20260909-214034         -> ~/.local/share/caelestia/hypr
uwsm.pre-dots-20260909-214034         -> ~/.local/share/caelestia/uwsm
fastfetch.pre-dots-20260909-214034    -> ~/.local/share/caelestia/fastfetch
```

(`~/.config/caelestia/hypr-user.conf.pre-dots-*` and
`.pre-noctalia-spike` are separate, older backups *inside* the `caelestia`
config directory itself — they go away with step 3's `rm -rf
~/.config/caelestia` and need no separate handling.)

These are safe to delete once you're confident the migration is solid — i.e.
after you've already removed `~/.local/share/caelestia` in step 3, since
most of them are just symlinks pointing at it anyway:

```sh
find ~/.config -maxdepth 1 -name '*.pre-dots-*' -exec rm -rf {} +
```

Note the trailing `-*`: the timestamp is part of the name
(`foot.pre-dots-20260909-214034`, not `foot.pre-dots`), so a pattern of
plain `*.pre-dots` matches nothing and silently leaves every backup in
place.
