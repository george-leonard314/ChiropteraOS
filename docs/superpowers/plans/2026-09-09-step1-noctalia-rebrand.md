# Step 1: Chiroptera Shell from Noctalia Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a full-history copy of Noctalia v5 into Chiroptera Shell: every `noctalia` token renamed, the Luau plugin API aliased so existing plugins keep working, the upstream test suite passing, the shell packaged and running as the author's session shell.

**Architecture:** `chiroptera-shell` is a clone of `noctalia-dev/noctalia` with a fetch-only `upstream` remote and a deterministic, idempotent transform (`chiroptera/rename.sh`) committed on top, verified by `chiroptera/check-rename.sh`. The transform renames the binary, Meson project, C++ identifiers, D-Bus names, XDG dirs, env vars, translations, docs, and asset file names, and preserves upstream org, domains, the greeter package name, and official plugin ids. The plugin API alias is an ordinary source commit with a unit test in the upstream test framework. `ChiropteraOS` gets a PKGBUILD that builds the shell with Meson from a git tag. The laptop switches by migrating Noctalia's state dir and pointing Hyprland's autostart and the spike binds at `chiroptera`.

**Tech Stack:** git, bash, perl, Meson + Ninja, GCC 16 (C++23), Luau (vendored), makepkg/pacman, GitHub CLI, Hyprland 0.56.

**Spec:** `docs/superpowers/specs/2026-09-09-chiroptera-os-design.md` sections 3.1, 3.4, 4.1, 4.2, 6.1, 11 step 1.

## Global Constraints

- Repo `chiroptera-shell` on GitHub user `george-leonard314`, private. It currently holds the dropped caelestia-based history; the new history is force-pushed over it. Local path `~/git/chiroptera-shell`. Git auth is HTTPS via the `gh` credential helper.
- Full upstream history kept. Remote `upstream` = `https://github.com/noctalia-dev/noctalia.git`, fetch only (`--no-tags`, push URL `DISABLED`). Upstream HEAD at plan time: `d6607b4e`; record the actual sha in `.upstream-sync`.
- Rename targets: binary `chiroptera`; Meson project `chiroptera`; config `~/.config/chiroptera/`; state `~/.local/state/chiroptera/`; assets `/usr/share/chiroptera/`; IPC `chiroptera msg`; D-Bus prefix `dev.chiroptera.`; desktop entry `dev.chiroptera.Chiroptera.desktop`; icon `chiroptera.svg`; layer namespaces `chiroptera-*`; env vars `CHIROPTERA_*`; Luau global `chiroptera`.
- Preserved verbatim, never rewritten: `noctalia-dev` (GitHub org), `noctalia.dev` and its subdomains (upstream API endpoints and docs), `noctalia-greeter` and `NOCTALIA_GREETER_*` (a separate package the shell talks to), official plugin ids `noctalia/<name>` for name in `bitwarden bongocat example kaomoji mpvpaper notes screen_recorder timer translator umbriel-companion wallhaven wallpaper_depth world_clock`, lines carrying `<!-- keep -->` or `noctalia-compat`, and the files `LICENSE` (MIT copyright notice must survive), `CREDITS.md`, everything under `third_party/`, and `tests/plugin_api_alias_test.cpp`.
- Upstream infrastructure deleted by the transform: `.github/`, `nix/`, `flake.nix`, `flake.lock`, `default.nix`, `noctalia.scm`, `lefthook.yml`.
- Meson `version:` stays `5.0.1` (upstream's); plugins gate compatibility on it. Our release identity is the git tag `v5.0.1-chiroptera1` and pacman `pkgver=5.0.1.chiroptera1`.
- The Luau API table is registered as `chiroptera` and the global `noctalia` is bound to the same table (spec 4.2).
- Tests are the upstream Meson suite (`-Dtests=enabled`, debug build) plus the new alias test. All must pass.
- The laptop currently runs `noctalia` from the AUR package `noctalia-git` (left installed), started manually; Hyprland autostart still names caelestia. State lives in `~/.local/state/noctalia/`. Spike binds live in `~/.config/caelestia/hypr-user.conf` between `# >>> noctalia spike` and `# <<< noctalia spike <<<`, plus `~/.local/bin/chiroptera-super-tap` and `~/.local/bin/chiroptera-toggle`.
- Personal files never enter any repo.

---

## File Structure

**chiroptera-shell** (clone of noctalia-dev/noctalia):
- `chiroptera/rename.sh` — idempotent transform.
- `chiroptera/check-rename.sh` — assertion; exit 0 only when clean.
- `.upstream-sync` — `upstream <sha>`.
- `tests/plugin_api_alias_test.cpp` — proves `noctalia` and `chiroptera` are the same table.
- `src/scripting/luau_host.cpp` — alias lines in `registerChiropteraLib` (renamed from `registerNoctaliaLib`).
- `meson.build` — one entry added to `_cpp_test_names`.
- Everything else: upstream files, renamed. Assets renamed: `assets/chiroptera.svg`, `assets/chiroptera-wallpaper.png`, `assets/dev.chiroptera.Chiroptera.desktop`, `assets/fonts/chiroptera-tabler.ttf`.

**ChiropteraOS**:
- `pkgs/chiroptera-shell/PKGBUILD`
- `docs/upstream-sync.md` — rewritten for the Noctalia base.

**Laptop (outside git)**: `~/.local/state/chiroptera/` (copied from noctalia), `~/.config/chiroptera/`, edited spike block and scripts, edited `~/.local/share/caelestia/hypr/hyprland/execs.conf` with a `.pre-chiroptera` backup.

---

### Task 1: Bootstrap chiroptera-shell from Noctalia

**Files:**
- Create: `~/git/chiroptera-shell/` (full-history clone)
- Overwrite: GitHub repo `george-leonard314/chiroptera-shell` history (force-push)

**Interfaces:**
- Produces: local repo with remotes `origin` (ours) and `upstream` (Noctalia, fetch only, no tags), branch `main` force-pushed, zero local tags.

- [ ] **Step 1: Clone upstream with history and wire the remotes**

```bash
cd ~/git
git clone https://github.com/noctalia-dev/noctalia.git chiroptera-shell
cd chiroptera-shell
git remote rename origin upstream
git remote set-url --push upstream DISABLED
git config remote.upstream.tagOpt --no-tags
git tag -l | xargs -r git tag -d
git remote add origin https://github.com/george-leonard314/chiroptera-shell.git
git remote -v
git tag -l | wc -l
git rev-parse --short HEAD
```

Expected: four remote lines (`origin` fetch/push to `george-leonard314/chiroptera-shell.git`, `upstream` fetch to `noctalia-dev/noctalia.git`, push `DISABLED`); tag count `0`; HEAD is a 7-character sha (plan time: `d6607b4`).

- [ ] **Step 2: Replace the old repository history**

The GitHub repo still holds the caelestia-based history that the user chose to drop. Overwrite it.

```bash
cd ~/git/chiroptera-shell
git push --force -u origin main
git push origin --delete v0.1.0 2>&1 | tail -1
git ls-remote origin | cut -c1-12,41-
gh repo view george-leonard314/chiroptera-shell --json isPrivate --jq .isPrivate
```

Expected: the push succeeds (`forced update`), the old tag deletion prints `- [deleted]         v0.1.0`, `ls-remote` shows only `HEAD` and `refs/heads/main` at the same sha as local HEAD, and `true`.

- [ ] **Step 3: Confirm the tree is untouched upstream**

```bash
cd ~/git/chiroptera-shell && git status --porcelain | wc -l && ls && sed -n 1,3p meson.build
```

Expected: `0`; the listing includes `meson.build src tests docs assets third_party`; `project('noctalia', ['c', 'cpp'],` and `version: '5.0.1',`.

---

### Task 2: Rename transform and check

**Files:**
- Create: `~/git/chiroptera-shell/chiroptera/check-rename.sh`
- Create: `~/git/chiroptera-shell/chiroptera/rename.sh`
- Create: `~/git/chiroptera-shell/.upstream-sync`
- Modify: about 580 files; four asset files renamed; upstream infra deleted.

**Interfaces:**
- Consumes: Task 1 repo.
- Produces: tree where `meson.build` says `project('chiroptera'`, `src/scripting/luau_host.cpp` has `registerChiropteraLib` registering `"chiroptera"`, `src/config/cli.cpp` resolves `configHome / "chiroptera"`, the desktop entry is `assets/dev.chiroptera.Chiroptera.desktop` with `Exec=chiroptera --daemon`, D-Bus names `dev.chiroptera.*`, env vars `CHIROPTERA_*` except `NOCTALIA_GREETER_STATE_DIR`. Scripts: `chiroptera/rename.sh` (no args, exit 0), `chiroptera/check-rename.sh` (exit 0 when clean).

- [ ] **Step 1: Write the check script (the test)**

```bash
mkdir -p ~/git/chiroptera-shell/chiroptera
cat > ~/git/chiroptera-shell/chiroptera/check-rename.sh <<'EOF'
#!/usr/bin/env bash
# Fails if any reference to the upstream name survives outside the allowlist.
# Allowed: the upstream GitHub org, upstream domains, the separate greeter package,
# official plugin ids (author namespace "noctalia"), lines marked <!-- keep --> or
# noctalia-compat, the MIT license and credits, vendored third_party code, the alias
# test that names both globals on purpose, and this tooling directory.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

plugins='bitwarden|bongocat|example|kaomoji|mpvpaper|notes|screen_recorder|timer|translator|umbriel-companion|wallhaven|wallpaper_depth|world_clock'
allow="noctalia-dev|noctalia-greeter|noctalia\.dev|noctalia-compat|NOCTALIA_GREETER|noctalia/($plugins)\b|<!-- keep -->|^\./(chiroptera|third_party|LICENSE|CREDITS\.md|tests/plugin_api_alias_test\.cpp)(/|:)"
status=0

leftovers=$(find . -type f -not -path './.git/*' -not -path './build*/*' -print0 \
  | xargs -0 grep -HnI -i 'noctalia' -- 2>/dev/null | grep -vE "$allow" || true)
if [ -n "$leftovers" ]; then
  echo "check-rename: leftover references:" >&2
  echo "$leftovers" >&2
  status=1
fi

paths=$(find . -not -path './.git/*' -not -path './build*/*' -not -path './third_party/*' -iname '*noctalia*' || true)
if [ -n "$paths" ]; then
  echo "check-rename: leftover paths:" >&2
  echo "$paths" >&2
  status=1
fi

for f in .github nix flake.nix flake.lock default.nix noctalia.scm lefthook.yml; do
  if [ -e "$f" ]; then
    echo "check-rename: $f must not exist" >&2
    status=1
  fi
done

if ! grep -q 'Copyright' LICENSE; then
  echo "check-rename: LICENSE lost its copyright notice" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "check-rename: ok"
fi
exit "$status"
EOF
chmod +x ~/git/chiroptera-shell/chiroptera/check-rename.sh
```

- [ ] **Step 2: Run the check to verify it fails on the untouched tree**

```bash
cd ~/git/chiroptera-shell && chiroptera/check-rename.sh 2>&1 | tail -12; echo "exit=${PIPESTATUS[0]}"
```

Expected: thousands of `leftover references` lines (tail shows the end of them), a `leftover paths` block listing `./noctalia.scm`, `./assets/noctalia.svg`, `./assets/noctalia-wallpaper.png`, `./assets/dev.noctalia.Noctalia.desktop`, `./assets/fonts/noctalia-tabler.ttf`, seven `must not exist` lines, and `exit=1`.

- [ ] **Step 3: Write the rename transform**

```bash
cat > ~/git/chiroptera-shell/chiroptera/rename.sh <<'EOF'
#!/usr/bin/env bash
# Idempotent transform: turn an upstream Noctalia tree into Chiroptera Shell.
# Run after every upstream merge (see ChiropteraOS/docs/upstream-sync.md). Safe to re-run.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

GH_USER=george-leonard314
# Never renamed or rewritten: our tooling, build dirs, vendored code, the MIT notice and
# credits, and the alias test that names both API globals on purpose.
exclude='^(chiroptera|build[^/]*|third_party|LICENSE|CREDITS\.md|tests/plugin_api_alias_test\.cpp)(/|$)'
# Official plugins are published under the author namespace "noctalia"; their ids stay.
plugins='bitwarden|bongocat|example|kaomoji|mpvpaper|notes|screen_recorder|timer|translator|umbriel-companion|wallhaven|wallpaper_depth|world_clock'

# 1. Upstream-only infrastructure we do not carry.
rm -rf .github nix flake.nix flake.lock default.nix noctalia.scm lefthook.yml

# 2. Rename files and directories whose names contain the old name, deepest first.
#    "|| true" guards: on a re-run nothing matches and grep would exit 1 under pipefail.
find . -depth -not -path './.git/*' -not -path './build*/*' -iname '*noctalia*' -printf '%P\n' \
  | { grep -vE "$exclude" || true; } \
  | while IFS= read -r path; do
      dir=$(dirname "$path")
      base=$(basename "$path" | sed 's/noctalia/chiroptera/g; s/Noctalia/Chiroptera/g; s/NOCTALIA/CHIROPTERA/g')
      mv "$path" "$dir/$base"
    done

# 3. Rewrite text contents. The upstream repo URL first, then the generic rules with
#    lookaheads that protect the org, domains, greeter, plugin ids, and marked lines.
mapfile -d '' files < <(
  find . -type f -not -path './.git/*' -not -path './build*/*' -printf '%P\0' \
    | { grep -zvE "$exclude" || true; } \
    | { xargs -0 -r grep -lIZ -i 'noctalia' -- 2>/dev/null || true; }
)
if [ "${#files[@]}" -gt 0 ]; then
  perl -pi -e '
      next if /<!-- keep -->|noctalia-compat/;
      s{github\.com/noctalia-dev/noctalia(?![A-Za-z0-9-])}{github.com/'"$GH_USER"'/chiroptera-shell}g;
      s{noctalia(?!-dev\b|-greeter|\.dev\b|-compat|/(?:'"$plugins"')\b)}{chiroptera}g;
      s/Noctalia/Chiroptera/g;
      s/NOCTALIA(?!_GREETER)/CHIROPTERA/g;
    ' "${files[@]}"
fi

# 4. README banner crediting upstream, inserted once.
if ! grep -q '<!-- chiroptera-banner -->' README.md; then
  {
    cat <<'BANNER'
<!-- chiroptera-banner -->
# Chiroptera Shell

The desktop shell of ChiropteraOS. A rebrand of Noctalia by the Noctalia team and contributors, MIT licensed: <!-- keep -->
https://github.com/noctalia-dev/noctalia <!-- keep -->

Upstream is tracked as the `upstream` git remote. `chiroptera/rename.sh` is the transform applied
after each upstream merge; `chiroptera/check-rename.sh` verifies it. Plugins written for Noctalia
keep working: the Luau API is registered as `chiroptera` with `noctalia` as an alias.
The rest of this README is the upstream documentation with names rewritten.

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

Expected: `rename: done`, `check-rename: ok`, `exit=0`. If leftovers print, each is either a real miss (fix the regex in the script and re-run; never hand-edit the file) or a token that belongs on the allowlist (add it to both scripts and say why in the report).

- [ ] **Step 5: Verify key files by content**

```bash
cd ~/git/chiroptera-shell
sed -n 1,2p meson.build
grep -n "registerChiropteraLib\|luaL_register(L, \"chiroptera\"" src/scripting/luau_host.cpp | head -3
grep -n 'configHome / "chiroptera"\|stateHome / "chiroptera"' src/config/cli.cpp
ls assets | grep -i chiroptera; ls assets/fonts
grep -n 'Exec=\|Icon=\|Name=' assets/dev.chiroptera.Chiroptera.desktop
grep -rhoE 'dev\.chiroptera\.[A-Za-z]+' src | sort -u | head -4
grep -rhoE 'NOCTALIA_[A-Z_]+|CHIROPTERA_[A-Z_]+' src | sort -u
grep -rn 'api.noctalia.dev/ping\|noctalia-dev/official-plugins\|noctalia-greeter-sync' src | wc -l
grep -c 'Copyright' LICENSE
head -3 README.md
```

Expected: `project('chiroptera', ['c', 'cpp'],` and `version: '5.0.1',`; the register function and the `"chiroptera"` registration; both dir lines in cli.cpp; `chiroptera.svg chiroptera-wallpaper.png dev.chiroptera.Chiroptera.desktop` and `chiroptera-tabler.ttf`; `Exec=chiroptera --daemon`, `Icon=chiroptera`, `Name=Chiroptera`; D-Bus names starting `dev.chiroptera.`; env var list shows only `CHIROPTERA_*` names plus `NOCTALIA_GREETER_STATE_DIR`; the preserved-token count is `3` or more (not 0); LICENSE copyright count at least `1`; README starts with the banner.

- [ ] **Step 6: Verify idempotence**

```bash
cd ~/git/chiroptera-shell && git add -A && chiroptera/rename.sh && echo "second run changed: $(git diff --stat | tail -1)"
```

Expected: `rename: done` then `second run changed:` followed by nothing.

- [ ] **Step 7: Record the upstream base and commit**

```bash
cd ~/git/chiroptera-shell
echo "upstream $(git rev-parse upstream/main)" > .upstream-sync
git add -A
git commit -m "Rename Noctalia to Chiroptera

Full-tree transform via chiroptera/rename.sh: binary and Meson project, C++
identifiers, D-Bus names, XDG dirs, env vars, Luau API table, translations,
docs, desktop entry, and asset file names. Preserves the upstream org and
domains, the noctalia-greeter integration, official plugin ids, the MIT
notice and credits. Drops Nix, Guix, and upstream CI. Upstream base recorded
in .upstream-sync."
git show --stat HEAD | tail -2
```

Expected: several hundred files changed, with `assets/{noctalia.svg => chiroptera.svg}` style renames.

---

### Task 3: Build the renamed tree and pass the upstream test suite

**Files:**
- Uses: `~/git/chiroptera-shell/build/` (gitignored by upstream's `build*/` rule)

**Interfaces:**
- Consumes: Task 2 tree.
- Produces: a debug build with tests at `build/`, `build/chiroptera` binary, all upstream tests passing. Any rename-caused compile or test failure fixed in source with a `rename:` commit.

- [ ] **Step 1: Configure a debug build with tests**

```bash
cd ~/git/chiroptera-shell
meson setup build --buildtype=debug -Dtests=enabled 2>&1 | tail -5
```

Expected: ends with `Found ninja` and a build summary; no `ERROR:`. If a dependency is missing, the message names the pkg-config module; install it with `sudo pacman -S --needed <package>` only if it is one of the packages in the AUR `noctalia-git` dependency list (Task 5 PKGBUILD), and note it in the report.

- [ ] **Step 2: Compile**

```bash
cd ~/git/chiroptera-shell && meson compile -C build 2>&1 | tail -3; echo "exit=${PIPESTATUS[0]}"
```

Expected: `exit=0`. On a compile error, capture the first error with file and line. If it names an identifier the rename split inconsistently (for example a macro or generated header that still says the old name, or a string literal now mismatching a renamed file), fix the source so the two sides agree, re-run `chiroptera/check-rename.sh`, commit with a `rename:` message, and rebuild. If it is unrelated to the rename, report BLOCKED with the error text.

- [ ] **Step 3: Run the test suite**

```bash
cd ~/git/chiroptera-shell && meson test -C build --print-errorlogs 2>&1 | tail -15
```

Expected: a summary line `Ok: <N>` with `Fail: 0` where N is at least 113 (the upstream `_cpp_test_names` list has 113 entries plus `upower_charge_limit_integration`, `config_validate_cli`, `template_undo_signal`). If a test fails, read its error log: tests such as `config_migration`, `plugin_lifecycle`, `app_identity`, and `config_validate_cli` carry the old name in fixtures and paths that the transform rewrote; a failure there points at a fixture the transform touched inconsistently (for example a path expectation in `tests/config_validate/`). Fix source or fixture consistently, commit as `rename: ...`, re-run.

- [ ] **Step 4: Sanity-run the binary offline**

```bash
cd ~/git/chiroptera-shell
./build/chiroptera --version
./build/chiroptera --help | head -3
CHIROPTERA_CONFIG_HOME=/tmp/claude-1000/ct-cfg CHIROPTERA_STATE_HOME=/tmp/claude-1000/ct-state ./build/chiroptera config validate 2>&1 | tail -3; echo "exit=$?"
```

Expected: a version line containing `5.0.1`; `Usage: chiroptera <command> [options]`; config validation of an empty config succeeds or reports only that no config exists, without crashing.

- [ ] **Step 5: Commit any fixes**

If Steps 2 or 3 required source changes, they are already committed. Confirm: `git status --porcelain | wc -l` prints `0` and `git log --oneline -3` lists the rename commit plus any `rename:` fix commits.

---

### Task 4: Plugin API alias with a unit test, tag, and push

**Files:**
- Create: `~/git/chiroptera-shell/tests/plugin_api_alias_test.cpp`
- Modify: `~/git/chiroptera-shell/meson.build` (`_cpp_test_names` list, around line 1139)
- Modify: `~/git/chiroptera-shell/src/scripting/luau_host.cpp` (`registerChiropteraLib`, around line 1801)

**Interfaces:**
- Consumes: Task 3 build directory.
- Produces: in every plugin VM, the global `noctalia` is the same table as `chiroptera`. Tag `v5.0.1-chiroptera1` pushed with `main`.

- [ ] **Step 1: Write the failing test**

Copy the include block of the existing host-based test so the same headers are used, then add the alias assertions.

```bash
cd ~/git/chiroptera-shell
{ sed -n '1,/^} \/\/ namespace$/p' tests/plugin_process_test.cpp | grep -E '^#include' ; cat <<'EOF'

// Plugins written for Noctalia call `noctalia.*`. Chiroptera registers the API as
// `chiroptera` and must expose `noctalia` as an alias to the very same table.
int main() {
  scripting::ScriptApiContext api;
  api.setConfigSnapshot(std::make_shared<const toml::table>(toml::parse("[shell]\noffline_mode = true")));
  LuauHost host(api, "test/plugin:service");

  TEST_CHECK(host.exec("primary", "assert(type(chiroptera) == 'table', 'chiroptera API table missing')"));
  TEST_CHECK(host.exec("alias", "assert(type(noctalia) == 'table', 'noctalia alias missing')"));
  TEST_CHECK(host.exec("same", "assert(rawequal(noctalia, chiroptera), 'noctalia must be the same table as chiroptera')"));
  TEST_CHECK(host.exec("members", "assert(noctalia.state ~= nil and noctalia.json ~= nil and noctalia.sound ~= nil and noctalia.string ~= nil)"));
  return 0;
}
EOF
} > tests/plugin_api_alias_test.cpp
grep -c '#include' tests/plugin_api_alias_test.cpp
python3 - <<'EOF'
from pathlib import Path
p = Path("meson.build"); s = p.read_text()
old = "  _cpp_test_names = [\n"
assert old in s and "'plugin_api_alias'" not in s
p.write_text(s.replace(old, old + "    'plugin_api_alias',\n", 1))
print("meson test list updated")
EOF
```

Expected: an include count of at least 3 (the process test's headers include `scripting/luau_host.h`, `scripting/script_api_context.h`, `tests/test_check.h`; if `toml++` or `<memory>` are missing from that block, add `#include <toml++/toml.hpp>` and `#include <memory>` by hand) and `meson test list updated`.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ~/git/chiroptera-shell && meson compile -C build plugin_api_alias_test 2>&1 | tail -2 && meson test -C build plugin_api_alias --print-errorlogs 2>&1 | grep -E 'check failed|alias missing|Fail:|Ok:'
```

Expected: the test compiles, then fails with `check failed: host.exec("alias", ...)` (the Luau assertion message `noctalia alias missing` appears in the error log) and `Fail: 1`.

- [ ] **Step 3: Add the alias**

In `src/scripting/luau_host.cpp`, inside `registerChiropteraLib`, the function ends with the `string` sub-table followed by `lua_pop(L, 1);`. Insert the alias immediately before that pop.

```bash
cd ~/git/chiroptera-shell && python3 - <<'EOF'
from pathlib import Path
p = Path("src/scripting/luau_host.cpp"); s = p.read_text()
old = '''    lua_setfield(L, -2, "string");
    lua_pop(L, 1);
  }'''
new = '''    lua_setfield(L, -2, "string");
    // noctalia-compat: plugins written for Noctalia call `noctalia.*`; bind the
    // same table under that name so they keep working unchanged.
    lua_pushvalue(L, -1);
    lua_setglobal(L, "noctalia"); // noctalia-compat
    lua_pop(L, 1);
  }'''
assert s.count(old) == 1, s.count(old)
p.write_text(s.replace(old, new))
print("alias added")
EOF
grep -n 'noctalia' src/scripting/luau_host.cpp
```

Expected: `alias added`; the grep shows exactly the three alias lines (two comments and the `lua_setglobal`), every one carrying `noctalia-compat`.

- [ ] **Step 4: Run the test to verify it passes, then the whole suite and the check**

```bash
cd ~/git/chiroptera-shell
meson compile -C build 2>&1 | tail -1
meson test -C build plugin_api_alias --print-errorlogs 2>&1 | grep -E 'Fail:|Ok:'
meson test -C build 2>&1 | grep -E 'Fail:|Ok:'
chiroptera/check-rename.sh
```

Expected: `Ok: 1`, `Fail: 0` for the single test; the full suite `Fail: 0`; `check-rename: ok`.

- [ ] **Step 5: Prove an unmodified official plugin passes the offline linter**

```bash
cd ~/git/chiroptera-shell
rm -rf build/official-plugins && git clone -q --depth 1 https://github.com/noctalia-dev/official-plugins build/official-plugins
grep -c 'noctalia\.' build/official-plugins/example/*.luau | head -3
./build/chiroptera plugins lint build/official-plugins/example; echo "lint-exit=$?"
```

Expected: the example plugin's scripts contain `noctalia.` calls (counts above 0), and the linter exits `0`. A non-zero exit whose messages mention an unknown global `noctalia` means the linter has its own global list that also needs the alias; add it in `src/scripting/plugin_lint.cpp` with a `noctalia-compat` marker, rebuild, re-lint, and report the change.

- [ ] **Step 6: Commit, tag, push**

```bash
cd ~/git/chiroptera-shell
git add tests/plugin_api_alias_test.cpp meson.build src/scripting/luau_host.cpp
git commit -m "Alias the Luau API table as noctalia for plugin compatibility

registerChiropteraLib binds the global noctalia to the chiroptera table.
Unit test plugin_api_alias asserts both globals are the same table."
git tag -a v5.0.1-chiroptera1 -m "Chiroptera Shell 5.0.1-chiroptera1: rename of Noctalia $(cut -d' ' -f2 .upstream-sync | cut -c1-7) with plugin API alias"
git push origin main --tags
git describe --tags
git status -sb | head -1
```

Expected: `v5.0.1-chiroptera1` and `## main...origin/main`.

---

### Task 5: PKGBUILD in ChiropteraOS, build and install

**Files:**
- Create: `~/git/ChiropteraOS/pkgs/chiroptera-shell/PKGBUILD`
- Remove: `~/git/ChiropteraOS/pkgs/chiroptera-cli/` and the old `pkgs/chiroptera-shell/` if present from the superseded plan (they are not; the old plan stopped before Task 7)

**Interfaces:**
- Consumes: tag `v5.0.1-chiroptera1`.
- Produces: `chiroptera-shell-5.0.1.chiroptera1-1-x86_64.pkg.tar.zst` installed on the laptop next to `noctalia-git`, providing `/usr/bin/chiroptera`, `/usr/share/chiroptera/assets/`, the desktop entry, the icon, and fish/bash/zsh completions. Env override `CHIROPTERA_SHELL_REPO` for local builds.

- [ ] **Step 1: Write the PKGBUILD**

```bash
mkdir -p ~/git/ChiropteraOS/pkgs/chiroptera-shell
cat > ~/git/ChiropteraOS/pkgs/chiroptera-shell/PKGBUILD <<'EOF'
# Maintainer: George (ChiropteraOS)
# Derived from the noctalia-git AUR package by the Noctalia team.

pkgname=chiroptera-shell
_srcname=chiroptera-shell
pkgver=5.0.1.chiroptera1
_tag=v5.0.1-chiroptera1
pkgrel=1
pkgdesc='Chiroptera Shell: the ChiropteraOS Wayland desktop shell (rebrand of Noctalia)'
arch=('x86_64' 'aarch64')
url='https://github.com/george-leonard314/chiroptera-shell'
license=('MIT')
options=('!debug')
depends=(
  'cairo' 'curl' 'fontconfig' 'freetype2' 'gcc-libs' 'git' 'glib2' 'glibc' 'jemalloc'
  'libglvnd' 'libical' 'libjxl' 'libpipewire' 'libqalculate' 'librsvg' 'libsecret'
  'libsndfile' 'libsodium' 'libwebp' 'libwireplumber' 'libxkbcommon' 'libxml2' 'md4c'
  'pam' 'polkit' 'pango' 'sdbus-cpp' 'tomlplusplus' 'wayland'
)
makedepends=('meson' 'ninja' 'nlohmann-json' 'pkgconf' 'stb' 'wayland-protocols')
optdepends=('noctalia-greeter: greetd login screen themed by the shell'
            'upower: battery integration'
            'ddcutil: external monitor brightness')
provides=('chiroptera-shell')
# Override with a local clone for development builds, e.g. file:///home/g/git/chiroptera-shell
_repo="${CHIROPTERA_SHELL_REPO:-$url.git}"
source=("${_srcname}::git+${_repo}#tag=${_tag}")
sha256sums=('SKIP')

build() {
  CXXFLAGS+=" -Wno-unused-result"
  arch-meson "${_srcname}" build-release \
    -Db_ndebug=true \
    -Dtests=disabled
  meson compile -C build-release
}

package() {
  meson install -C build-release --destdir "${pkgdir}"

  # Completions are generated by the built binary (a packaging step by upstream design).
  local bin="${srcdir}/build-release/chiroptera"
  install -dm755 "${pkgdir}/usr/share/fish/vendor_completions.d" \
                 "${pkgdir}/usr/share/bash-completion/completions" \
                 "${pkgdir}/usr/share/zsh/site-functions"
  "${bin}" completions fish > "${pkgdir}/usr/share/fish/vendor_completions.d/chiroptera.fish"
  "${bin}" completions bash > "${pkgdir}/usr/share/bash-completion/completions/chiroptera"
  "${bin}" completions zsh  > "${pkgdir}/usr/share/zsh/site-functions/_chiroptera"

  install -Dm644 "${_srcname}/LICENSE" "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
  install -Dm644 "${_srcname}/README.md" "${pkgdir}/usr/share/doc/${pkgname}/README.md"
}
EOF
```

- [ ] **Step 2: Build and inspect the package**

```bash
cd ~/git/ChiropteraOS/pkgs/chiroptera-shell
makepkg -sf --noconfirm 2>&1 | tail -3
pacman -Qlp chiroptera-shell-5.0.1.chiroptera1-1-x86_64.pkg.tar.zst | grep -E '/usr/bin/chiroptera$|share/chiroptera/assets/chiroptera.svg|applications/dev.chiroptera.Chiroptera.desktop|icons/hicolor/scalable/apps/chiroptera.svg|vendor_completions.d/chiroptera.fish|licenses/chiroptera-shell/LICENSE'
pacman -Qlp chiroptera-shell-5.0.1.chiroptera1-1-x86_64.pkg.tar.zst | grep -ci noctalia
```

Expected: `Finished making: chiroptera-shell 5.0.1.chiroptera1-1`; six matching lines; count `0`. The build takes several minutes. If the clone fails on authentication, set `CHIROPTERA_SHELL_REPO=file:///home/g/git/chiroptera-shell` and retry. If `completions` exits non-zero, print its stderr in the report and report BLOCKED; do not ship the package without completions silently.

- [ ] **Step 3: Install and smoke test the binary**

Installing needs sudo, which has no terminal in this environment. Try
non-interactively; if sudo refuses, stop and hand the exact command to the
user through the controller (report `DONE_WITH_CONCERNS` with the command),
then continue once the user confirms it ran.

```bash
cd ~/git/ChiropteraOS/pkgs/chiroptera-shell && sudo -n pacman -U --noconfirm chiroptera-shell-5.0.1.chiroptera1-1-x86_64.pkg.tar.zst 2>&1 | tail -2
chiroptera --version
pacman -Q noctalia-git chiroptera-shell
ls /usr/share/chiroptera/assets | head -5
```

Expected: install succeeds with no file conflicts; a version line with `5.0.1`; both packages listed; the assets listing shows `chiroptera.svg` and `fonts`.

- [ ] **Step 4: Commit the packaging**

```bash
cd ~/git/ChiropteraOS && git add pkgs/chiroptera-shell/PKGBUILD && git commit -m "Add chiroptera-shell PKGBUILD (Noctalia-based, Meson build from git tag)"
```

---

### Task 6: Switch the laptop to Chiroptera Shell and document the sync ritual

**Files:**
- Modify (laptop, outside git): `~/.local/state/chiroptera/` (new copy), `~/.config/chiroptera/`, `~/.config/caelestia/hypr-user.conf` (spike block), `~/.local/bin/chiroptera-super-tap`, `~/.local/share/caelestia/hypr/hyprland/execs.conf` (with `.pre-chiroptera` backup)
- Rewrite: `~/git/ChiropteraOS/docs/upstream-sync.md`

**Interfaces:**
- Consumes: installed `chiroptera` from Task 5.
- Produces: laptop session shell is `chiroptera`, autostarted by Hyprland, with the spike binds and both helper scripts pointing at it; an official Noctalia plugin verified working through the alias at runtime.

- [ ] **Step 1: Migrate Noctalia state and re-point the spike binds and scripts**

```bash
if [ ! -e ~/.local/state/chiroptera ]; then cp -a ~/.local/state/noctalia ~/.local/state/chiroptera; fi
mkdir -p ~/.config/chiroptera
if [ -e ~/.config/noctalia/config.toml ] && [ ! -e ~/.config/chiroptera/config.toml ]; then cp -a ~/.config/noctalia/config.toml ~/.config/chiroptera/config.toml; fi
python3 - <<'EOF'
import re
from pathlib import Path
p = Path.home() / ".config/caelestia/hypr-user.conf"
s = p.read_text()
start, end = "# >>> noctalia spike", "# <<< noctalia spike <<<"
a, b = s.index(start), s.index(end) + len(end)
block = s[a:b].replace("noctalia msg", "chiroptera msg").replace("dev.noctalia.Noctalia", "dev.chiroptera.Chiroptera").replace("noctalia-(", "chiroptera-(")
block = block.replace("# >>> noctalia spike (temporary, remove this block to end the spike) >>>", "# >>> chiroptera shell binds (temporary until chiroptera-dots lands) >>>").replace(end, "# <<< chiroptera shell binds <<<")
p.write_text(s[:a] + block + s[b:])
print("spike block re-pointed")
EOF
sed -i 's/noctalia msg/chiroptera msg/' ~/.local/bin/chiroptera-super-tap
grep -c 'chiroptera msg' ~/.config/caelestia/hypr-user.conf ~/.local/bin/chiroptera-super-tap
grep -c 'noctalia' ~/.config/caelestia/hypr-user.conf
```

Expected: `spike block re-pointed`; counts of at least `9` and `1`; the remaining `noctalia` count in the overrides file is `0`.

- [ ] **Step 2: Point Hyprland autostart at Chiroptera**

```bash
f=~/.local/share/caelestia/hypr/hyprland/execs.conf
cp -n "$f" "$f.pre-chiroptera"
python3 - <<'EOF'
from pathlib import Path
p = Path.home() / ".local/share/caelestia/hypr/hyprland/execs.conf"
lines = p.read_text().splitlines()
out = []
for l in lines:
    if l.strip() == "exec-once = caelestia resizer -d":
        continue
    if l.strip() == "exec-once = caelestia shell -d":
        out.append("exec-once = chiroptera --daemon")
        continue
    out.append(l)
p.write_text("\n".join(out) + "\n")
print("execs updated")
EOF
grep -n 'chiroptera\|caelestia' ~/.local/share/caelestia/hypr/hyprland/execs.conf
```

Expected: `execs updated`; exactly one line, `exec-once = chiroptera --daemon`.

- [ ] **Step 3: Swap the running shell**

```bash
hyprctl reload >/dev/null
pkill -x noctalia; sleep 1
python3 - <<'EOF'
import subprocess, time
t0 = time.monotonic()
subprocess.run(["chiroptera", "--daemon"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(600):
    if "chiroptera-bar" in subprocess.run(["hyprctl", "layers"], capture_output=True, text=True).stdout:
        print(f"time to first bar layer: {time.monotonic() - t0:.2f} s"); break
    time.sleep(0.05)
else:
    print("no bar layer within 30 s")
EOF
hyprctl layers | grep -o 'namespace: chiroptera-[a-z-]*' | sort -u | tr '\n' ' '; echo
pgrep -ax chiroptera | head -1; pgrep -x noctalia || echo "noctalia: not running"
chiroptera msg --help | head -2
```

Expected: a start time under one second; namespaces `chiroptera-bar-default`, `chiroptera-panel`, `chiroptera-wallpaper`; one `chiroptera` process; `noctalia: not running`; the IPC help prints.

- [ ] **Step 4: Verify the plugin alias at runtime with an official plugin**

```bash
chiroptera msg plugins enable noctalia/example; sleep 3
chiroptera msg plugins list | grep -i example
chiroptera msg plugin noctalia/example:hello focused set "alias ok"; echo "set-exit=$?"
sleep 1; grep -iE 'luau|plugin' ~/.cache/chiroptera/chiroptera.log | grep -iE 'error|failed' | tail -5; echo "plugin-errors=$?"
chiroptera msg plugins disable noctalia/example
```

Expected: the plugin lists as enabled; `set-exit=0`; `plugin-errors=1` (no error lines from the plugin runtime). The example plugin is written against `noctalia.*`, so this proves the alias in the real shell. If the log path differs, find it with `ls ~/.cache/chiroptera/`.

- [ ] **Step 5: Confirm the user-facing binds on the laptop**

Ask the user to: tap Super (launcher opens), press Super+comma (settings opens), Super+O (Obsidian in a special workspace). Record their answers in the report; these cannot be automated.

- [ ] **Step 6: Rewrite the upstream sync ritual**

```bash
cat > ~/git/ChiropteraOS/docs/upstream-sync.md <<'EOF'
# Upstream sync ritual

`chiroptera-shell` is a full-history copy of Noctalia with the rename transform
(`chiroptera/rename.sh`) and the plugin-API alias committed on top. Syncing
means: apply the same transform to upstream's new tree on a branch, then merge
that. Because the transform is deterministic, the rename itself never
conflicts; only upstream edits adjacent to renamed text do, and those are
mechanical. The alias commit merges like any other source change.

Nothing here runs automatically. Do it when an upstream change is worth
having. Check upstream's release notes for plugin API level bumps: the shell
must keep `version:` in `meson.build` equal to upstream's so plugins gate
correctly.

```sh
cd ~/git/chiroptera-shell
git fetch upstream
git log --oneline "$(cut -d' ' -f2 .upstream-sync)..upstream/main"   # what changed
git checkout -b sync upstream/main
bash <(git show main:chiroptera/rename.sh)
git add -A && git commit -m "Apply Chiroptera transform to upstream $(git rev-parse --short upstream/main)"
git checkout main
git merge sync            # resolve conflicts: keep both the rename and upstream's edit
echo "upstream $(git rev-parse upstream/main)" > .upstream-sync
chiroptera/check-rename.sh
meson setup build --reconfigure --buildtype=debug -Dtests=enabled && meson compile -C build && meson test -C build
git add -A && git commit -m "Merge upstream $(git rev-parse --short upstream/main)"
git branch -D sync
```

## After a sync

Tag `v<upstream version>-chiroptera<N>` (N restarts at 1 when the upstream
version changes), bump `pkgver` and `_tag` in
`ChiropteraOS/pkgs/chiroptera-shell/PKGBUILD` (`pkgver` is the tag with `-`
replaced by `.`), push with `--tags`, rebuild, install, and run the laptop
checks from the step 1 plan, Task 6.
EOF
cd ~/git/ChiropteraOS && git add docs/upstream-sync.md && git commit -m "Document the upstream sync ritual for the Noctalia-based shell" && git log --oneline -3
```

Expected: three commits listed, newest first: the sync doc, the PKGBUILD, the step 1 plan.

- [ ] **Step 7: Final laptop state summary**

```bash
pacman -Q noctalia-git chiroptera-shell caelestia-shell
chiroptera --version
ls ~/.local/state/chiroptera | tr '\n' ' '; echo
grep -c 'chiroptera' ~/.local/share/caelestia/hypr/hyprland/execs.conf
```

Report this output verbatim. Rollback if the desktop is broken: `mv ~/.local/share/caelestia/hypr/hyprland/execs.conf.pre-chiroptera ~/.local/share/caelestia/hypr/hyprland/execs.conf; hyprctl reload; pkill -x chiroptera; noctalia --daemon`.
