# Where the build stands

Updated 2026-09-11.

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

**Step 5, build half — chiroptera-hwd.** `hwd/chiroptera-hwd` detects the CPU
level and applies the CachyOS repositories, pacman, kernel, microcode and boot
entry, with graphics delegated to `chwd`. Packaged as `chiroptera-hwd`; a bats
suite and a real apply in a container run in CI. See `docs/hwd.md`.

## Remaining

| Step | Work |
|---|---|
| 3 | Theme, logo and bar composition — largely done during step 2 |
| 4 | Publishing: choose a host and wire up the `publish` job (build CI is done) |
| 5 | Applied to the laptop; after-benchmarks wait on the flaky-TSC fix (`tsc=reliable`) |
| 6 | Done bar CI: the ISO builds and installs end to end in QEMU (`iso/`, `calamares/`, `boot/`; see `docs/iso.md`). Hardware test and an ISO workflow remain |
| 7 | The AI sidebar plugin |
| 8 | Upstream sync tooling and the greeter rebrand |

Step 4's build half is done: `.github/workflows/packages.yml` builds all four
packages in an Arch container, proves the result installable, and uploads a
ready-to-serve repository. What remains of it is choosing where to publish —
see `docs/repository.md`. Step 5 can proceed in parallel.

## Known blockers

- **Moving a git tag does not invalidate `makepkg`'s cached checkout.** After any
  tag move, clear the package directory's cache or the rebuild ships stale
  content. CI clones fresh each run and so cannot hit this, but its skip logic
  keys on `pkgver-pkgrel`: after moving a tag, bump `pkgrel` or dispatch the
  workflow with `force_rebuild`.
- **Where to publish the repository is undecided.** All three repositories are
  public now, so GitHub Pages is free. See `docs/repository.md`.

### Resolved in step 4

- ~~Private repositories cannot be cloned by `makepkg`.~~ CI rewrites the clone
  URL for the build user with a fine-grained deploy token, so `makepkg`'s plain
  `git clone` authenticates. Local builds still use the `file://` overrides.
  The token expires within a year and must be rotated.
- ~~Undeclared dependencies in `chiroptera-meta`.~~ `libnotify` is declared.
  `firefox` and `code` were deliberately dropped rather than declared: there is
  no profile or configuration invested in either. The keybinds referencing them
  in `chiroptera-dots` still point at applications the meta package no longer
  pulls in.
- ~~`app2unit` is AUR-only.~~ Vendored into `pkgs/app2unit`.
- ~~`chiroptera-meta` did not parse.~~ Commit `9e12a3b` had left the
  `optdepends` array unterminated. Lint now catches this class of error.

## Decisions still owed by the author

Step 6 needs seven Calamares choices: branding, locale defaults, partitioning and
encryption, user setup, the package list, post-install hardware detection, and
what the finish screen does.
