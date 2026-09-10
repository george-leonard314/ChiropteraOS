# Step 4 — Build CI and the ChiropteraOS pacman repository

Design, 2026-09-10. Approved approach: a single Arch-container job that builds
incrementally and emits a ready-to-serve repository directory as an artifact.

## Goal

`pacman -S chiroptera-meta` succeeds on a machine that has only added the
ChiropteraOS repository. Everything else in this step exists to make that one
command true and to keep it true without hand-building on the author's laptop.

## What the repository must carry

Four packages. Of `chiroptera-meta`'s dependencies, exactly three are absent
from the official Arch repositories:

| Package | Arch | Source |
|---|---|---|
| `app2unit` | any | Vendored from the AUR into `pkgs/app2unit` |
| `chiroptera-shell` | x86_64 | Private `git+https`, tag `v5.0.1-chiroptera1` |
| `chiroptera-dots` | any | Private `git+https`, tag `v0.1.0` |
| `chiroptera-meta` | any | This repository |

x86_64 only. The `aarch64` line in the shell PKGBUILD is inherited from
upstream Noctalia and is not a target the author builds or tests.

## Architecture

```
push to main (pkgs/**, ci/**, workflow)
        |
     [lint]      bash -n + makepkg --printsrcinfo over every PKGBUILD
        |
     [build]     archlinux:base-devel container, unprivileged builder user
        |          restore repo/ from Actions cache
        |          build only packages whose pkgver-pkgrel is not present
        |          prune to the 2 newest versions per package
        |          rebuild the database from the retained set
        |
     [smoke]     fresh container, repo added over file://, resolve chiroptera-meta
        |
     [publish]   inert until a host is chosen
```

Build logic lives in `ci/*.sh`, not inline YAML, so the whole pipeline can be
run locally in a container instead of push-and-pray.

## Files

| Path | Purpose |
|---|---|
| `ci/lint-pkgbuilds.sh` | Syntax and `.SRCINFO` check over every PKGBUILD |
| `ci/build-repo.sh` | Build, prune, `repo-add` |
| `ci/smoke-test.sh` | Prove the built repository is installable |
| `ci/chiroptera.conf` | The `[chiroptera]` snippet users add to `pacman.conf` |
| `.github/workflows/packages.yml` | Wires the four jobs together |
| `pkgs/app2unit/PKGBUILD` | Vendored AUR recipe |
| `docs/repository.md` | Consuming the repo; rotating the token |

## Build details

**Unprivileged user.** `makepkg` refuses to run as root. The container creates
`builder` with passwordless sudo restricted to `pacman`.

**Source access.** A fine-grained PAT with *Contents: Read* on
`chiroptera-shell` and `chiroptera-dots`, stored as the secret
`SOURCE_REPO_TOKEN`. CI configures, as the builder user:

```
git config --global url."https://x-access-token:$TOKEN@github.com/".insteadOf "https://github.com/"
```

`makepkg` strips the `git+` prefix and runs a plain `git clone https://…`, so
the rewrite applies and the clone authenticates. This is the resolution of the
"private repositories cannot be cloned by makepkg" blocker. The token is a
GitHub Actions secret and is therefore masked in logs; the generated
`.gitconfig` exists only inside the ephemeral container.

*Cost of this choice:* fine-grained PATs expire after at most a year. Renewal
is a recurring chore and is documented in `docs/repository.md`.

**Per-package build commands.** Only the shell compiles:

- `chiroptera-shell` — `makepkg -s`, needs its makedepends.
- `app2unit`, `chiroptera-dots`, `chiroptera-meta` — `makepkg --nodeps`. These
  are `arch=any` with no `build()`, so installing their runtime dependencies
  into the container would cost hundreds of megabytes and prove nothing. The
  smoke test checks dependency resolution instead, which is the check that
  actually matters.

Each built package is installed into the container before the next is built.

**Skip logic.** For each package, `makepkg --printsrcinfo` yields
`pkgname`, `pkgver`, `pkgrel`, `arch`. If the corresponding
`pkgname-pkgver-pkgrel-arch.pkg.tar.zst` is already in the restored `repo/`,
the build is skipped.

**Interaction with the moved-tag trap.** Each CI run clones fresh, so the
`makepkg` source-cache staleness recorded in `docs/STATUS.md` cannot occur in
CI. The trap reappears in a different form: if a tag is moved without bumping
`pkgrel`, the skip logic will decline to rebuild. The remedy is to bump
`pkgrel` — which is correct packaging practice anyway — or to dispatch the
workflow with `force_rebuild`.

**Retention.** Keep the two newest `pkgver-pkgrel` versions per package name, ordered with
`vercmp`; delete the rest, then rebuild the database over the retained set with
`repo-add --new`. Rebuilding rather than incrementally amending avoids database
drift and keeps growth bounded no matter where the repo is eventually hosted.

**Static-host symlinks.** `repo-add` writes `chiroptera.db` and
`chiroptera.files` as symlinks to their `.tar.zst` counterparts. Static hosts
do not serve symlinks, so the build replaces both with real copies. Missing
this produces a repository that works locally and 404s once published.

**Signing: structured, off.** The sign step runs only when the secret
`PACKAGE_SIGNING_KEY` is present; absent, it is a no-op and `repo-add` runs
unsigned. Enabling signing later means adding a secret, not reworking the
workflow. `ci/chiroptera.conf` ships `SigLevel = Never` with the signed variant
present but commented out.

**Cache.** `repo/` is kept in the Actions cache. Eviction costs a full rebuild,
never correctness.

## Verification

Three layers, cheapest first:

1. **Lint** — `bash -n` and `makepkg --printsrcinfo` on every PKGBUILD, on
   every push and pull request. This is the check that would have caught the
   unterminated `optdepends` array described below.
2. **Build** — a package that fails to build fails the run.
3. **Smoke test** — a fresh container adds the built repository as a `file://`
   server alongside the official repositories, runs `pacman -Sy`, and resolves
   `pacman -Sp chiroptera-meta`. Resolution requires every dependency to exist,
   so this is the check that would have caught `app2unit` being AUR-only. It
   resolves rather than installs: the failure mode being guarded against is a
   missing or unsatisfiable dependency, not a broken file list.

## Fixes folded in

These are prerequisites — CI cannot go green without the first, and the
repository is not usable without the third.

1. **`chiroptera-meta` does not parse.** Commit `9e12a3b` removed the closing
   parenthesis of the `optdepends` array; `bash -n` reports a syntax error at
   the `provides=` line. Restore the parenthesis.
2. **Undeclared dependencies.** Add `libnotify` to `depends`. `firefox` and
   `code` are deliberately *not* declared: the author has no profile or
   configuration invested in either, so they are not part of the package set. A
   comment in the PKGBUILD records this so it is not re-raised as an omission.
   Consequence, accepted and out of scope here: the keybinds referencing them
   in `chiroptera-dots` will point at absent applications until that separate
   repository is edited.
3. **`app2unit` vendored** into `pkgs/app2unit`, resolving the AUR-only
   blocker.

## Client configuration

```ini
[chiroptera]
SigLevel = Never
Server = <set once hosting is chosen>
```

## Deferred

- **Hosting.** Where the artifact is published — a dedicated public repo served
  by Pages, GitHub Releases, or Pages from ChiropteraOS itself — is unresolved.
  The constraint that forces the question: GitHub Pages publishes from a
  private repository only on a paid plan, and all three repositories are
  private. The `publish` job is left inert; wiring it is one step, not a
  rework.
- **Signing key** creation and distribution.

## Out of scope

The CachyOS kernel and repositories (step 5), and any change to
`chiroptera-dots`.
