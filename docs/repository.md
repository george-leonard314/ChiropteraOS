# The ChiropteraOS package repository

`pacman -S chiroptera-meta` should succeed on a machine that has added one
repository. This document covers what that repository carries, how CI builds
it, and the two things still owed before it can be published.

## What it carries

The ChiropteraOS packages, plus the AUR packages they and the live image
depend on. An AUR-only dependency cannot be resolved by `pacman`, so the
repository has to carry it.

| Package | Arch | Source |
|---|---|---|
| `app2unit` | any | Public GitHub tarball, vendored from the AUR |
| `pacseek` | any | Public GitHub tarball, vendored from the AUR |
| `evdi-dkms` | x86_64 | Public GitHub tarball, vendored from the AUR |
| `displaylink` | x86_64 | Synaptics download, vendored from the AUR — **proprietary** |
| `chiroptera-shell` | x86_64 | Private repository, tag `v5.0.1-chiroptera4` |
| `chiroptera-dots` | any | Private repository, tag `v0.1.0` |
| `chiroptera-meta` | any | This repository |
| `chiroptera-hwd` | any | This repository |
| `chiroptera-boot` | any | This repository |
| `kmg` | x86_64 | Downloaded from the latest release of `george-leonard314/kmg`, whose own CI builds it |

`evdi-dkms` and `displaylink` are what make DisplayLink docks work; the image
installs both. Two things about them are unlike the rest:

- `displaylink` is **not free software**. The DisplayLinkManager binary is
  Synaptics', under the EULA installed to
  `/usr/share/licenses/displaylink/DISPLAYLINK-EULA`. Publishing the repository
  and the image redistributes it. That is a deliberate choice, taken so docks
  work out of the box; revisit it before any wider release.
- Its source zip is fetched from `synaptics.com` at build time and Synaptics
  retires old versions from that path, so this package will eventually fail to
  build with a 404. The fix is to bump `pkgver`, `_releasedate`, `_pkgfullver`
  and the first `sha256sums` entry to the current release. `displaylink`
  requires `evdi<1.16`, so check that constraint when bumping either.

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

Only the packages that build something have their dependencies synced:
`chiroptera-shell`, `pacseek` and `evdi-dkms` compile, and `app2unit`
renders man pages with `scdoc`. `chiroptera-dots`
and `chiroptera-meta` build with `--nodeps`: they have no `build()` at all, so
installing their runtime dependencies would pull hundreds of megabytes into the
builder and prove nothing. The smoke test proves what matters instead.

`kmg` is not built here. The kmg repository keeps its PKGBUILD in
`kmg/packaging/arch`, and its CI attaches the package to every `v*-kmg*`
release; this build downloads the latest one and checks its sha256. A new KMG
release reaches the repository on the next run, so start one by hand after
releasing: `gh workflow run packages.yml`.

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

`SOURCES` points at a directory holding local clones of the source
repositories, which are then cloned over `file://`, so unpushed work can be
built.
Output lands in `./repo`. `PACKAGES` limits which packages are built, so a
change to the meta package can be checked without recompiling the shell:

```sh
PACKAGES="app2unit chiroptera-meta" SOURCES=$HOME/git ./ci/run-in-container.sh
```

## The deploy token (optional)

`chiroptera-shell` and `chiroptera-dots` are public (since 2026-09-11), so
`makepkg` clones them anonymously and CI needs no token. The build's
authentication step says so and moves on when `SOURCE_REPO_TOKEN` is unset.

The token path stays for a private source. Git inside `makepkg` does not use
`gh`'s credential helper, so an unauthenticated clone of a private repository
fails with `could not read Username for 'https://github.com'`. When the secret
exists, CI rewrites the clone URL for the build user:

```sh
git config --global \
  url."https://x-access-token:$TOKEN@github.com/".insteadOf "https://github.com/"
```

`makepkg` strips the `git+` prefix and runs a plain `git clone https://…`, so
the rewrite applies and the clone authenticates.

**If a source goes private again.** Create a fine-grained personal access token
with *Contents: Read* on the private repositories only, and store it as the
repository secret `SOURCE_REPO_TOKEN`. Fine-grained tokens expire after at most
a year: when the build starts failing on `could not read Username`, the token
has expired and needs replacing.

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

**Publishing.** Where the repository is served is still the author's choice,
but the constraint that blocked it is gone: `ChiropteraOS` is public (since
2026-09-11), so GitHub Pages can serve the built repository from it for free.
GitHub Releases on the same repository is the alternative. Either way the
packages are world-downloadable, since clients fetch them anonymously.

The `publish` job is gated on a `PUBLISH_TARGET` repository variable and fails
loudly if enabled before it is implemented. Wiring it up is one job, not a
rework: take the `chiroptera-repo` artifact and put it where it belongs.

**Signing.** Packages are unsigned. `build-repo.sh` signs packages and the
database when the `PACKAGE_SIGNING_KEY` secret exists and no-ops otherwise, so
enabling it means creating a packaging key, adding the secret, and switching
clients to `SigLevel = Required DatabaseOptional` — not editing the workflow.
