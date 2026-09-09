# Step 2: chiroptera-dots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture the author's live laptop configuration into a `chiroptera-dots` repository, replace every remaining caelestia reference with Chiroptera equivalents, package it as `chiroptera-dots` plus a `chiroptera-meta` dependency set, and move the laptop onto the new tree so the caelestia packages and directories can be removed.

**Architecture:** `chiroptera-dots` is a fresh repository with no upstream, seeded from the files the author actually uses. Configs live under a `config/` tree mirroring `$XDG_CONFIG_HOME`. An `install.sh` links that tree into the user's config directory for development, or copies it for a fresh install; the package ships the same tree to `/usr/share/chiroptera/dots` and `/etc/skel`. Hyprland keybinds are rewritten from caelestia global shortcuts to Chiroptera IPC. `chiroptera-meta` depends on the shell, the dots, and the applications the desktop expects.

**Tech Stack:** git, bash, Hyprland 0.56 config, fish, TOML, JSON, makepkg/pacman, GitHub CLI.

**Spec:** `docs/superpowers/specs/2026-09-09-chiroptera-os-design.md` sections 3.2, 5, 6.1, 11 step 2.

## Global Constraints

- Repo `chiroptera-dots` on GitHub user `george-leonard314`, **private**, created fresh. No upstream remote: caelestia is out of the project. Local path `~/git/chiroptera-dots`. Git auth is HTTPS via the `gh` credential helper.
- Personal files never enter the repo: `hypr/monitors.conf`, `hypr/monitors.lua`, `fish/fish_variables`, anything under `~/.config/chiroptera/secrets*`, browser profiles, history, tokens, `*.bak`, `*.pre-chiroptera`, `*copy*.txt`.
- Generated files never enter the repo: `foot/themes/`, `fastfetch/themes/`, `hypr/scheme/current.conf`, `btop/themes/`, `~/.local/share/chiroptera/branding/fastfetch-logo.{svg,png}`. These are template output written by the shell.
- Zero occurrences of `caelestia` in the committed tree, except the word inside a `CREDITS.md` acknowledgement line marked `<!-- keep -->`.
- The author's laptop keeps working throughout. Every replaced file gets a `.pre-dots` backup, and every step that changes the live session is reversible by the rollback command in Task 7.
- The `faah` error sound and its red border flash are the author's own work and must be preserved verbatim, including `faah.oga`.
- Package `chiroptera-dots` version `0.1.0`, `chiroptera-meta` version `0.1.0`, both `arch=('any')`, license MIT.
- Nothing removes the caelestia packages in this step; Task 7 only proves they are no longer referenced.
- Sudo has no terminal in this environment. Any `pacman -U` step is handed to the user, as in step 1.

---

## File Structure

```
chiroptera-dots/
  README.md                     what this is, how to install
  CREDITS.md                    upstream acknowledgements (caelestia, Noctalia)
  install.sh                    --link (dev) | --copy (fresh) | --diff | --force
  config/
    hypr/
      hyprland.conf             top-level, sources the rest
      hyprland/{env,general,input,misc,animations,decoration,group,execs,rules,gestures,keybinds}.conf
      variables.conf            $terminal, $browser, keybind variables
      workspaces.conf
      scripts/wsaction.fish
      scheme/default.conf       palette placeholder the shell overwrites
    chiroptera/
      config.toml               templates, widget icons, fastfetch logo hook
      templates/terminal-sequences
      templates/fastfetch-logo.svg
    fish/
      config.fish
      conf.d/faah.fish          error sound + border flash
      sounds/faah.oga
      functions/*.fish
      completions/
    foot/foot.ini
    btop/btop.conf
    fastfetch/config.jsonc
    starship.toml
    uwsm/{env,env-hyprland}
  branding/
    chiroptera-bat.svg  chiroptera-bat-icon.svg  chiroptera-bat-alt.svg
    dragon-mono.svg
    wallpapers/chiroptera-default.png
  bin/
    chiroptera-super-tap        Super tap opens the launcher
    chiroptera-toggle           special-workspace app toggles
```

**ChiropteraOS** gains `pkgs/chiroptera-dots/PKGBUILD` and `pkgs/chiroptera-meta/PKGBUILD`.

---

### Task 1: Bootstrap chiroptera-dots and seed it from the laptop

**Files:**
- Create: GitHub repo `george-leonard314/chiroptera-dots` (private)
- Create: `~/git/chiroptera-dots/` with `config/`, `branding/`, `bin/`, `.gitignore`

**Interfaces:**
- Produces: a repo whose `config/` tree mirrors the author's live `$XDG_CONFIG_HOME` for the files listed above, with personal and generated files excluded. Nothing on the laptop is modified.

- [ ] **Step 1: Create the repo and the skeleton**

```bash
gh repo create george-leonard314/chiroptera-dots --private \
  --description "ChiropteraOS dotfiles: Hyprland, Chiroptera Shell, fish, foot, fastfetch"
cd ~/git && git clone https://github.com/george-leonard314/chiroptera-dots.git
cd chiroptera-dots && mkdir -p config/{hypr/hyprland,hypr/scripts,hypr/scheme,chiroptera/templates,fish/conf.d,fish/functions,fish/sounds,fish/completions,foot,btop,fastfetch,uwsm} branding/wallpapers bin
git remote -v
```

Expected: two remote lines for `origin` only, both HTTPS to `george-leonard314/chiroptera-dots.git`.

- [ ] **Step 2: Write .gitignore before copying anything**

```bash
cd ~/git/chiroptera-dots && cat > .gitignore <<'EOF'
# Personal: monitor layout, shell variables, secrets
config/hypr/monitors.conf
config/hypr/monitors.lua
config/fish/fish_variables
config/chiroptera/secrets*

# Generated by the shell's template engine
config/foot/themes/
config/fastfetch/themes/
config/btop/themes/
config/hypr/scheme/current.conf
branding/fastfetch-logo.*

# Backups and editor leftovers
*.bak
*.pre-chiroptera
*.pre-dots
*.pre-noctalia-spike
*~
EOF
git add .gitignore && git commit -m "Add .gitignore for personal, generated, and backup files"
```

- [ ] **Step 3: Seed the tree from the laptop**

Copy only the listed files. `-L` dereferences the caelestia symlinks so real content lands in the repo.

```bash
cd ~/git/chiroptera-dots
L=~/.local/share/caelestia
cp -L $L/hypr/hyprland.conf $L/hypr/variables.conf $L/hypr/workspaces.conf config/hypr/
cp -L $L/hypr/hyprland/*.conf config/hypr/hyprland/
rm -f config/hypr/hyprland/*.bak-*
cp -L $L/hypr/scripts/wsaction.fish config/hypr/scripts/
cp -L $L/hypr/scheme/default.conf config/hypr/scheme/
cp -L $L/fish/config.fish config/fish/
cp -L $L/fish/conf.d/faah.fish config/fish/conf.d/
cp -L $L/fish/sounds/faah.oga config/fish/sounds/
cp -rL $L/fish/functions/. config/fish/functions/
cp -rL $L/fish/completions/. config/fish/completions/ 2>/dev/null || true
cp -L $L/foot/foot.ini config/foot/
cp -L $L/btop/btop.conf config/btop/
cp -L $L/fastfetch/config.jsonc config/fastfetch/
cp -L $L/starship.toml config/
cp -L $L/uwsm/env $L/uwsm/env-hyprland config/uwsm/ 2>/dev/null || true
cp ~/.config/chiroptera/config.toml config/chiroptera/
cp ~/.config/chiroptera/templates/terminal-sequences ~/.config/chiroptera/templates/fastfetch-logo.svg config/chiroptera/templates/
cp ~/.local/share/chiroptera/branding/chiroptera-bat.svg \
   ~/.local/share/chiroptera/branding/chiroptera-bat-icon.svg \
   ~/.local/share/chiroptera/branding/chiroptera-bat-alt.svg \
   ~/.local/share/chiroptera/branding/dragon-mono.svg branding/
cp ~/Pictures/Wallpapers/chiroptera-default.png branding/wallpapers/
cp ~/.local/bin/chiroptera-super-tap ~/.local/bin/chiroptera-toggle bin/
chmod +x bin/*
find config branding bin -type f | wc -l
```

Expected: a file count of at least 35. If a `cp` fails because a source is missing, report which one; do not substitute a different file.

- [ ] **Step 4: Verify nothing personal or generated was copied**

```bash
cd ~/git/chiroptera-dots
git add -A --dry-run 2>/dev/null | grep -cE 'monitors\.(conf|lua)|fish_variables|themes/|current\.conf|\.bak|copy[0-9]*\.txt'
ls config/fastfetch/ config/foot/ config/hypr/
grep -rn 'password\|token\|secret\|api[_-]key' config/ --include='*' -i | grep -v 'secrets\*' | head -5
```

Expected: the first count is `0`; the listings show no `themes` directory and no `monitors.conf`; the secret grep prints nothing.

- [ ] **Step 5: Commit the untouched seed**

```bash
cd ~/git/chiroptera-dots && git add -A && git commit -m "Seed dots from the laptop configuration

Verbatim copy of the live config before any Chiroptera rewrite, so the
following commit shows exactly what the migration changes."
git show --stat HEAD | tail -3
```

---

### Task 2: Rewrite the Hyprland config for Chiroptera

**Files:**
- Modify: `config/hypr/hyprland.conf`, `config/hypr/hyprland/{execs,keybinds,rules,gestures}.conf`, `config/hypr/variables.conf`
- Create: `config/hypr/hyprland/user.conf` (empty override file, sourced last)
- Create: `chiroptera/check-dots.sh` (assertion script)

**Interfaces:**
- Consumes: Task 1 seed.
- Produces: a Hyprland tree with zero `caelestia` references. Autostart is `chiroptera --daemon`. Every keybind uses Chiroptera IPC (`chiroptera msg ...`) or one of the two helper scripts. `check-dots.sh` exits 0 only when no `caelestia` token survives outside the credits file.

The mapping from caelestia global shortcuts to Chiroptera IPC, derived from `chiroptera msg --help`:

| caelestia | Chiroptera |
|---|---|
| `global, caelestia:launcher` + the nine `launcherInterrupt` binds | the three `chiroptera-super-tap` binds (press/release/catchall) |
| `global, caelestia:session` | `exec, chiroptera msg panel-toggle session` |
| `global, caelestia:lock` | `exec, chiroptera msg session lock` |
| `global, caelestia:clearNotifs` | `exec, chiroptera msg notification-clear-active` |
| `global, caelestia:showall` | `exec, chiroptera msg panel-toggle control-center` |
| `global, caelestia:brightnessUp` / `Down` | `exec, chiroptera msg brightness-up` / `brightness-down` |
| `global, caelestia:mediaToggle` / `Next` / `Prev` / `Stop` | `exec, chiroptera msg media toggle` / `next` / `previous` / `stop` |
| `global, caelestia:screenshotFreeze` | `exec, chiroptera msg screenshot-region` |
| `global, caelestia:screenshot` | `exec, chiroptera msg screenshot-annotate` |
| `exec, caelestia shell -d` | `exec, chiroptera --daemon` |
| `exec, qs -c caelestia kill` | `exec, pkill -x chiroptera` |
| `exec, caelestia clipboard` / `-d` | `exec, chiroptera msg panel-toggle clipboard` |
| `exec, caelestia emoji -p` | `exec, chiroptera msg panel-toggle launcher` (emoji provider prefix `/emo`) |
| `exec, caelestia record` / `-s` / `-r` | `exec, chiroptera msg plugin chiroptera/screen_recorder:service all toggle` |
| `exec, caelestia toggle <name>` | `exec, ~/.local/bin/chiroptera-toggle <name>` |
| `exec, caelestia resizer pip` | dropped: no Chiroptera equivalent |
| `layerrule ... caelestia-*` | `layerrule ... chiroptera-*`, matching the shell's namespaces |

- [ ] **Step 1: Write the check script (the test)**

```bash
cd ~/git/chiroptera-dots && mkdir -p chiroptera && cat > chiroptera/check-dots.sh <<'EOF'
#!/usr/bin/env bash
# Fails if a caelestia reference survives, if a personal file is tracked, or if a
# keybind points at a command that does not exist.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
status=0

leftovers=$(grep -rn -i 'caelestia' config branding bin 2>/dev/null | grep -v '<!-- keep -->' || true)
if [ -n "$leftovers" ]; then
  echo "check-dots: caelestia references remain:" >&2; echo "$leftovers" >&2; status=1
fi

personal=$(git ls-files | grep -E 'monitors\.(conf|lua)|fish_variables|secrets|\.bak$|\.pre-' || true)
if [ -n "$personal" ]; then
  echo "check-dots: personal or backup files are tracked:" >&2; echo "$personal" >&2; status=1
fi

generated=$(git ls-files | grep -E 'config/(foot|fastfetch|btop)/themes/|scheme/current\.conf' || true)
if [ -n "$generated" ]; then
  echo "check-dots: generated files are tracked:" >&2; echo "$generated" >&2; status=1
fi

# Every `chiroptera msg <cmd>` in the keybinds must be a real IPC command.
if command -v chiroptera >/dev/null; then
  valid=$(chiroptera msg --help 2>&1 | grep -E '^\s{2}[a-z]' | awk '{print $1}')
  used=$(grep -ohE 'chiroptera msg [a-z-]+' config/hypr -r | awk '{print $3}' | sort -u)
  for cmd in $used; do
    grep -qx "$cmd" <<<"$valid" || { echo "check-dots: unknown IPC command '$cmd'" >&2; status=1; }
  done
fi

[ "$status" -eq 0 ] && echo "check-dots: ok"
exit "$status"
EOF
chmod +x chiroptera/check-dots.sh && chiroptera/check-dots.sh; echo "exit=$?"
```

Expected: a list of caelestia references from `keybinds.conf`, `execs.conf`, `rules.conf`, `gestures.conf`, and `hyprland.conf`, then `exit=1`.

- [ ] **Step 2: Rewrite hyprland.conf and execs.conf**

In `config/hypr/hyprland.conf`, replace the `$cConf = ~/.config/caelestia` variable with `$cConf = ~/.config/chiroptera`, and change the two `hypr-vars.conf` / `hypr-user.conf` source lines to source `$hypr/hyprland/user.conf` instead, created below. In `config/hypr/hyprland/execs.conf`, delete the `caelestia resizer -d` line and replace `caelestia shell -d` with `chiroptera --daemon`.

```bash
cd ~/git/chiroptera-dots
sed -i 's|\$cConf = ~/.config/caelestia|$cConf = ~/.config/chiroptera|' config/hypr/hyprland.conf
sed -i '/caelestia resizer -d/d; s|exec-once = caelestia shell -d|exec-once = chiroptera --daemon|' config/hypr/hyprland/execs.conf
python3 - <<'EOF'
from pathlib import Path
p = Path("config/hypr/hyprland.conf"); s = p.read_text()
s = s.replace("exec = mkdir -p $cConf && touch -a $cConf/hypr-vars.conf\nsource = $cConf/hypr-vars.conf\n", "")
s = s.replace("exec = mkdir -p $cConf && touch -a $cConf/hypr-user.conf\nsource = $cConf/hypr-user.conf\n",
              "# User overrides, sourced last so they win.\nsource = $hl/user.conf\n")
p.write_text(s); print("hyprland.conf rewritten")
EOF
printf '# Personal overrides for this machine. Not tracked upstream.\n' > config/hypr/hyprland/user.conf
grep -n 'chiroptera\|caelestia' config/hypr/hyprland.conf config/hypr/hyprland/execs.conf
```

Expected: `$cConf = ~/.config/chiroptera`, `source = $hl/user.conf`, one `exec-once = chiroptera --daemon`, and no caelestia line.

- [ ] **Step 3: Rewrite keybinds.conf**

Apply the mapping table above. The nine `launcherInterrupt` binds and the `caelestia:launcher` bind are replaced by the Super-tap block; the rest are one-for-one.

```bash
cd ~/git/chiroptera-dots && python3 - <<'PY'
import re
from pathlib import Path
p = Path("config/hypr/hyprland/keybinds.conf"); s = p.read_text()

supertap = """# Super tap opens the launcher: press arms, any other Super chord cancels, release fires.
bindi  = Super, Super_L, exec, ~/.local/bin/chiroptera-super-tap press
bindri = Super, Super_L, exec, ~/.local/bin/chiroptera-super-tap release
bindin = Super, catchall, exec, ~/.local/bin/chiroptera-super-tap interrupt
bindin = Super, mouse:272, exec, ~/.local/bin/chiroptera-super-tap interrupt
bindin = Super, mouse:273, exec, ~/.local/bin/chiroptera-super-tap interrupt
bindin = Super, mouse_up, exec, ~/.local/bin/chiroptera-super-tap interrupt
bindin = Super, mouse_down, exec, ~/.local/bin/chiroptera-super-tap interrupt
"""
# Drop every launcher/interrupt bind, then insert the Super-tap block once in their place.
lines, out, inserted = s.splitlines(True), [], False
for line in lines:
    if "caelestia:launcherInterrupt" in line or "caelestia:launcher" in line:
        if not inserted:
            out.append(supertap); inserted = True
        continue
    out.append(line)
s = "".join(out)

pairs = [
    (r"global, caelestia:session",            "exec, chiroptera msg panel-toggle session"),
    (r"global, caelestia:clearNotifs",        "exec, chiroptera msg notification-clear-active"),
    (r"global, caelestia:showall",            "exec, chiroptera msg panel-toggle control-center"),
    (r"global, caelestia:lock",               "exec, chiroptera msg session lock"),
    (r"global, caelestia:brightnessUp",       "exec, chiroptera msg brightness-up"),
    (r"global, caelestia:brightnessDown",     "exec, chiroptera msg brightness-down"),
    (r"global, caelestia:mediaToggle",        "exec, chiroptera msg media toggle"),
    (r"global, caelestia:mediaNext",          "exec, chiroptera msg media next"),
    (r"global, caelestia:mediaPrev",          "exec, chiroptera msg media previous"),
    (r"global, caelestia:mediaStop",          "exec, chiroptera msg media stop"),
    (r"global, caelestia:screenshotFreeze",   "exec, chiroptera msg screenshot-region"),
    (r"global, caelestia:screenshot",         "exec, chiroptera msg screenshot-annotate"),
    (r"exec, caelestia shell -d",             "exec, chiroptera --daemon"),
    (r"exec, qs -c caelestia kill; sleep \.1; caelestia shell -d", "exec, pkill -x chiroptera; sleep .3; chiroptera --daemon"),
    (r"exec, qs -c caelestia kill",           "exec, pkill -x chiroptera"),
    (r"exec, pkill fuzzel \|\| caelestia clipboard -d", "exec, chiroptera msg panel-toggle clipboard"),
    (r"exec, pkill fuzzel \|\| caelestia clipboard",    "exec, chiroptera msg panel-toggle clipboard"),
    (r"exec, pkill fuzzel \|\| caelestia emoji -p",     "exec, chiroptera msg panel-toggle launcher"),
    (r"exec, caelestia record -s",            "exec, chiroptera msg plugin chiroptera/screen_recorder:service all toggle"),
    (r"exec, caelestia record -r",            "exec, chiroptera msg plugin chiroptera/screen_recorder:service all replay-toggle"),
    (r"exec, caelestia record",               "exec, chiroptera msg plugin chiroptera/screen_recorder:service all toggle"),
    (r"exec, caelestia toggle ([a-z]+)",      r"exec, ~/.local/bin/chiroptera-toggle \1"),
]
for pat, rep in pairs:
    s = re.sub(pat, rep, s)

# The resizer has no Chiroptera equivalent: drop the bind, keep the key free.
s = re.sub(r"^.*caelestia resizer pip.*\n", "", s, flags=re.M)
p.write_text(s)
left = [l for l in s.splitlines() if "caelestia" in l]
print("remaining caelestia lines in keybinds.conf:", len(left))
for l in left: print("  ", l)
PY
```

Expected: `remaining caelestia lines in keybinds.conf: 1`, and the one line printed is the comment referencing upstream issue numbers. Delete that comment by hand in the next step.

- [ ] **Step 4: Rewrite rules.conf and gestures.conf, clear the last comment**

```bash
cd ~/git/chiroptera-dots
sed -i 's/caelestia-(border-exclusion|area-picker)/chiroptera-(bar-.*|panel|attached-panel)/; s/caelestia-(drawers|background)/chiroptera-(panel|attached-panel|osd|notification)/; s/caelestia-drawers/chiroptera-panel/g' config/hypr/hyprland/rules.conf
sed -i 's|exec, caelestia toggle specialws|exec, ~/.local/bin/chiroptera-toggle specialws|' config/hypr/hyprland/gestures.conf
sed -i '/caelestia-dots\/caelestia#/d' config/hypr/hyprland/keybinds.conf
chiroptera/check-dots.sh; echo "exit=$?"
```

Expected: `check-dots: ok`, `exit=0`. If the IPC check reports an unknown command, the mapping table has a typo; fix the keybind, not the check.

- [ ] **Step 5: Verify Hyprland parses the tree**

```bash
cd ~/git/chiroptera-dots
cp -r config/hypr /tmp/claude-1000/hypr-test && sed -i 's|source = \$hypr/monitors.conf||' /tmp/claude-1000/hypr-test/hyprland.conf
hyprctl configerrors | grep -c . 
grep -c 'chiroptera msg' config/hypr/hyprland/keybinds.conf
grep -rn 'bindi\|bindri\|bindin' config/hypr/hyprland/keybinds.conf | head -3
```

Expected: the live config still has `0` errors (this step does not load the new tree; Task 7 does), at least 12 `chiroptera msg` binds, and the three Super-tap bind kinds present.

- [ ] **Step 6: Commit**

```bash
cd ~/git/chiroptera-dots && git add -A && git commit -m "Rewrite the Hyprland config for Chiroptera

Autostart, keybinds, layer rules and gestures move from caelestia global
shortcuts to Chiroptera IPC and the two helper scripts. Adds user.conf for
machine-local overrides and chiroptera/check-dots.sh to assert the tree stays
free of caelestia references, personal files and generated files."
```

---

### Task 3: Clean the remaining configs and write the installer

**Files:**
- Modify: `config/fish/config.fish`, `config/fastfetch/config.jsonc`, `config/chiroptera/config.toml`, `config/foot/foot.ini`, `config/btop/btop.conf`
- Create: `install.sh`, `README.md`, `CREDITS.md`

**Interfaces:**
- Consumes: Task 2 tree.
- Produces: `install.sh` with four modes: `--link` symlinks each config entry to the repo (development, the author's laptop), `--copy` copies without overwriting an existing changed file, `--force` overwrites, `--diff` lists differences. It always backs up a replaced path to `<path>.pre-dots`. Paths inside the tree reference `~/.config/chiroptera` and `~/.local/share/chiroptera`, never caelestia.

- [ ] **Step 1: Fix the remaining config references**

```bash
cd ~/git/chiroptera-dots
sed -i 's|~/.local/state/caelestia/sequences.txt|~/.cache/terminal-sequences|; s|\$XDG_CONFIG_HOME/caelestia|$XDG_CONFIG_HOME/chiroptera|g; s|\$HOME/.config/caelestia|$HOME/.config/chiroptera|g' config/fish/config.fish
sed -i 's/"color_theme = \"caelestia\""/"color_theme = \"chiroptera\""/; s/^color_theme = .*/color_theme = "chiroptera"/' config/btop/btop.conf
sed -i 's|include=.*themes/caelestia|include=~/.config/foot/themes/chiroptera|' config/foot/foot.ini
python3 - <<'EOF'
import json
from pathlib import Path
p = Path("config/fastfetch/config.jsonc"); c = json.loads(p.read_text())
# The logo is regenerated by the shell's template hook; ship the path, not the file.
c["logo"]["source"] = "~/.local/share/chiroptera/branding/fastfetch-logo.png"
p.write_text(json.dumps(c, indent=2, ensure_ascii=False) + "\n")
print("fastfetch logo path:", c["logo"]["source"])
EOF
grep -rn -i caelestia config/ | grep -v '<!-- keep -->' | head
```

Expected: the fastfetch logo path printed, and the grep prints nothing.

- [ ] **Step 2: Write install.sh**

```bash
cd ~/git/chiroptera-dots && cat > install.sh <<'EOF'
#!/usr/bin/env bash
# Install the ChiropteraOS dotfiles into $XDG_CONFIG_HOME.
#
#   ./install.sh --link    symlink each entry to this checkout (development)
#   ./install.sh --copy    copy, skipping anything you have changed
#   ./install.sh --force   copy, overwriting
#   ./install.sh --diff    show what differs, change nothing
#
# A replaced path is backed up once as <path>.pre-dots.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cfg=${XDG_CONFIG_HOME:-$HOME/.config}
data=${XDG_DATA_HOME:-$HOME/.local/share}
mode=${1:---copy}

entries=(hypr chiroptera fish foot btop fastfetch starship.toml uwsm)

backup() { [ -e "$1" ] && [ ! -e "$1.pre-dots" ] && cp -a "$1" "$1.pre-dots" || true; }

case "$mode" in
  --diff)
    for e in "${entries[@]}"; do
      diff -rq "$here/config/$e" "$cfg/$e" 2>&1 | sed "s|$here/config/||;s|$cfg/||" || true
    done
    exit 0 ;;
  --link|--copy|--force) ;;
  *) echo "usage: $0 [--link|--copy|--force|--diff]" >&2; exit 2 ;;
esac

mkdir -p "$cfg" "$data/chiroptera" "$HOME/.local/bin" "$HOME/Pictures/Wallpapers"

for e in "${entries[@]}"; do
  src="$here/config/$e"; dst="$cfg/$e"
  [ -e "$src" ] || continue
  if [ "$mode" = "--link" ]; then
    backup "$dst"; rm -rf "$dst"; ln -s "$src" "$dst"; echo "linked  $dst"
  elif [ -e "$dst" ] && [ "$mode" != "--force" ] && ! diff -rq "$src" "$dst" >/dev/null 2>&1; then
    echo "skipped $dst (differs; --force to overwrite)"
  else
    backup "$dst"; rm -rf "$dst"; cp -a "$src" "$dst"; echo "copied  $dst"
  fi
done

# Branding and helper scripts are shared regardless of mode.
mkdir -p "$data/chiroptera/branding"
cp -a "$here"/branding/*.svg "$data/chiroptera/branding/"
cp -a "$here"/branding/wallpapers/. "$HOME/Pictures/Wallpapers/"
install -m755 "$here"/bin/* "$HOME/.local/bin/"
echo "installed branding, wallpapers and helper scripts"

echo
echo "Done. Reload with:  hyprctl reload && chiroptera msg config-reload"
EOF
chmod +x install.sh && ./install.sh --diff | head -5; echo "diff exit=$?"
```

Expected: the diff mode runs and exits 0, listing differences between the repo and the live config (there will be many, since the live config still points at caelestia).

- [ ] **Step 3: Write README.md and CREDITS.md**

```bash
cd ~/git/chiroptera-dots && cat > README.md <<'EOF'
# chiroptera-dots

The dotfiles of ChiropteraOS: Hyprland, Chiroptera Shell, fish, foot, fastfetch,
btop and starship, as used on the author's machine.

## Install

```sh
git clone https://github.com/george-leonard314/chiroptera-dots
cd chiroptera-dots
./install.sh --copy      # or --link to develop against this checkout
hyprctl reload && chiroptera msg config-reload
```

`--diff` shows what would change; `--force` overwrites. Anything replaced is
backed up once as `<path>.pre-dots`.

## What is here

| Path | Purpose |
|---|---|
| `config/hypr` | Hyprland: keybinds via Chiroptera IPC, window rules, autostart |
| `config/chiroptera` | shell config, palette templates for the terminal and the fastfetch logo |
| `config/fish` | shell config, the `faah` error sound and red border flash |
| `config/foot`, `config/btop`, `config/fastfetch`, `config/starship.toml` | terminal and tool configs, coloured by the shell's templates |
| `branding` | logo marks and the default wallpaper |
| `bin` | `chiroptera-super-tap` (tap Super for the launcher), `chiroptera-toggle` (special-workspace apps) |

## Machine-local settings

Put anything specific to one machine in `~/.config/hypr/hyprland/user.conf`,
which is sourced last. Monitor layout lives in `~/.config/hypr/monitors.conf`
and is deliberately not tracked.
EOF
cat > CREDITS.md <<'EOF'
# Credits

The Hyprland configuration and several tool configs in this repository began as
the Caelestia dotfiles by soramane and contributors, GPL-3.0: <!-- keep -->
https://github.com/caelestia-dots/caelestia <!-- keep -->

Chiroptera Shell is a rebrand of Noctalia by the Noctalia team, MIT:
https://github.com/noctalia-dev/noctalia
EOF
git add -A && git commit -m "Clean remaining config references, add install.sh, README and credits"
chiroptera/check-dots.sh
```

Expected: `check-dots: ok`.

---

### Task 4: Package chiroptera-dots and chiroptera-meta

**Files:**
- Create: `~/git/ChiropteraOS/pkgs/chiroptera-dots/PKGBUILD`
- Create: `~/git/ChiropteraOS/pkgs/chiroptera-meta/PKGBUILD`
- Modify: `~/git/ChiropteraOS/.gitignore` (bare-clone ignore for the new package)

**Interfaces:**
- Consumes: a `v0.1.0` tag on chiroptera-dots (created in this task).
- Produces: `chiroptera-dots-0.1.0-1-any.pkg.tar.zst` installing the tree to `/usr/share/chiroptera/dots`, the helper scripts to `/usr/bin`, the branding to `/usr/share/chiroptera/branding`, the wallpaper to `/usr/share/backgrounds/chiroptera`, and `/usr/bin/chiroptera-dots` as the installer. `chiroptera-meta-0.1.0-1-any.pkg.tar.zst` depends on the shell, the dots, and the desktop application set.

- [ ] **Step 1: Tag the dots repo and push**

```bash
cd ~/git/chiroptera-dots
git tag -a v0.1.0 -m "chiroptera-dots 0.1.0: first capture of the laptop configuration"
git push -u origin main --tags && git describe --tags
```

Expected: `v0.1.0`.

- [ ] **Step 2: Write the dots PKGBUILD**

```bash
mkdir -p ~/git/ChiropteraOS/pkgs/chiroptera-dots && cat > ~/git/ChiropteraOS/pkgs/chiroptera-dots/PKGBUILD <<'EOF'
# Maintainer: George (ChiropteraOS)

pkgname=chiroptera-dots
_srcname=chiroptera-dots
pkgver=0.1.0
_tag=v0.1.0
pkgrel=1
pkgdesc='ChiropteraOS dotfiles: Hyprland, Chiroptera Shell, fish, foot, fastfetch'
arch=('any')
url='https://github.com/george-leonard314/chiroptera-dots'
license=('MIT')
depends=('hyprland' 'chiroptera-shell' 'fish' 'foot' 'fastfetch' 'btop' 'starship')
optdepends=('thunar: file manager used by the file-explorer keybind'
            'obsidian: notes, bound to the obsidian special workspace'
            'superproductivity: todo, bound to the todo special workspace')
provides=('chiroptera-dots')
# Override with a local clone for development builds, e.g. file:///home/g/git/chiroptera-dots
_repo="${CHIROPTERA_DOTS_REPO:-$url.git}"
source=("${_srcname}::git+${_repo}#tag=${_tag}")
sha256sums=('SKIP')

package() {
  cd "${_srcname}"
  # Pristine tree the installer copies from.
  install -dm755 "$pkgdir/usr/share/chiroptera/dots"
  cp -a config/. "$pkgdir/usr/share/chiroptera/dots/"
  # New users get it through /etc/skel.
  install -dm755 "$pkgdir/etc/skel/.config"
  cp -a config/. "$pkgdir/etc/skel/.config/"
  install -dm755 "$pkgdir/usr/share/chiroptera/branding"
  install -m644 branding/*.svg "$pkgdir/usr/share/chiroptera/branding/"
  install -Dm644 branding/wallpapers/chiroptera-default.png \
    "$pkgdir/usr/share/backgrounds/chiroptera/chiroptera-default.png"
  install -Dm755 bin/chiroptera-super-tap "$pkgdir/usr/bin/chiroptera-super-tap"
  install -Dm755 bin/chiroptera-toggle    "$pkgdir/usr/bin/chiroptera-toggle"
  install -Dm755 install.sh               "$pkgdir/usr/bin/chiroptera-dots"
  install -Dm644 README.md  "$pkgdir/usr/share/doc/$pkgname/README.md"
  install -Dm644 CREDITS.md "$pkgdir/usr/share/doc/$pkgname/CREDITS.md"
}
EOF
```

- [ ] **Step 3: Write the meta PKGBUILD**

The dependency list is the caelestia-meta set with caelestia removed, Chiroptera added, and the applications the author's keybinds actually invoke.

```bash
mkdir -p ~/git/ChiropteraOS/pkgs/chiroptera-meta && cat > ~/git/ChiropteraOS/pkgs/chiroptera-meta/PKGBUILD <<'EOF'
# Maintainer: George (ChiropteraOS)

pkgname=chiroptera-meta
pkgver=0.1.0
pkgrel=1
pkgdesc='Everything a ChiropteraOS desktop needs'
arch=('any')
url='https://github.com/george-leonard314/ChiropteraOS'
license=('MIT')
depends=(
  # Shell and dotfiles
  'chiroptera-shell' 'chiroptera-dots'
  # Compositor and session
  'hyprland' 'xdg-desktop-portal-hyprland' 'xdg-desktop-portal-gtk' 'uwsm'
  # Terminal and shell tooling
  'foot' 'fish' 'starship' 'eza' 'zoxide' 'fzf' 'jq' 'ripgrep' 'bat'
  # System tools the config and keybinds use
  'btop' 'fastfetch' 'wl-clipboard' 'cliphist' 'hyprpicker' 'grim' 'slurp'
  'brightnessctl' 'ddcutil' 'trash-cli' 'inotify-tools' 'polkit-gnome' 'gnome-keyring'
  # Audio, network, bluetooth
  'pipewire' 'pipewire-pulse' 'pipewire-alsa' 'wireplumber' 'networkmanager' 'bluez' 'bluez-utils'
  # Look and feel
  'adw-gtk-theme' 'papirus-icon-theme' 'qt5ct-kde' 'qt6ct-kde'
  'ttf-jetbrains-mono-nerd' 'noto-fonts' 'noto-fonts-cjk' 'noto-fonts-emoji'
  'ttf-material-symbols-variable'
  # Sound effects used by the fish error hook
  'sound-theme-freedesktop' 'libpulse'
)
optdepends=('thunar: file manager'
            'obsidian: notes'
            'superproductivity: todo'
            'noctalia-greeter: greetd login screen themed by the shell'
            'nwg-displays: monitor layout editor')
provides=('chiroptera-meta')
EOF
grep -c "'" ~/git/ChiropteraOS/pkgs/chiroptera-meta/PKGBUILD
```

- [ ] **Step 4: Build both packages and inspect**

```bash
cd ~/git/ChiropteraOS/pkgs/chiroptera-dots && CHIROPTERA_DOTS_REPO=file:///home/g/git/chiroptera-dots makepkg -sf --noconfirm 2>&1 | tail -3
pacman -Qlp chiroptera-dots-0.1.0-1-any.pkg.tar.zst | grep -E 'usr/bin/chiroptera-(dots|toggle|super-tap)$|share/chiroptera/dots/hypr/hyprland.conf|share/chiroptera/dots/fish/sounds/faah.oga|backgrounds/chiroptera|etc/skel/.config/hypr/' | head
pacman -Qlp chiroptera-dots-0.1.0-1-any.pkg.tar.zst | grep -ci caelestia
cd ~/git/ChiropteraOS/pkgs/chiroptera-meta && makepkg -sf --noconfirm --nodeps 2>&1 | tail -3
pacman -Qip chiroptera-meta-0.1.0-1-any.pkg.tar.zst | grep -E '^(Name|Version|Depends On)' | cut -c1-200
```

Expected: both builds finish; the dots package lists all five paths, including `faah.oga`; the caelestia count is `0`; the meta package's dependency list includes `chiroptera-shell` and `chiroptera-dots`.

- [ ] **Step 5: Commit the packaging**

```bash
cd ~/git/ChiropteraOS
cat >> .gitignore <<'EOF'
pkgs/chiroptera-dots/chiroptera-dots/
EOF
git add .gitignore pkgs/chiroptera-dots/PKGBUILD pkgs/chiroptera-meta/PKGBUILD
git commit -m "Add chiroptera-dots and chiroptera-meta packages"
git log --oneline -1
```

---

### Task 5: Move the laptop onto the dots and verify

**Files:**
- Modify (laptop, outside git): `~/.config/{hypr,fish,foot,btop,fastfetch,starship.toml,uwsm}` symlinks, `~/.config/caelestia/hypr-user.conf` (spike block retired), `~/.local/bin/chiroptera-*`

**Interfaces:**
- Consumes: the repo from Task 3 and, optionally, the installed package from Task 4.
- Produces: a laptop whose config comes from `~/git/chiroptera-dots` with no path pointing into `~/.local/share/caelestia`, and a working session.

**This task changes the live desktop.** Every replaced path is backed up as `<path>.pre-dots`, and the rollback command is in Step 5.

- [ ] **Step 1: Fold the temporary spike block into the repo**

The window rules, screenshot binds, group binds and caelestia-unbind lines currently live in `~/.config/caelestia/hypr-user.conf`. Move them into the tracked config, then retire that file.

```bash
cd ~/git/chiroptera-dots
python3 - <<'PY'
from pathlib import Path
src = Path.home() / ".config/caelestia/hypr-user.conf"
block = src.read_text()
start = block.index("# >>> chiroptera shell binds")
body = block[start:].splitlines(True)
keep = [l for l in body if not l.startswith("# >>>") and not l.startswith("# <<<")
        and "unbind = Super+Alt, L" not in l and "unbind = Ctrl+Super+Alt, R" not in l
        and "unbind = Super+Alt, Backslash" not in l]
out = Path("config/hypr/hyprland/chiroptera.conf")
out.write_text("# Chiroptera-specific binds and rules, sourced from hyprland.conf.\n" + "".join(keep))
print(f"wrote {out} with {len(keep)} lines")
PY
python3 - <<'PY'
from pathlib import Path
p = Path("config/hypr/hyprland.conf"); s = p.read_text()
if "chiroptera.conf" not in s:
    s = s.replace("source = $hl/user.conf", "source = $hl/chiroptera.conf\n\n# User overrides, sourced last so they win.\nsource = $hl/user.conf")
    p.write_text(s)
print("hyprland.conf sources chiroptera.conf then user.conf")
PY
grep -n 'source = \$hl' config/hypr/hyprland.conf | tail -3
chiroptera/check-dots.sh
```

Expected: the new file is written, `hyprland.conf` sources `chiroptera.conf` before `user.conf`, and the check passes.

- [ ] **Step 2: Carry over the machine-local pieces**

`monitors.conf` and the personal keybind overrides stay on the machine, not in the repo.

```bash
cp -n ~/.config/hypr/monitors.conf ~/.config/hypr/monitors.conf.keep 2>/dev/null || true
cat > /tmp/claude-1000/user-conf-seed <<'EOF'
# Machine-local overrides for laptop.
bind = SUPER, P, exec, nwg-displays
bind = SUPER SHIFT, P, pin
bind = SUPER SHIFT, slash, exec, ~/.local/bin/hypr-cheatsheet
EOF
wc -l /tmp/claude-1000/user-conf-seed
```

- [ ] **Step 3: Link the repo into the live config**

```bash
cd ~/git/chiroptera-dots && ./install.sh --link
cp ~/.config/hypr/monitors.conf.keep ~/git/chiroptera-dots/config/hypr/monitors.conf 2>/dev/null || cp ~/.local/share/caelestia/hypr/monitors.conf ~/git/chiroptera-dots/config/hypr/monitors.conf
cp /tmp/claude-1000/user-conf-seed ~/git/chiroptera-dots/config/hypr/hyprland/user.conf
for f in hypr fish foot btop fastfetch starship.toml uwsm; do printf '%s -> %s\n' "$f" "$(readlink ~/.config/$f || echo '(not a link)')"; done
git -C ~/git/chiroptera-dots status --short | head -5
```

Expected: every entry points at `/home/g/git/chiroptera-dots/config/...`; `git status` shows `monitors.conf` and `user.conf` as untracked or ignored, never staged.

- [ ] **Step 4: Reload and verify the session**

```bash
hyprctl reload; sleep 2
echo "config errors: $(hyprctl configerrors | grep -c .)"
pkill -x chiroptera; sleep 1; chiroptera --daemon; sleep 4
hyprctl layers | grep -o 'namespace: chiroptera-[a-z-]*' | sort -u | tr '\n' ' '; echo
echo "IPC binds: $(hyprctl binds | grep -c 'chiroptera msg')"
echo "caelestia binds left: $(hyprctl binds | grep -c 'caelestia')"
grep -c 'chiroptera' ~/.config/fish/config.fish
fish -c 'false' 2>/dev/null; sleep 1; echo "faah hook present: $(grep -c __faah_on_error ~/.config/fish/conf.d/faah.fish)"
```

Expected: `0` config errors; the `chiroptera-bar-default` namespace present; at least 12 IPC binds; `0` caelestia binds; the faah hook found.

- [ ] **Step 5: Ask the user to confirm the session by hand**

These cannot be automated. Ask the user to confirm, and record their answers in the report:

1. Tap Super: the launcher opens.
2. Super+O: Obsidian appears in its special workspace.
3. Print: a region screenshot starts.
4. Type a bad command in fish: the faah sound plays and the border flashes red.
5. Media keys and brightness keys still work.

Rollback if anything is broken:

```bash
for p in ~/.config/{hypr,fish,foot,btop,fastfetch,starship.toml,uwsm}; do
  [ -e "$p.pre-dots" ] && { rm -rf "$p"; mv "$p.pre-dots" "$p"; }
done
hyprctl reload; pkill -x chiroptera; chiroptera --daemon
```

- [ ] **Step 6: Commit the machine-local additions and push**

```bash
cd ~/git/chiroptera-dots
git status --short
git add -A && git commit -m "Fold the temporary bind block into the tracked Hyprland config" || echo "nothing to commit"
git push origin main
```

Expected: `monitors.conf` and `user.conf` do not appear in the commit, because `.gitignore` covers them.

---

### Task 6: Prove caelestia is unreferenced and document the removal

**Files:**
- Create: `~/git/ChiropteraOS/docs/caelestia-removal.md`

**Interfaces:**
- Consumes: the laptop state from Task 5.
- Produces: evidence that nothing on the laptop reads from the caelestia packages or directories, plus the exact removal commands for the user to run.

- [ ] **Step 1: Search the live session for caelestia references**

```bash
echo "=== config symlinks ==="; for f in hypr fish foot btop fastfetch starship.toml uwsm; do readlink ~/.config/$f; done | grep -c caelestia
echo "=== running processes ==="; pgrep -af caelestia | grep -v pgrep | wc -l
echo "=== hyprland binds ==="; hyprctl binds | grep -c caelestia
echo "=== files under ~/.config referencing it ==="; grep -rl caelestia ~/.config --exclude-dir=caelestia 2>/dev/null | head
echo "=== what still lives in the caelestia dirs ==="; du -sh ~/.config/caelestia ~/.local/state/caelestia ~/.cache/caelestia ~/.local/share/caelestia 2>/dev/null
```

Expected: the first three counts are `0`; the file list is empty or shows only backups ending in `.pre-dots`.

- [ ] **Step 2: Write the removal document**

```bash
cat > ~/git/ChiropteraOS/docs/caelestia-removal.md <<'EOF'
# Removing Caelestia

ChiropteraOS started from the Caelestia dotfiles and shell. After step 2 nothing
on the machine reads from them, so they can be removed. Run these yourself;
they need root.

## 1. Keep the shared dependencies

`caelestia-meta` pulled in packages the desktop still needs. Claim them first,
otherwise removing the metapackage takes them with it.

```sh
sudo pacman -D --asexplicit xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  hyprpicker wl-clipboard cliphist inotify-tools app2unit wireplumber trash-cli \
  foot eza fastfetch starship btop jq adw-gtk-theme papirus-icon-theme \
  qt5ct-kde qt6ct-kde ttf-jetbrains-mono-nerd
```

Installing `chiroptera-meta` makes this step unnecessary, because it owns the
same dependencies.

## 2. Remove the packages

```sh
sudo pacman -Rns caelestia-meta caelestia-shell caelestia-cli
```

This also removes Quickshell and the Qt shapes plugin, roughly 400 MB.

## 3. Remove the leftover directories

Check first that nothing you want is inside:

```sh
ls ~/.config/caelestia ~/.local/state/caelestia ~/.local/share/caelestia
rm -rf ~/.cache/caelestia                    # image cache, safe
rm -rf ~/.config/caelestia ~/.local/state/caelestia ~/.local/share/caelestia
```

`~/.local/share/caelestia` was the old dotfiles checkout. Its contents now live
in `chiroptera-dots`, so removing it is safe once `./install.sh --link` has run
and the session works.

## 4. Backups

The migration left `.pre-dots` copies beside every replaced config path. Remove
them when you are confident:

```sh
find ~/.config -maxdepth 1 -name '*.pre-dots' -exec rm -rf {} +
```
EOF
cd ~/git/ChiropteraOS && git add docs/caelestia-removal.md && git commit -m "Document the safe Caelestia removal sequence"
git log --oneline -3
```

Expected: three commits, newest first: the removal doc, the packages, the step 2 plan.

- [ ] **Step 3: Report the state for the user**

```bash
pacman -Q chiroptera-shell chiroptera-dots chiroptera-meta caelestia-shell noctalia-git 2>&1
readlink ~/.config/hypr
git -C ~/git/chiroptera-dots log --oneline -3
git -C ~/git/chiroptera-dots describe --tags
```

Report this output verbatim, and hand the user the two `pacman` commands from the removal document.
