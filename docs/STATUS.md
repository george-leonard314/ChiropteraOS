# Where the build stands

Updated 2026-09-09.

## Done

**Step 1 — Chiroptera Shell.** A full-history copy of Noctalia v5 renamed to
Chiroptera, tagged `v5.0.1-chiroptera1`, packaged, and running as the daily
session shell. The Luau plugin API is exposed as `chiroptera` with `noctalia`
aliased to the same table, so existing third-party plugins keep working; official
plugin ids keep their upstream `noctalia/` author namespace. All 117 upstream
tests pass after the rename.

**Step 2 — chiroptera-dots.** The author's configuration captured into its own
repository, rewritten from caelestia's global shortcuts to Chiroptera IPC,
packaged as `chiroptera-dots` and `chiroptera-meta`, and installed. The laptop's
`~/.config` links into the repo. Caelestia's packages and directories were
removed afterwards with nothing left depending on them.

## Remaining

| Step | Work |
|---|---|
| 3 | Theme, logo and bar composition — largely done during step 2 |
| 4 | Build CI and the pacman repository on GitHub Pages |
| 5 | `chiroptera-hwd` hardware detection, plus the CachyOS kernel and repos |
| 6 | The ISO: archiso profile, live desktop, Calamares |
| 7 | The AI sidebar plugin |
| 8 | Upstream sync tooling and the greeter rebrand |

Step 4 comes next: the installer needs somewhere to pull packages from.

## Known blockers

- **Private repositories cannot be cloned by `makepkg`.** Git inside `makepkg`
  does not use the `gh` credential helper, so local builds pass
  `CHIROPTERA_DOTS_REPO=file:///home/g/git/chiroptera-dots` and the shell
  equivalent. Step 4 must resolve this with a deploy token or by making the
  source repositories public.
- **Undeclared dependencies** in `chiroptera-meta`: `firefox` and `code` are
  bound to keys through `app2unit`; `libnotify` backs a test keybind.
- **`app2unit` is AUR-only** until the ChiropteraOS repository carries it.
- **Moving a git tag does not invalidate `makepkg`'s cached checkout.** After any
  tag move, clear the package directory's cache or the rebuild ships stale
  content.

## Decisions still owed by the author

Step 6 needs seven Calamares choices: branding, locale defaults, partitioning and
encryption, user setup, the package list, post-install hardware detection, and
what the finish screen does.
