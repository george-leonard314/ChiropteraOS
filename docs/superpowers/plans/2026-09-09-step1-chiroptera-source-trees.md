# Step 1: Chiroptera Source Trees Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `chiroptera-shell` and `chiroptera-dots` as renamed copies of the Caelestia shell, dots, and CLI with upstream remotes, package them, and get `chiroptera shell -d` running on the author's laptop as a pure rename.

**Architecture:** Each new repo is a full-history clone of its upstream with a deterministic, idempotent rename transform (`chiroptera/rename.sh`) committed on top. The transform renames every `caelestia` token including the QML plugin module URI, so Chiroptera installs side by side with Caelestia. Upstream sync later means: apply the same transform to upstream's tree, then merge. `ChiropteraOS` gets PKGBUILDs that build both packages from git tags, and the laptop switches by running a migration script that copies user config and state to the new names and rewrites the live Hyprland config.

**Tech Stack:** git (remotes, subtree), bash, perl (in-place regex), CMake + Ninja + Qt 6 (shell plugin), Quickshell (`qs`), Python 3.14 with hatchling and hatch-vcs (CLI), makepkg/pacman, GitHub CLI (`gh`).

**Spec:** `docs/superpowers/specs/2026-09-09-chiroptera-os-design.md` sections 3, 4.1, 5, 6.1, 11 step 1.

## Global Constraints

- Three repos: `chiroptera-shell`, `chiroptera-dots` (with the CLI at `cli/`), `ChiropteraOS`. GitHub user `george-leonard314`. All private, matching `ChiropteraOS`.
- Copies keep full upstream history. Upstream remotes are `upstream` (shell), `upstream-dots` and `upstream-cli` (dots). Upstream remotes fetch with `--no-tags` and have push disabled.
- Shell installs to `/etc/xdg/quickshell/chiroptera/`, QML plugin to `/usr/lib/qt6/qml/Chiroptera/`, version helper to `/usr/lib/chiroptera/version`. CLI executable is `chiroptera`. User config `~/.config/chiroptera/`, state `~/.local/state/chiroptera/`.
- Global shortcut appid becomes `chiroptera`; layer namespaces become `chiroptera-*`.
- Personal files never enter any repo: no `monitors.conf`, keys, tokens, shell history.
- GPL-3.0 license files stay. README credits upstream by name and link.
- Version tags `v0.1.0` on both source repos. PKGBUILDs pin `#tag=v${pkgver}`.
- The laptop's existing Hyprland config (legacy `.conf` layout, symlinked from `~/.local/share/caelestia`) stays in place. Only names inside it change. Moving the laptop to the Lua config in `chiroptera-dots` is a later step.
- Caelestia packages stay installed during this step. Removal is a later step.
- Upstream commits at plan time: shell `ce84c7b`, cli `c6df16b`, dots `1ee7a98`. Record the actual hashes at execution time in `.upstream-sync`.
- Names preserved verbatim (never renamed): `caelestia-dots` (GitHub org in URLs), `caelestiafox` / `CaelestiaFox` (published Firefox extension), `caelestia-firefox`, `caelestia-vscode` (published integrations shipped as built artifacts), and any line carrying `<!-- keep -->`.
- Upstream hosting facts: git auth to GitHub is HTTPS through `gh auth git-credential`. SSH is not set up. Use HTTPS URLs everywhere.

---

## File Structure

**chiroptera-shell** (clone of `caelestia-dots/shell`):
- `chiroptera/rename.sh` — idempotent transform: deletes upstream-only infra, renames paths, rewrites text, prepends README banner.
- `chiroptera/check-rename.sh` — assertion script: fails if any non-allowlisted `caelestia` survives.
- `.upstream-sync` — one line: `upstream <sha>` of the upstream commit the tree is based on.
- Everything else: upstream files, renamed. `plugin/src/Caelestia/` becomes `plugin/src/Chiroptera/`.

**chiroptera-dots** (clone of `caelestia-dots/caelestia`, plus `cli/` subtree from `caelestia-dots/cli`):
- `chiroptera/rename.sh`, `chiroptera/check-rename.sh` — same shape as the shell's, with dots-specific exclusions.
- `chiroptera/migrate-from-caelestia.sh` — one-shot laptop migration: copies config and state, rewrites the legacy live config.
- `chiroptera/test-migrate.sh` — fixture-based test for the migration script.
- `cli/tests/test_rename.py` — unittest checks that the CLI is fully renamed and runs.
- `cli/pyproject.toml` — gains `raw-options = { root = ".." }` so hatch-vcs finds the repo root from the subtree.
- `.upstream-sync` — two lines: `upstream-dots <sha>` and `upstream-cli <sha>`.

**ChiropteraOS**:
- `pkgs/chiroptera-cli/PKGBUILD`
- `pkgs/chiroptera-shell/PKGBUILD`
- `docs/upstream-sync.md` — the sync ritual.
- `docs/superpowers/specs/2026-09-09-chiroptera-os-design.md` — section 3.4 and 4.1 amended to describe the transform approach.

---

### Task 1: Bootstrap the chiroptera-shell repository

**Files:**
- Create: GitHub repo `george-leonard314/chiroptera-shell` (private)
- Create: `~/git/chiroptera-shell/` (clone with history)

**Interfaces:**
- Produces: local repo at `~/git/chiroptera-shell` with remotes `origin` (ours, HTTPS) and `upstream` (caelestia, fetch only, no tags), branch `main` pushed.

- [ ] **Step 1: Create the private GitHub repo**

```bash
gh repo create george-leonard314/chiroptera-shell --private \
  --description "Chiroptera Shell: the ChiropteraOS desktop shell, derived from caelestia-shell"
```

Expected: prints `https://github.com/george-leonard314/chiroptera-shell`.

- [ ] **Step 2: Clone upstream with full history and wire the remotes**

```bash
cd ~/git
git clone https://github.com/caelestia-dots/shell.git chiroptera-shell
cd chiroptera-shell
git remote rename origin upstream
git remote set-url --push upstream DISABLED
git config remote.upstream.tagOpt --no-tags
git tag -l | xargs -r git tag -d
git remote add origin https://github.com/george-leonard314/chiroptera-shell.git
git remote -v
git tag -l | wc -l
```

Expected: `git remote -v` shows four lines: `origin` fetch and push to `george-leonard314/chiroptera-shell.git`, `upstream` fetch to `caelestia-dots/shell.git` and push `DISABLED`. Tag count is `0`.

- [ ] **Step 3: Push the untouched copy**

```bash
cd ~/git/chiroptera-shell
git push -u origin main
gh repo view george-leonard314/chiroptera-shell --json isPrivate,defaultBranchRef --jq '{isPrivate, branch: .defaultBranchRef.name}'
```

Expected: `{"isPrivate":true,"branch":"main"}`.

---

### Task 2: Shell rename transform

**Files:**
- Create: `~/git/chiroptera-shell/chiroptera/check-rename.sh`
- Create: `~/git/chiroptera-shell/chiroptera/rename.sh`
- Create: `~/git/chiroptera-shell/.upstream-sync`
- Modify: every tracked file containing `caelestia`; `plugin/src/Caelestia/` renamed to `plugin/src/Chiroptera/`; `nix/`, `flake.nix`, `flake.lock`, `.envrc`, `.github/` deleted.

**Interfaces:**
- Consumes: Task 1 repo.
- Produces: `chiroptera/rename.sh` (no args, run from anywhere inside the repo, exit 0), `chiroptera/check-rename.sh` (exit 0 when clean, exit 1 with offending lines on stderr otherwise). CMake project name `chiroptera-shell`, QML module URIs `Chiroptera`, `Chiroptera.Config`, `Chiroptera.Settings`, `Chiroptera.Components`, `Chiroptera.Models`, `Chiroptera.Services`, `Chiroptera.Blobs`, `Chiroptera.Images`, `Chiroptera.I18n`. Install dirs `INSTALL_LIBDIR=lib/chiroptera`, `INSTALL_QSCONFDIR=etc/xdg/quickshell/chiroptera`. Global shortcut appid `chiroptera`. Layer namespace prefix `chiroptera-`. Paths singleton uses `~/.config/chiroptera`, `~/.local/state/chiroptera`, `~/.cache/chiroptera`, `~/.local/share/chiroptera`, env overrides `CHIROPTERA_WALLPAPERS_DIR`, `CHIROPTERA_RECORDINGS_DIR`, `CHIROPTERA_LIB_DIR`.

- [ ] **Step 1: Write the check script (this is the test)**

```bash
mkdir -p ~/git/chiroptera-shell/chiroptera
cat > ~/git/chiroptera-shell/chiroptera/check-rename.sh <<'EOF'
#!/usr/bin/env bash
# Fails if any reference to the upstream name survives outside the allowlist.
# Allowlist: the upstream GitHub org in URLs, the published CaelestiaFox extension,
# lines marked <!-- keep -->, and this tooling directory.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

allow='caelestia-dots|caelestiafox|CaelestiaFox|<!-- keep -->|^\./chiroptera/'
status=0

leftovers=$(find . -type f -not -path './.git/*' -not -path './build/*' -print0 \
  | xargs -0 grep -HnI -i 'caelestia' -- 2>/dev/null | grep -vE "$allow" || true)
if [ -n "$leftovers" ]; then
  echo "check-rename: leftover references:" >&2
  echo "$leftovers" >&2
  status=1
fi

paths=$(find . -not -path './.git/*' -not -path './build/*' -iname '*caelestia*' | grep -vE "$allow" || true)
if [ -n "$paths" ]; then
  echo "check-rename: leftover paths:" >&2
  echo "$paths" >&2
  status=1
fi

for f in nix flake.nix flake.lock .envrc .github; do
  if [ -e "$f" ]; then
    echo "check-rename: $f must not exist" >&2
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-rename: ok"
fi
exit "$status"
EOF
chmod +x ~/git/chiroptera-shell/chiroptera/check-rename.sh
```

- [ ] **Step 2: Run the check to verify it fails on the untouched tree**

```bash
cd ~/git/chiroptera-shell && chiroptera/check-rename.sh; echo "exit=$?"
```

Expected: many `leftover references` lines, a `leftover paths` block containing `./plugin/src/Caelestia`, four `must not exist` lines, and `exit=1`.

- [ ] **Step 3: Write the rename transform**

```bash
cat > ~/git/chiroptera-shell/chiroptera/rename.sh <<'EOF'
#!/usr/bin/env bash
# Idempotent transform: turn an upstream caelestia-shell tree into chiroptera-shell.
# Run after every upstream merge (see ChiropteraOS/docs/upstream-sync.md). Safe to re-run.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

GH_USER=george-leonard314
# Paths that are never renamed or rewritten (regex on repo-relative paths).
exclude='^(chiroptera|build)(/|$)'

# 1. Upstream-only infrastructure we do not carry.
rm -rf nix flake.nix flake.lock .envrc .github

# 2. Rename files and directories whose names contain the old name, deepest first.
#    "|| true" guards: on a re-run nothing matches and grep would exit 1 under pipefail.
find . -depth -not -path './.git/*' -not -path './build/*' -iname '*caelestia*' -printf '%P\n' \
  | { grep -vE "$exclude" || true; } \
  | while IFS= read -r path; do
      dir=$(dirname "$path")
      base=$(basename "$path" | sed 's/caelestia/chiroptera/g; s/Caelestia/Chiroptera/g; s/CAELESTIA/CHIROPTERA/g')
      mv "$path" "$dir/$base"
    done

# 3. Rewrite text contents. URLs first so the org name survives only where it must.
mapfile -d '' files < <(
  find . -type f -not -path './.git/*' -not -path './build/*' -printf '%P\0' \
    | { grep -zvE "$exclude" || true; } \
    | { xargs -0 -r grep -lIZ -i 'caelestia' -- 2>/dev/null || true; }
)
if [ "${#files[@]}" -gt 0 ]; then
  perl -pi -e '
      next if /<!-- keep -->/;
      s{github\.com/caelestia-dots/shell}{github.com/'"$GH_USER"'/chiroptera-shell}g;
      s{github\.com/caelestia-dots/cli}{github.com/'"$GH_USER"'/chiroptera-dots}g;
      s{github\.com/caelestia-dots/caelestia}{github.com/'"$GH_USER"'/chiroptera-dots}g;
      s/caelestia(?!-dots|fox|-firefox|-vscode)/chiroptera/g;
      s/Caelestia(?!Fox)/Chiroptera/g;
      s/CAELESTIA/CHIROPTERA/g;
    ' "${files[@]}"
fi

# 4. README banner crediting upstream, inserted once.
if ! grep -q '<!-- chiroptera-banner -->' README.md; then
  {
    cat <<'BANNER'
<!-- chiroptera-banner -->
# Chiroptera Shell

The desktop shell of ChiropteraOS. Derived from caelestia-shell by soramane and contributors, GPL-3.0: <!-- keep -->
https://github.com/caelestia-dots/shell <!-- keep -->

Upstream is tracked as the `upstream` git remote. `chiroptera/rename.sh` is the transform applied
after each upstream merge; `chiroptera/check-rename.sh` verifies it. The rest of this README is the
upstream documentation with names rewritten.

---

BANNER
    cat README.md
  } > README.md.new
  mv README.md.new README.md
fi

echo "rename: done"
EOF
chmod +x ~/git/chiroptera-shell/chiroptera/rename.sh
```

- [ ] **Step 4: Run the transform, then the check**

```bash
cd ~/git/chiroptera-shell && chiroptera/rename.sh && chiroptera/check-rename.sh; echo "exit=$?"
```

Expected: `rename: done`, `check-rename: ok`, `exit=0`.

- [ ] **Step 5: Verify key files by content**

```bash
cd ~/git/chiroptera-shell
grep -n 'project(\|INSTALL_LIBDIR\|INSTALL_QSCONFDIR' CMakeLists.txt
grep -n 'URI' plugin/src/Chiroptera/CMakeLists.txt plugin/src/Chiroptera/Config/CMakeLists.txt
grep -n 'appid' components/misc/CustomShortcut.qml
grep -n 'chiroptera' utils/Paths.qml
grep -n 'CHIROPTERA_VERSION' plugin/src/Chiroptera/CMakeLists.txt
head -3 README.md
```

Expected: `project(chiroptera-shell ...)`, `lib/chiroptera`, `etc/xdg/quickshell/chiroptera`; `URI Chiroptera` and `URI Chiroptera.Config`; `appid: "chiroptera"`; Paths lines ending in `/chiroptera` and env names `CHIROPTERA_*`; the compile definition `CHIROPTERA_VERSION`; README starts with the banner.

- [ ] **Step 6: Verify idempotence**

```bash
cd ~/git/chiroptera-shell && git add -A && chiroptera/rename.sh && echo "second run changed: $(git diff --stat | tail -1)"
```

Expected: `rename: done` then `second run changed:` followed by nothing. `git diff` compares the working tree to the index that holds the first run's result, so any output means the transform is not idempotent; fix before continuing.

- [ ] **Step 7: Record the upstream base and commit**

```bash
cd ~/git/chiroptera-shell
echo "upstream $(git rev-parse upstream/main)" > .upstream-sync
git add -A
git commit -m "Rename Caelestia to Chiroptera

Full-tree transform via chiroptera/rename.sh: QML module URIs, CMake targets,
install dirs, config and state paths, shortcut appid, layer namespaces.
Drops Nix and upstream CI. Upstream base recorded in .upstream-sync."
git show --stat HEAD | tail -3
```

Expected: the commit shows hundreds of files changed with `plugin/src/{Caelestia => Chiroptera}/...` renames.

---

### Task 3: Build the shell, smoke test it, tag and push

**Files:**
- Uses: `~/git/chiroptera-shell/` (build dir `build/`, gitignored)

**Interfaces:**
- Consumes: Task 2 tree.
- Produces: tag `v0.1.0` on `origin/main` of chiroptera-shell; proven that `build/lib/version -s` prints `chiroptera-shell 0.1.0` and Quickshell loads the config with the `Chiroptera` modules.

- [ ] **Step 1: Configure and build**

```bash
cd ~/git/chiroptera-shell
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ \
  -DVERSION=0.1.0 -DGIT_REVISION="$(git rev-parse HEAD)" -DDISTRIBUTOR=dev 2>&1 | grep -E 'Created QML module|QML install dir|Error' 
cmake --build build 2>&1 | tail -3
```

Expected: nine `Created QML module: Chiroptera...` lines (`Chiroptera`, `Chiroptera.Settings`, `Chiroptera.Components`, `Chiroptera.Config`, `Chiroptera.Models`, `Chiroptera.Services`, `Chiroptera.Blobs`, `Chiroptera.Images`, `Chiroptera.I18n`), no `Error`, and the build ends with a `ninja` completion line without `FAILED`.

- [ ] **Step 2: Verify the version helper and module layout**

```bash
cd ~/git/chiroptera-shell
./build/lib/version -s
ls build/qml/Chiroptera/
ls build/qml/Chiroptera/Config/
```

Expected: `chiroptera-shell 0.1.0, revision <sha>, distributed by: dev`; directory listing contains `Blobs Components Config I18n Images Models Services Settings lib qmldir`; Config contains `qmldir` and a `libchiroptera-configplugin.so`.

- [ ] **Step 3: Load the config headless with Quickshell**

```bash
cd ~/git/chiroptera-shell
QT_QPA_PLATFORM=offscreen QML2_IMPORT_PATH="$PWD/build/qml" timeout 5 qs -p . > build/qs-smoke.log 2>&1; echo "exit=$?"
grep -E 'module "[A-Za-z.]*" is not installed|is not a type|Type .* unavailable|Cannot assign|Unresolved' build/qs-smoke.log; echo "qml-errors=$?"
```

Expected: `exit=124` (still running when the timeout hit) or `exit=0`, and `qml-errors=1` (grep found nothing). If `qml-errors=0`, the lines printed name a module or type that the rename broke; fix the source and rebuild before continuing.

- [ ] **Step 4: Tag and push**

```bash
cd ~/git/chiroptera-shell
git tag -a v0.1.0 -m "Chiroptera Shell 0.1.0: pure rename of caelestia-shell $(cut -d' ' -f2 .upstream-sync | cut -c1-7)"
git push origin main --tags
git describe --tags
```

Expected: `v0.1.0`.

---

### Task 4: Bootstrap the chiroptera-dots repository with the CLI subtree

**Files:**
- Create: GitHub repo `george-leonard314/chiroptera-dots` (private)
- Create: `~/git/chiroptera-dots/` with `cli/` subtree

**Interfaces:**
- Produces: local repo with remotes `origin`, `upstream-dots` (caelestia-dots/caelestia), `upstream-cli` (caelestia-dots/cli), both upstreams fetch only, no tags. `cli/` holds the full CLI tree with history joined via `git subtree`.

- [ ] **Step 1: Create the private GitHub repo**

```bash
gh repo create george-leonard314/chiroptera-dots --private \
  --description "Chiroptera dotfiles and CLI for ChiropteraOS, derived from the Caelestia dots and CLI"
```

Expected: prints `https://github.com/george-leonard314/chiroptera-dots`.

- [ ] **Step 2: Clone the dots upstream and wire remotes**

```bash
cd ~/git
git clone https://github.com/caelestia-dots/caelestia.git chiroptera-dots
cd chiroptera-dots
git remote rename origin upstream-dots
git remote set-url --push upstream-dots DISABLED
git config remote.upstream-dots.tagOpt --no-tags
git remote add --no-tags upstream-cli https://github.com/caelestia-dots/cli.git
git remote set-url --push upstream-cli DISABLED
git fetch upstream-cli main
git tag -l | xargs -r git tag -d
git remote add origin https://github.com/george-leonard314/chiroptera-dots.git
git remote -v
```

Expected: six lines: `origin` fetch/push to ours, `upstream-dots` and `upstream-cli` with fetch URLs to caelestia-dots and push `DISABLED`.

- [ ] **Step 3: Add the CLI as a subtree at cli/**

```bash
cd ~/git/chiroptera-dots
git subtree add --prefix=cli upstream-cli/main -m "Add caelestia-cli as cli/ subtree"
ls cli
git log --oneline -1
```

Expected: `ls cli` shows `LICENSE README.md bin completions default.nix flake.lock flake.nix pyproject.toml src` (dotfiles hidden). Log shows the subtree merge commit.

- [ ] **Step 4: Push the untouched copy**

```bash
cd ~/git/chiroptera-dots && git push -u origin main
gh repo view george-leonard314/chiroptera-dots --json isPrivate --jq .isPrivate
```

Expected: `true`.

---

### Task 5: CLI tests and the dots rename transform

**Files:**
- Create: `~/git/chiroptera-dots/cli/tests/test_rename.py`
- Create: `~/git/chiroptera-dots/chiroptera/check-rename.sh`
- Create: `~/git/chiroptera-dots/chiroptera/rename.sh`
- Create: `~/git/chiroptera-dots/.upstream-sync`
- Modify: `~/git/chiroptera-dots/cli/pyproject.toml` (hatch-vcs root)
- Modify: every tracked file containing `caelestia` outside the exclusions; `cli/src/caelestia/` becomes `cli/src/chiroptera/`, `cli/bin/caelestia` becomes `cli/bin/chiroptera`, `cli/completions/caelestia.fish` becomes `chiroptera.fish`, `cli/src/chiroptera/data/schemes/caelestia/` becomes `.../chiroptera/`, `nvim/colors/caelestia.lua` and `nvim/lua/plugins/caelestia.lua` become `chiroptera.lua`, `spicetify/Themes/caelestia/` becomes `chiroptera/`.

**Interfaces:**
- Consumes: Task 4 repo.
- Produces: Python package `chiroptera` at `cli/src/chiroptera` with console script `chiroptera = "chiroptera:main"`; `chiroptera.utils.paths` exposes `c_config_dir`, `c_state_dir`, `c_cache_dir`, `c_data_dir` all named `chiroptera`; `chiroptera.subcommands.shell` runs `qs -c chiroptera`; `DotsSource().url` defaults to `https://github.com/george-leonard314/chiroptera-dots.git`; hook env var `CHIROPTERA_DOTS`; completions file `cli/completions/chiroptera.fish`. Dots: `manifest.toml` package list `["chiroptera-shell", "chiroptera-cli"]`, hooks call `chiroptera shell -d`, Hyprland Lua config references `chiroptera:` shortcuts and `~/.config/chiroptera/`.

- [ ] **Step 1: Write the failing CLI tests**

```bash
mkdir -p ~/git/chiroptera-dots/cli/tests
cat > ~/git/chiroptera-dots/cli/tests/test_rename.py <<'EOF'
"""Checks that the CLI is fully renamed from caelestia to chiroptera and still runs."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

# Isolate from the real user config before any chiroptera module is imported.
_tmp = tempfile.mkdtemp(prefix="chiroptera-test-")
for var in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"):
    os.environ[var] = os.path.join(_tmp, var.lower())


class RenameTests(unittest.TestCase):
    def test_paths_use_chiroptera_dirs(self):
        from chiroptera.utils import paths

        for attr in ("c_config_dir", "c_data_dir", "c_state_dir", "c_cache_dir"):
            self.assertEqual(getattr(paths, attr).name, "chiroptera", attr)

    def test_shell_command_targets_chiroptera_config(self):
        src = (SRC / "chiroptera/subcommands/shell.py").read_text()
        self.assertIn('["qs", "-c", "chiroptera", "-n"]', src)
        self.assertNotIn("caelestia", src)

    def test_dots_source_defaults_to_chiroptera_dots(self):
        from chiroptera.utils.dots.source import DotsSource

        self.assertEqual(DotsSource().url, "https://github.com/george-leonard314/chiroptera-dots.git")

    def test_hook_env_var_is_renamed(self):
        src = (SRC / "chiroptera/utils/dots/misc.py").read_text()
        self.assertIn('"CHIROPTERA_DOTS"', src)

    def test_scheme_data_dir_is_renamed(self):
        self.assertTrue((SRC / "chiroptera/data/schemes/chiroptera/default/dark.txt").is_file())
        self.assertFalse((SRC / "chiroptera/data/schemes/caelestia").exists())

    def test_cli_help_runs(self):
        result = subprocess.run(
            [sys.executable, "-m", "chiroptera", "--help"], cwd=SRC, capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("usage: chiroptera", result.stdout)


if __name__ == "__main__":
    unittest.main()
EOF
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/git/chiroptera-dots/cli && python -m unittest discover -s tests -v 2>&1 | tail -5
```

Expected: `FAILED (errors=...)` with `ModuleNotFoundError: No module named 'chiroptera'` and `FileNotFoundError` for `chiroptera/subcommands/shell.py`.

- [ ] **Step 3: Write the check script**

```bash
mkdir -p ~/git/chiroptera-dots/chiroptera
cat > ~/git/chiroptera-dots/chiroptera/check-rename.sh <<'EOF'
#!/usr/bin/env bash
# Fails if any reference to the upstream name survives outside the allowlist.
# Allowlist: the upstream GitHub org in URLs, the published CaelestiaFox / firefox / vscode
# integrations (shipped as built artifacts we do not rebuild), lines marked <!-- keep -->,
# the tooling directory, and the CLI tests that name the old string on purpose.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

allow='caelestia-dots|caelestiafox|CaelestiaFox|caelestia-firefox|caelestia-vscode|<!-- keep -->|^\./(chiroptera|firefox|vscode|packages/caelestia-firefox-theme|cli/tests)/'
status=0

leftovers=$(find . -type f -not -path './.git/*' -print0 \
  | xargs -0 grep -HnI -i 'caelestia' -- 2>/dev/null | grep -vE "$allow" || true)
if [ -n "$leftovers" ]; then
  echo "check-rename: leftover references:" >&2
  echo "$leftovers" >&2
  status=1
fi

paths=$(find . -not -path './.git/*' -iname '*caelestia*' | grep -vE "$allow" || true)
if [ -n "$paths" ]; then
  echo "check-rename: leftover paths:" >&2
  echo "$paths" >&2
  status=1
fi

for f in .github cli/.github cli/flake.nix cli/flake.lock cli/default.nix cli/.envrc; do
  if [ -e "$f" ]; then
    echo "check-rename: $f must not exist" >&2
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-rename: ok"
fi
exit "$status"
EOF
chmod +x ~/git/chiroptera-dots/chiroptera/check-rename.sh
cd ~/git/chiroptera-dots && chiroptera/check-rename.sh; echo "exit=$?"
```

Expected: leftover references and paths listed (including `./cli/src/caelestia`, `./nvim/colors/caelestia.lua`), six `must not exist` lines, `exit=1`.

- [ ] **Step 4: Write the rename transform**

```bash
cat > ~/git/chiroptera-dots/chiroptera/rename.sh <<'EOF'
#!/usr/bin/env bash
# Idempotent transform: turn the upstream caelestia dots + cli trees into chiroptera-dots.
# Run after every upstream merge (see ChiropteraOS/docs/upstream-sync.md). Safe to re-run.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

GH_USER=george-leonard314
# Never renamed or rewritten: our tooling, the CLI tests, and the published integrations
# (Firefox extension native host, VS Code extension) that ship as built artifacts.
exclude='^(chiroptera|cli/tests|firefox|vscode|packages/caelestia-firefox-theme)(/|$)'

# 1. Upstream-only infrastructure we do not carry.
rm -rf .github cli/.github cli/flake.nix cli/flake.lock cli/default.nix cli/.envrc

# 2. Rename files and directories whose names contain the old name, deepest first.
#    "|| true" guards: on a re-run nothing matches and grep would exit 1 under pipefail.
find . -depth -not -path './.git/*' -iname '*caelestia*' -printf '%P\n' \
  | { grep -vE "$exclude" || true; } \
  | while IFS= read -r path; do
      dir=$(dirname "$path")
      base=$(basename "$path" | sed 's/caelestia/chiroptera/g; s/Caelestia/Chiroptera/g; s/CAELESTIA/CHIROPTERA/g')
      mv "$path" "$dir/$base"
    done

# 3. Rewrite text contents. URLs first so the org name survives only where it must.
mapfile -d '' files < <(
  find . -type f -not -path './.git/*' -printf '%P\0' \
    | { grep -zvE "$exclude" || true; } \
    | { xargs -0 -r grep -lIZ -i 'caelestia' -- 2>/dev/null || true; }
)
if [ "${#files[@]}" -gt 0 ]; then
  perl -pi -e '
      next if /<!-- keep -->/;
      s{github\.com/caelestia-dots/shell}{github.com/'"$GH_USER"'/chiroptera-shell}g;
      s{github\.com/caelestia-dots/cli}{github.com/'"$GH_USER"'/chiroptera-dots}g;
      s{github\.com/caelestia-dots/caelestia}{github.com/'"$GH_USER"'/chiroptera-dots}g;
      s/caelestia(?!-dots|fox|-firefox|-vscode)/chiroptera/g;
      s/Caelestia(?!Fox)/Chiroptera/g;
      s/CAELESTIA/CHIROPTERA/g;
    ' "${files[@]}"
fi

# 4. README banners crediting upstream, inserted once each.
if ! grep -q '<!-- chiroptera-banner -->' README.md; then
  {
    cat <<'BANNER'
<!-- chiroptera-banner -->
# Chiroptera dots

The dotfiles and CLI of ChiropteraOS. Derived from the Caelestia dotfiles and CLI by soramane and contributors: <!-- keep -->
https://github.com/caelestia-dots/caelestia and https://github.com/caelestia-dots/cli (CLI is GPL-3.0, at `cli/`). <!-- keep -->

Upstreams are tracked as the `upstream-dots` and `upstream-cli` git remotes; the CLI lives at `cli/` as a
git subtree. `chiroptera/rename.sh` is the transform applied after each upstream merge;
`chiroptera/check-rename.sh` verifies it. The rest of this README is the upstream documentation with names rewritten.

---

BANNER
    cat README.md
  } > README.md.new
  mv README.md.new README.md
fi

echo "rename: done"
EOF
chmod +x ~/git/chiroptera-dots/chiroptera/rename.sh
```

- [ ] **Step 5: Run the transform, fix hatch-vcs for the subtree, run check and tests**

```bash
cd ~/git/chiroptera-dots
chiroptera/rename.sh
python - <<'EOF'
from pathlib import Path
p = Path("cli/pyproject.toml")
s = p.read_text()
old = '[tool.hatch.version]\nsource = "vcs"\n'
new = '[tool.hatch.version]\nsource = "vcs"\nraw-options = { root = ".." }\n'
assert old in s, "hatch version block not found"
if "raw-options" not in s:
    p.write_text(s.replace(old, new))
print("pyproject ok")
EOF
chiroptera/check-rename.sh; echo "check=$?"
cd cli && python -m unittest discover -s tests -v 2>&1 | tail -3
```

Expected: `rename: done`, `pyproject ok`, `check-rename: ok`, `check=0`, and `OK` with `Ran 6 tests`.

- [ ] **Step 6: Verify the wheel builds from the subtree**

```bash
cd ~/git/chiroptera-dots/cli && rm -rf dist && python -m build --wheel --no-isolation 2>&1 | tail -1 && ls dist/
```

Expected: `Successfully built chiroptera-0.1.dev<N>-py3-none-any.whl` (or similar dev version, since no tag exists yet) and `ls dist/` shows one `chiroptera-*.whl`.

- [ ] **Step 7: Verify key dots files and idempotence**

```bash
cd ~/git/chiroptera-dots
head -6 manifest.toml
grep -n 'chiroptera' hypr/hyprland/execs.lua hypr/hyprland.lua | head -5
grep -c 'chiroptera:' hypr/hyprland/keybinds.lua
grep -n 'name = \|chiroptera = ' cli/pyproject.toml
rm -rf cli/dist
git add -A && chiroptera/rename.sh >/dev/null && echo "second run changed: $(git diff --stat | tail -1)"
```

Expected: manifest starts with `packages = ["chiroptera-shell", "chiroptera-cli"]` and hooks call `chiroptera scheme set -n chiroptera` and `chiroptera shell -d`; `execs.lua` has `hl.exec_cmd("chiroptera shell -d")`; `hyprland.lua` references `/.config/chiroptera/`; keybinds count is at least 5; pyproject has `name = "chiroptera"` and `chiroptera = "chiroptera:main"`; `second run changed:` is followed by nothing.

- [ ] **Step 8: Record upstream bases and commit**

```bash
cd ~/git/chiroptera-dots
{ echo "upstream-dots $(git rev-parse upstream-dots/main)"; echo "upstream-cli $(git rev-parse upstream-cli/main)"; } > .upstream-sync
cat >> .gitignore <<'EOF'

# CLI build output
/cli/dist/
/cli/__pycache__/
EOF
git add -A
git commit -m "Rename Caelestia to Chiroptera

Full-tree transform via chiroptera/rename.sh over the dots and the cli/ subtree:
package and console script names, config/state paths, manifest package list and
hooks, Hyprland shortcut ids, scheme and theme names. Published Firefox and
VS Code integrations are kept verbatim. hatch-vcs root points at the repo root
so the wheel version comes from this repo's tags. Adds CLI rename tests."
git show --stat HEAD | tail -2
```

Expected: commit with `cli/src/{caelestia => chiroptera}/...` renames.

---

### Task 6: Laptop migration script with fixture test

**Files:**
- Create: `~/git/chiroptera-dots/chiroptera/test-migrate.sh`
- Create: `~/git/chiroptera-dots/chiroptera/migrate-from-caelestia.sh`

**Interfaces:**
- Consumes: nothing from the repo except location.
- Produces: `chiroptera/migrate-from-caelestia.sh` — reads `HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_DATA_HOME`, optional `CAELESTIA_LEGACY_DOTS` (default `$XDG_DATA_HOME/caelestia`). Copies `caelestia` config and state dirs to `chiroptera` if the destination does not exist, rewrites names in the copied user files and in the legacy live Hyprland and fish config, backing each edited legacy file up once as `<file>.pre-chiroptera`. Never touches binary files. Exit 0. Re-runnable.

- [ ] **Step 1: Write the fixture test**

```bash
cat > ~/git/chiroptera-dots/chiroptera/test-migrate.sh <<'EOF'
#!/usr/bin/env bash
# Runs migrate-from-caelestia.sh against a throwaway HOME and checks the result.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
H=$(mktemp -d -t chiroptera-migrate-test.XXXXXX)
trap 'rm -rf "$H"' EXIT

mkdir -p "$H/.config/caelestia/monitors/eDP-1" "$H/.local/state/caelestia/wallpaper" \
         "$H/.local/share/caelestia/hypr/hyprland" "$H/.local/share/caelestia/fish/functions"
cat > "$H/.config/caelestia/shell.json" <<'J'
{ "command": [ "caelestia", "wallpaper", "-r" ] }
J
echo '{"toggles": {}}' > "$H/.config/caelestia/cli.json"
echo 'bind = , Print, global, caelestia:screenshotFreeze' > "$H/.config/caelestia/hypr-user.conf"
echo '{ "bar": {} }' > "$H/.config/caelestia/monitors/eDP-1/shell.json"
echo '{"name": "dynamic"}' > "$H/.local/state/caelestia/scheme.json"
printf 'SQLite format 3\000caelestia\000binary' > "$H/.local/state/caelestia/apps.sqlite"
cat > "$H/.local/share/caelestia/hypr/hyprland.conf" <<'C'
$cConf = ~/.config/caelestia
source = $cConf/hypr-user.conf
C
cat > "$H/.local/share/caelestia/hypr/hyprland/execs.conf" <<'C'
exec-once = caelestia resizer -d
exec-once = caelestia shell -d
C
cat > "$H/.local/share/caelestia/hypr/hyprland/keybinds.conf" <<'C'
bindi = Super, Super_L, global, caelestia:launcher
bindr = Ctrl+Super+Shift, R, exec, qs -c caelestia kill
C
echo 'layerrule = blur true, match:namespace caelestia-drawers' > "$H/.local/share/caelestia/hypr/hyprland/rules.conf"
echo 'cat ~/.local/state/caelestia/sequences.txt' > "$H/.local/share/caelestia/fish/config.fish"
echo 'echo caelestia' > "$H/.local/share/caelestia/fish/functions/fish_greeting.fish"
cp "$H/.local/state/caelestia/apps.sqlite" "$H/apps.sqlite.orig"

fail() { echo "FAIL: $*" >&2; exit 1; }

HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" XDG_DATA_HOME="$H/.local/share" \
  "$here/migrate-from-caelestia.sh" > "$H/run1.log"

grep -q '"chiroptera", "wallpaper"' "$H/.config/chiroptera/shell.json" || fail "shell.json command not renamed"
grep -q 'chiroptera:screenshotFreeze' "$H/.config/chiroptera/hypr-user.conf" || fail "hypr-user.conf not renamed"
[ -f "$H/.config/chiroptera/monitors/eDP-1/shell.json" ] || fail "monitor config not copied"
[ -f "$H/.local/state/chiroptera/scheme.json" ] || fail "state not copied"
cmp -s "$H/.local/state/chiroptera/apps.sqlite" "$H/apps.sqlite.orig" || fail "binary state file was altered"
grep -q 'chiroptera:launcher' "$H/.local/share/caelestia/hypr/hyprland/keybinds.conf" || fail "keybinds not renamed"
grep -q 'qs -c chiroptera kill' "$H/.local/share/caelestia/hypr/hyprland/keybinds.conf" || fail "qs -c not renamed"
grep -q 'chiroptera shell -d' "$H/.local/share/caelestia/hypr/hyprland/execs.conf" || fail "execs not renamed"
grep -q 'namespace chiroptera-drawers' "$H/.local/share/caelestia/hypr/hyprland/rules.conf" || fail "rules not renamed"
grep -q '~/.config/chiroptera' "$H/.local/share/caelestia/hypr/hyprland.conf" || fail "hyprland.conf not renamed"
grep -q 'state/chiroptera/sequences.txt' "$H/.local/share/caelestia/fish/config.fish" || fail "fish config not renamed"
grep -q 'echo chiroptera' "$H/.local/share/caelestia/fish/functions/fish_greeting.fish" || fail "fish function not renamed"
[ -f "$H/.local/share/caelestia/hypr/hyprland/keybinds.conf.pre-chiroptera" ] || fail "no backup of edited legacy file"
grep -q 'caelestia:launcher' "$H/.local/share/caelestia/hypr/hyprland/keybinds.conf.pre-chiroptera" || fail "backup is not the original"
[ -d "$H/.config/caelestia" ] || fail "original config dir must be left in place"

# Second run: nothing changes.
before=$(find "$H/.config" "$H/.local" -type f -exec md5sum {} + | sort)
HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" XDG_DATA_HOME="$H/.local/share" \
  "$here/migrate-from-caelestia.sh" > "$H/run2.log"
after=$(find "$H/.config" "$H/.local" -type f -exec md5sum {} + | sort)
[ "$before" = "$after" ] || fail "second run modified files"

echo "test-migrate: ok"
EOF
chmod +x ~/git/chiroptera-dots/chiroptera/test-migrate.sh
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
~/git/chiroptera-dots/chiroptera/test-migrate.sh; echo "exit=$?"
```

Expected: an error that `migrate-from-caelestia.sh` is not found, `exit=127` or `exit=1`.

- [ ] **Step 3: Write the migration script**

```bash
cat > ~/git/chiroptera-dots/chiroptera/migrate-from-caelestia.sh <<'EOF'
#!/usr/bin/env bash
# One-shot migration of a legacy Caelestia install (install.fish era, configs symlinked from
# ~/.local/share/caelestia) to the Chiroptera names. Copies user config and state to the new
# directories, then rewrites names inside the copied user files and inside the live legacy
# Hyprland and fish config. Leaves the Caelestia packages and original dirs in place.
# Re-runnable: copies only when the destination is absent; edits are idempotent.
#
# Rollback of the legacy edits: for each *.pre-chiroptera file, move it back over the original.
set -euo pipefail

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
state=${XDG_STATE_HOME:-$HOME/.local/state}
data=${XDG_DATA_HOME:-$HOME/.local/share}
legacy=${CAELESTIA_LEGACY_DOTS:-$data/caelestia}

copy_tree() { # src dst
  if [ -e "$2" ]; then
    echo "keep    $2 (exists)"
  else
    cp -a "$1" "$2"
    echo "copied  $1 -> $2"
  fi
}

rename_text() { # file... : rewrite names in place, text files only, skip files already clean
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    grep -qI 'caelestia' "$f" 2>/dev/null || continue
    if [ "$BACKUP" = 1 ] && [ ! -e "$f.pre-chiroptera" ]; then
      cp -p "$f" "$f.pre-chiroptera"
    fi
    perl -pi -e 's/caelestia(?!-dots|fox|-firefox|-vscode)/chiroptera/g; s/Caelestia(?!Fox)/Chiroptera/g; s/CAELESTIA/CHIROPTERA/g' "$f"
    echo "edited  $f"
  done
}

if [ -d "$cfg/caelestia" ]; then
  copy_tree "$cfg/caelestia" "$cfg/chiroptera"
fi
if [ -d "$state/caelestia" ]; then
  copy_tree "$state/caelestia" "$state/chiroptera"
fi

# Copied user files: no backups needed, the originals still exist under the caelestia name.
BACKUP=0 rename_text \
  "$cfg/chiroptera/shell.json" "$cfg/chiroptera/cli.json" \
  "$cfg/chiroptera/hypr-user.conf" "$cfg/chiroptera/hypr-vars.conf" \
  "$cfg"/chiroptera/monitors/*/shell.json

# Live legacy config: back up once, then edit in place.
if [ -d "$legacy" ]; then
  BACKUP=1 rename_text \
    "$legacy"/hypr/*.conf "$legacy"/hypr/hyprland/*.conf \
    "$legacy"/fish/config.fish "$legacy"/fish/functions/*.fish
fi

echo "migrate: done"
EOF
chmod +x ~/git/chiroptera-dots/chiroptera/migrate-from-caelestia.sh
```

- [ ] **Step 4: Run the test**

```bash
~/git/chiroptera-dots/chiroptera/test-migrate.sh; echo "exit=$?"
```

Expected: `test-migrate: ok`, `exit=0`.

- [ ] **Step 5: Commit, tag, push**

```bash
cd ~/git/chiroptera-dots
git add chiroptera/migrate-from-caelestia.sh chiroptera/test-migrate.sh
git commit -m "Add legacy Caelestia to Chiroptera migration script with fixture test"
git tag -a v0.1.0 -m "Chiroptera dots and CLI 0.1.0: pure rename of the Caelestia dots and cli"
git push origin main --tags
cd cli && rm -rf dist && python -m build --wheel --no-isolation 2>&1 | tail -1
```

Expected: push succeeds and the wheel is now `chiroptera-0.1.0-py3-none-any.whl`.

---

### Task 7: PKGBUILDs in ChiropteraOS, build and install both packages

**Files:**
- Create: `~/git/ChiropteraOS/pkgs/chiroptera-cli/PKGBUILD`
- Create: `~/git/ChiropteraOS/pkgs/chiroptera-shell/PKGBUILD`
- Create: `~/git/ChiropteraOS/.gitignore`

**Interfaces:**
- Consumes: tags `v0.1.0` on both source repos (Tasks 3 and 6).
- Produces: packages `chiroptera-cli-0.1.0-1-any.pkg.tar.zst` and `chiroptera-shell-0.1.0-1-x86_64.pkg.tar.zst`, installed on the laptop alongside the Caelestia packages. Env overrides `CHIROPTERA_DOTS_REPO` and `CHIROPTERA_SHELL_REPO` let a build use a local clone (`file:///home/g/git/chiroptera-dots`) instead of GitHub.

- [ ] **Step 1: Write the CLI PKGBUILD**

```bash
mkdir -p ~/git/ChiropteraOS/pkgs/chiroptera-cli
cat > ~/git/ChiropteraOS/pkgs/chiroptera-cli/PKGBUILD <<'EOF'
# Maintainer: George (ChiropteraOS)
# Derived from the caelestia-cli AUR package by Soramane.

pkgname=chiroptera-cli
pkgver=0.1.0
pkgrel=1
pkgdesc='The main CLI for ChiropteraOS (derived from caelestia-cli)'
arch=('any')
url='https://github.com/george-leonard314/chiroptera-dots'
license=('GPL-3.0-only')
depends=('python' 'python-pillow' 'python-materialyoucolor' 'libnotify' 'swappy' 'grim' 'dart-sass'
         'wl-clipboard' 'slurp' 'gpu-screen-recorder' 'dconf' 'cliphist' 'fuzzel' 'git')
optdepends=('chiroptera-shell: shell control and screenshot function')
makedepends=('git' 'python-build' 'python-installer' 'python-hatch' 'python-hatch-vcs')
provides=('chiroptera-cli')
# Override with a local clone for development builds, e.g. file:///home/g/git/chiroptera-dots
_repo="${CHIROPTERA_DOTS_REPO:-$url.git}"
source=("chiroptera-dots::git+${_repo}#tag=v${pkgver}")
sha256sums=('SKIP')

build() {
    cd "$srcdir/chiroptera-dots/cli"
    python -m build --wheel --no-isolation
}

package() {
    cd "$srcdir/chiroptera-dots/cli"
    python -m installer --destdir="$pkgdir" dist/*.whl
    install -Dm644 completions/chiroptera.fish "$pkgdir/usr/share/fish/vendor_completions.d/chiroptera.fish"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
EOF
```

- [ ] **Step 2: Write the shell PKGBUILD**

```bash
mkdir -p ~/git/ChiropteraOS/pkgs/chiroptera-shell
cat > ~/git/ChiropteraOS/pkgs/chiroptera-shell/PKGBUILD <<'EOF'
# Maintainer: George (ChiropteraOS)
# Derived from the caelestia-shell AUR package by Soramane.

pkgname=chiroptera-shell
pkgver=0.1.0
pkgrel=1
pkgdesc='The desktop shell for ChiropteraOS (derived from caelestia-shell)'
arch=('x86_64' 'aarch64')
url='https://github.com/george-leonard314/chiroptera-shell'
license=('GPL-3.0-only')
depends=(
    'chiroptera-cli'
    'quickshell-git'
    'glibc'
    'gcc-libs'
    # Brightness
    'ddcutil'
    'brightnessctl'
    # Services
    'libcava'
    'networkmanager'
    'lm_sensors'
    'aubio'
    'libpipewire'
    'libqalculate'
    'power-profiles-daemon'
    # Fonts
    'ttf-material-symbols-variable'
    'ttf-rubik-vf'
    'ttf-cascadia-code-nerd'
    # Qt modules
    'qt6-base'
    'qt6-declarative'
    'qt6-imageformats'
    'qt6-m3shapes-git'
    # Extra functionality
    'swappy'
    'fish'
    'bash'
)
optdepends=(
    'asdbctl: controlling the brightness of Apple Studio Displays'
    'fprintd: fingerprint unlock for the lock screen'
    'howdy-next: face unlock for the lock screen'
)
makedepends=('git' 'cmake' 'ninja' 'qt6-shadertools')
provides=('chiroptera-shell')
# Override with a local clone for development builds, e.g. file:///home/g/git/chiroptera-shell
_repo="${CHIROPTERA_SHELL_REPO:-$url.git}"
source=("chiroptera-shell::git+${_repo}#tag=v${pkgver}")
sha256sums=('SKIP')

build() {
    cd "$srcdir/chiroptera-shell"
    cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/ \
        -DVERSION="$pkgver" \
        -DGIT_REVISION="$(git rev-parse HEAD)" \
        -DDISTRIBUTOR="ChiropteraOS (package: $pkgname)"
    cmake --build build
}

package() {
    cd "$srcdir/chiroptera-shell"
    DESTDIR="$pkgdir" cmake --install build
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
EOF
cat > ~/git/ChiropteraOS/.gitignore <<'EOF'
# makepkg output
pkgs/*/src/
pkgs/*/pkg/
pkgs/*/*.pkg.tar.*
pkgs/*/*.log
EOF
```

- [ ] **Step 3: Build and inspect the CLI package**

```bash
cd ~/git/ChiropteraOS/pkgs/chiroptera-cli
makepkg -sf --noconfirm 2>&1 | tail -3
pacman -Qlp chiroptera-cli-0.1.0-1-any.pkg.tar.zst | grep -E 'bin/chiroptera$|site-packages/chiroptera/__init__.py|vendor_completions.d/chiroptera.fish'
pacman -Qlp chiroptera-cli-0.1.0-1-any.pkg.tar.zst | grep -ci caelestia
```

Expected: `Finished making: chiroptera-cli 0.1.0-1`; three matching file lines; count `0`. If the clone fails with an auth prompt, run `gh auth setup-git` and retry, or set `CHIROPTERA_DOTS_REPO=file:///home/g/git/chiroptera-dots`.

- [ ] **Step 4: Install the CLI package and smoke test**

```bash
cd ~/git/ChiropteraOS/pkgs/chiroptera-cli && sudo pacman -U --noconfirm chiroptera-cli-0.1.0-1-any.pkg.tar.zst
chiroptera --help | head -1
chiroptera -v 2>&1 | head -4
which caelestia chiroptera
```

Expected: `usage: chiroptera [-h] ...`; version output lists `chiroptera-cli` as installed (shell still `not installed`); both executables exist.

- [ ] **Step 5: Build, inspect, and install the shell package**

```bash
cd ~/git/ChiropteraOS/pkgs/chiroptera-shell
makepkg -sf --noconfirm 2>&1 | tail -3
pacman -Qlp chiroptera-shell-0.1.0-1-x86_64.pkg.tar.zst | grep -E 'quickshell/chiroptera/shell.qml|qml/Chiroptera/qmldir|qml/Chiroptera/Config/qmldir|/usr/lib/chiroptera/version$'
pacman -Qlp chiroptera-shell-0.1.0-1-x86_64.pkg.tar.zst | grep -ci caelestia
sudo pacman -U --noconfirm chiroptera-shell-0.1.0-1-x86_64.pkg.tar.zst
/usr/lib/chiroptera/version -s
pacman -Q caelestia-shell chiroptera-shell
```

Expected: `Finished making: chiroptera-shell 0.1.0-1`; four matching lines; count `0`; install succeeds with no file conflicts; `chiroptera-shell 0.1.0, revision <sha>, distributed by: ChiropteraOS (package: chiroptera-shell)`; both packages listed.

- [ ] **Step 6: Commit the packaging**

```bash
cd ~/git/ChiropteraOS
git add .gitignore pkgs/
git commit -m "Add chiroptera-cli and chiroptera-shell PKGBUILDs

Build from git tags of the source repos. Repo URL overridable through
CHIROPTERA_DOTS_REPO / CHIROPTERA_SHELL_REPO for local development builds."
```

---

### Task 8: Switch the laptop to Chiroptera Shell and document the sync ritual

**Files:**
- Modify (laptop, outside git): `~/.config/chiroptera/` (new copy), `~/.local/state/chiroptera/` (new copy), `~/.local/share/caelestia/hypr/**/*.conf`, `~/.local/share/caelestia/fish/config.fish`, `~/.local/share/caelestia/fish/functions/*.fish`
- Create: `~/git/ChiropteraOS/docs/upstream-sync.md`
- Modify: `~/git/ChiropteraOS/docs/superpowers/specs/2026-09-09-chiroptera-os-design.md` sections 3.4 and 4.1

**Interfaces:**
- Consumes: installed packages from Task 7, migration script from Task 6.
- Produces: laptop running `chiroptera shell -d` from the live Hyprland config; documented ritual for merging upstream.

- [ ] **Step 1: Run the migration on the laptop**

```bash
~/git/chiroptera-dots/chiroptera/migrate-from-caelestia.sh
ls ~/.config/chiroptera ~/.local/state/chiroptera
grep -c 'caelestia:' ~/.local/share/caelestia/hypr/hyprland/keybinds.conf
grep -n 'chiroptera' ~/.local/share/caelestia/hypr/hyprland/execs.conf
```

Expected: `copied` lines for config and state, `edited` lines for at least `hyprland.conf`, `execs.conf`, `keybinds.conf`, `rules.conf`, `gestures.conf`, `fish/config.fish`, `shell.json`, and `hypr-user.conf`; shortcut count `0` (a comment mentioning the upstream org may remain, that is allowed); execs shows `exec-once = chiroptera resizer -d` and `exec-once = chiroptera shell -d`.

- [ ] **Step 2: Reload Hyprland and swap the running shell**

```bash
hyprctl reload
caelestia shell -k 2>/dev/null || true
sleep 1
chiroptera shell -d > /dev/null
sleep 3
pgrep -af 'qs -c chiroptera' | head -1
pgrep -af 'qs -c caelestia' || echo "no caelestia instance"
```

Expected: one `qs -c chiroptera -n -d` process; `no caelestia instance`.

- [ ] **Step 3: Verify the shell is serving the desktop**

```bash
hyprctl layers | grep -o 'namespace: chiroptera-[a-z-]*' | sort -u
qs -c chiroptera ipc show | head -5
hyprctl binds | grep -c 'chiroptera:'
```

Expected: at least `chiroptera-background` and `chiroptera-drawers` layers; the ipc listing prints targets; the binds count is at least 15. Then press Super once on the laptop: the launcher must open. Press Super+Shift+S: the screenshot picker must open. Report both results in the task summary.

- [ ] **Step 4: Write the upstream sync ritual**

```bash
cat > ~/git/ChiropteraOS/docs/upstream-sync.md <<'EOF'
# Upstream sync ritual

Both source repos are full-history copies of their Caelestia upstreams with the
rename transform (`chiroptera/rename.sh`) committed on top. Syncing means: apply
the same transform to upstream's new tree, then merge that. Because the transform
is deterministic, the rename itself never conflicts; only upstream edits adjacent
to renamed text do, and those are mechanical.

Nothing here runs automatically. Do it when a change upstream is worth having.

## chiroptera-shell

```sh
cd ~/git/chiroptera-shell
git fetch upstream
git log --oneline "$(cut -d' ' -f2 .upstream-sync)..upstream/main"   # what changed
git checkout -b sync upstream/main
bash <(git show main:chiroptera/rename.sh)
git add -A && git commit -m "Apply Chiroptera transform to upstream $(git rev-parse --short upstream/main)"
git checkout main
git merge sync            # resolve conflicts, keep both the rename and upstream's edit
echo "upstream $(git rev-parse upstream/main)" > .upstream-sync
chiroptera/check-rename.sh
cmake -B build -G Ninja -DVERSION=0 -DGIT_REVISION=0 && cmake --build build
git add -A && git commit -m "Merge upstream $(git rev-parse --short upstream/main)"
git branch -D sync
```

## chiroptera-dots

Dots come from `upstream-dots`; the CLI comes from `upstream-cli` through the
`cli/` subtree. They are merged in two moves: the dots through a transformed
branch, the CLI through `git subtree pull` followed by re-running the transform.

```sh
cd ~/git/chiroptera-dots
git fetch upstream-dots && git fetch upstream-cli main
git log --oneline "$(grep upstream-dots .upstream-sync | cut -d' ' -f2)..upstream-dots/main"
git log --oneline "$(grep upstream-cli .upstream-sync | cut -d' ' -f2)..upstream-cli/main"

# 1. Dots: transform upstream on a branch, merge it.
git checkout -b sync upstream-dots/main
bash <(git show main:chiroptera/rename.sh)
git add -A && git commit -m "Apply Chiroptera transform to upstream-dots $(git rev-parse --short upstream-dots/main)"
git checkout main
git merge sync            # resolve conflicts, keep both the rename and upstream's edit
git branch -D sync

# 2. CLI: subtree merge, then re-apply the transform to the merged files.
git subtree pull --prefix=cli upstream-cli main -m "Merge upstream-cli $(git rev-parse --short upstream-cli/main) into cli/"
chiroptera/rename.sh
git add -A && git commit -m "Re-apply Chiroptera transform after cli merge"

# 3. Record, verify.
{ echo "upstream-dots $(git rev-parse upstream-dots/main)"; echo "upstream-cli $(git rev-parse upstream-cli/main)"; } > .upstream-sync
chiroptera/check-rename.sh
(cd cli && python -m unittest discover -s tests)
chiroptera/test-migrate.sh
git add -A && git commit -m "Merge upstreams"
```

The subtree pull merges upstream's unrenamed CLI text into renamed files, so
conflicts there are lines upstream changed next to a renamed token. Take
upstream's edit, then let `rename.sh` rename it.

## After either sync

Bump `pkgver` in `ChiropteraOS/pkgs/*/PKGBUILD`, tag the source repo
(`git tag -a vX.Y.Z`), push with `--tags`, rebuild, install, and run the
laptop checks from the step 1 plan, Task 8.
EOF
```

- [ ] **Step 5: Amend the spec to match the transform approach**

```bash
cd ~/git/ChiropteraOS && python - <<'EOF'
from pathlib import Path
p = Path("docs/superpowers/specs/2026-09-09-chiroptera-os-design.md")
s = p.read_text()

old_a = ("Each source repo has `scripts/sync-upstream.sh`. It fetches every\n"
         "`upstream*` remote and prints the commits since the recorded last sync,\n"
         "grouped by top-level directory, with a marker for files the author has\n"
         "modified. It never merges.\n")
new_a = ("Each source repo carries a deterministic rename transform,\n"
         "`chiroptera/rename.sh`, and its assertion, `chiroptera/check-rename.sh`.\n"
         "The transform renames every `caelestia` token including the QML plugin\n"
         "module URI, so the two shells install side by side. Syncing applies the\n"
         "transform to upstream's tree on a branch and merges that, so the rename\n"
         "itself never conflicts. The ritual is written in `docs/upstream-sync.md`.\n"
         "A later step adds `chiroptera/sync-upstream.sh` that fetches every\n"
         "`upstream*` remote and prints the commits since the recorded last sync,\n"
         "grouped by top-level directory. It never merges.\n")
assert old_a in s, "3.4 paragraph not found"
s = s.replace(old_a, new_a)

old_b = ("Upstream structure is kept: `modules/` for UI, `services/` for system state,\n"
         "`config/` for the JSON schema, `utils/` for helpers, `assets/` for icons and\n"
         "fonts. Upstream files are edited only where a hook is needed to mount a new\n"
         "module. All new code lives in new directories:\n")
new_b = ("Upstream structure is kept: `modules/` for UI, `services/` for system state,\n"
         "`plugin/src/Chiroptera/` for the C++ QML plugin (renamed from `Caelestia`),\n"
         "`utils/` for helpers, `assets/` for icons and fonts. Beyond the rename\n"
         "transform, upstream files are edited only where a hook is needed to mount a\n"
         "new module. All new code lives in new directories:\n")
assert old_b in s, "4.1 paragraph not found"
s = s.replace(old_b, new_b)
p.write_text(s)
print("spec amended")
EOF
```

Expected: `spec amended`.

- [ ] **Step 6: Commit the documentation**

```bash
cd ~/git/ChiropteraOS
git add docs/upstream-sync.md docs/superpowers/specs/2026-09-09-chiroptera-os-design.md
git commit -m "Document the upstream sync ritual and the rename transform approach"
git log --oneline -4
```

Expected: four commits listed, newest first: documentation, PKGBUILDs, the step 1 plan, the CachyOS spec change.

- [ ] **Step 7: Final laptop state summary**

```bash
pacman -Q caelestia-shell caelestia-cli chiroptera-shell chiroptera-cli
chiroptera -v 2>&1 | sed -n '1,6p'
find ~/.local/share/caelestia -name '*.pre-chiroptera' | wc -l
```

Expected: all four packages present; version output shows both chiroptera packages installed and the shell line `chiroptera-shell 0.1.0`; backup count equals the number of edited legacy files (at least 6). Report this output verbatim in the task summary.

Rollback if the desktop is broken: `for b in $(find ~/.local/share/caelestia -name '*.pre-chiroptera'); do mv "$b" "${b%.pre-chiroptera}"; done; hyprctl reload; chiroptera shell -k; caelestia shell -d`.
