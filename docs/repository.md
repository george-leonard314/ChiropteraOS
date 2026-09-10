# The ChiropteraOS package repository

`pacman -S chiroptera-meta` should succeed on a machine that has added one
repository. This document covers what that repository carries, how CI builds
it, and the two things still owed before it can be published.

## What it carries

Four packages — the three ChiropteraOS ones plus `app2unit`, which is the only
dependency of `chiroptera-meta` that exists in neither `core` nor `extra`. An
AUR-only dependency cannot be resolved by `pacman`, so the repository has to
carry it.

| Package | Arch | Source |
|---|---|---|
| `app2unit` | any | Public GitHub tarball, vendored from the AUR |
| `chiroptera-shell` | x86_64 | Private repository, tag `v5.0.1-chiroptera1` |
| `chiroptera-dots` | any | Private repository, tag `v0.1.0` |
| `chiroptera-meta` | any | This repository |

x86_64 only. The `aarch64` line in the shell PKGBUILD is inherited from
upstream Noctalia and is not built or tested.

## Using it

Append `ci/chiroptera.conf` to `/etc/pacman.conf`, below `[core]` and
`[extra]`, and set `Server` to the published URL. Packages are unsigned today,
so the snippet ships `SigLevel = Never`.

## How CI works

`.github/workflows/packages.yml` runs on pushes to `main` that touch `pkgs/`,
`ci/` or the workflow itself, on pull requests, and on manual dispatch.

| Job | What it does |
|---|---|
| `lint` | Every PKGBUILD parses and yields metadata. Runs on pull requests too. |
| `build` | Builds what is missing, prunes, writes the database, uploads `repo/`. |
| `publish` | Inert. See "Publishing" below. |

Both jobs run in `archlinux:base-devel` as an unprivileged `builder` user,
because `makepkg` refuses to run as root — including for `--printsrcinfo`.

The build is incremental: a package is built only when its exact
`pkgver-pkgrel` is not already in the restored `repo/`, which comes from the
Actions cache. Losing that cache costs a full rebuild, never correctness.

Only `chiroptera-shell` and `app2unit` have their dependencies synced — the
former compiles, the latter renders man pages with `scdoc`. `chiroptera-dots`
and `chiroptera-meta` build with `--nodeps`: they have no `build()` at all, so
installing their runtime dependencies would pull hundreds of megabytes into the
builder and prove nothing. The smoke test proves what matters instead.

### Verification

Three layers, cheapest first:

1. **Lint** — `bash -n` plus `makepkg --printsrcinfo` on every PKGBUILD.
2. **Build** — a package that fails to build fails the run.
3. **Smoke test** — a throwaway pacman root adds the built repository over
   `file://` and resolves `chiroptera-meta`. Resolution requires every
   dependency to exist somewhere pacman can reach, which is precisely the
   check that `app2unit` being AUR-only used to fail.

## Running the whole pipeline locally

Do not push and wait. `ci/run-in-container.sh` runs lint, build and smoke test
in a throwaway Arch container exactly as CI does:

```sh
SOURCES=$HOME/git ./ci/run-in-container.sh
```

`SOURCES` points at a directory holding local clones of the private source
repositories, which are then cloned over `file://` — no deploy token needed.
Output lands in `./repo`. `PACKAGES` limits which packages are built, so a
change to the meta package can be checked without recompiling the shell:

```sh
PACKAGES="app2unit chiroptera-meta" SOURCES=$HOME/git ./ci/run-in-container.sh
```

## The deploy token

`chiroptera-shell` and `chiroptera-dots` are private. Git inside `makepkg` does
not use `gh`'s credential helper, so an unauthenticated clone fails with
`could not read Username for 'https://github.com'`.

CI resolves this by rewriting the clone URL for the build user:

```sh
git config --global \
  url."https://x-access-token:$TOKEN@github.com/".insteadOf "https://github.com/"
```

`makepkg` strips the `git+` prefix and runs a plain `git clone https://…`, so
the rewrite applies and the clone authenticates.

**Creating or rotating it.** The token is a fine-grained personal access token
with *Contents: Read* on `chiroptera-shell` and `chiroptera-dots` only, stored
as the repository secret `SOURCE_REPO_TOKEN`. Fine-grained tokens expire after
at most a year, so this is a recurring chore: when the build starts failing on
`could not read Username`, the token has expired. Issue a new one with the same
two-repository scope and replace the secret.

## Gotchas worth knowing

**A moved tag will not trigger a rebuild.** `docs/STATUS.md` records that
moving a git tag does not invalidate `makepkg`'s cached checkout. CI clones
fresh every run, so that specific trap cannot occur there — but the skip logic
keys on `pkgver-pkgrel` and cannot see that a tag now points somewhere else.
After moving a tag, bump `pkgrel` (correct packaging practice anyway) or
dispatch the workflow with `force_rebuild`.

**The database files must not be symlinks.** `repo-add` writes `chiroptera.db`
and `chiroptera.files` as symlinks to their `.tar.zst` counterparts. Static
hosts do not serve symlinks, so publishing them unresolved yields a repository
that works perfectly over `file://` and returns 404 over HTTP. `build-repo.sh`
replaces them with real copies and `smoke-test.sh` asserts they are not links.

**`makepkg --packagelist` lists packages it will not build.** It advertises a
`-debug` package whenever `debug` is in makepkg's `OPTIONS`, including for
`arch=any` packages that contain no binaries and so never produce one. Counting
that phantom as a missing output defeats the skip logic and rebuilds
everything, every run.

## Still owed

**Publishing.** Where the repository is served is undecided. The constraint
forcing the question: GitHub Pages publishes from a private repository only on
a paid plan, and `ChiropteraOS`, `chiroptera-shell` and `chiroptera-dots` are
all private. The candidates are a dedicated public repository served by Pages,
GitHub Releases on such a repository, or making `ChiropteraOS` public. Note
that whichever is chosen, the built packages are world-downloadable — clients
have to fetch them anonymously — even though the source history stays private.

The `publish` job is gated on a `PUBLISH_TARGET` repository variable and fails
loudly if enabled before it is implemented. Wiring it up is one job, not a
rework: take the `chiroptera-repo` artifact and put it where it belongs.

**Signing.** Packages are unsigned. `build-repo.sh` signs packages and the
database when the `PACKAGE_SIGNING_KEY` secret exists and no-ops otherwise, so
enabling it means creating a packaging key, adding the secret, and switching
clients to `SigLevel = Required DatabaseOptional` — not editing the workflow.
