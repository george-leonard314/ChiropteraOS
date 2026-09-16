#!/usr/bin/env bash
# Build the ChiropteraOS pacman repository into $REPO_DIR.
#
# Incremental: a package is built only when its exact pkgver-pkgrel is not
# already present. Set FORCE_REBUILD=1 to rebuild regardless -- needed after a
# git tag is moved without a pkgrel bump, since the skip logic keys on version
# alone and cannot see that the tag now points somewhere else.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

REPO_NAME=${REPO_NAME:-chiroptera}
REPO_DIR=${REPO_DIR:-$repo_root/repo}
KEEP=${KEEP:-2}
FORCE_REBUILD=${FORCE_REBUILD:-0}

# Dependencies before dependents. Overridable so a local run can exercise the
# script without recompiling the shell.
read -r -a packages <<<"${PACKAGES:-app2unit pacseek evdi-dkms displaylink chiroptera-shell chiroptera-dots chiroptera-meta chiroptera-hwd chiroptera-boot chiroptera-calamares-config kmg}"

# Dependency handling, per package:
#
#   --syncdeps  chiroptera-shell and pacseek compile; app2unit renders man
#               pages with scdoc; evdi-dkms builds its library and pyevdi
#               bindings. All genuinely need their makedepends installed.
#
#   --nodeps    chiroptera-dots, chiroptera-meta, chiroptera-hwd,
#               chiroptera-boot and
#               chiroptera-calamares-config have no
#               build() at all. Their makedepends are still installed
#               (chiroptera-dots needs librsvg in package()).
#               Installing their runtime dependencies would pull hundreds of
#               megabytes into the builder and prove nothing about whether the
#               published repository resolves. smoke-test.sh proves that.
#
#               displaylink is --nodeps for a different reason: it does have a
#               prepare() step, but its depends are evdi<1.16 and libusb, and
#               evdi lives only in this repository, which is not in the
#               builder's pacman.conf -- --syncdeps would fail to resolve it.
#               Nothing in prepare() needs evdi. Its declared makedepends are
#               grep, gawk and wget; the makeself installer only calls awk,
#               which base-devel already provides.
declare -A extra_flags=(
    [app2unit]="--syncdeps"
    [pacseek]="--syncdeps"
    [evdi-dkms]="--syncdeps"
    [displaylink]="--nodeps"
    [chiroptera-shell]="--syncdeps"
    [chiroptera-dots]="--nodeps"
    [chiroptera-meta]="--nodeps"
    [chiroptera-hwd]="--nodeps"
    [chiroptera-boot]="--nodeps"
    [chiroptera-calamares-config]="--nodeps"
)

# Packages their own repositories build and attach to GitHub releases. They
# are downloaded from the latest release rather than built here; the PKGBUILD
# and its history stay in that repository.
declare -A released=(
    [kmg]="george-leonard314/kmg"
)

mkdir -p "$REPO_DIR"

# Newest-first, using pacman's own version ordering. Lists are a handful of
# entries, so an O(n^2) selection is cheaper than being clever.
sort_versions_desc() {
    local -a items=("$@") out=()
    local best i
    while ((${#items[@]})); do
        best=0
        for ((i = 1; i < ${#items[@]}; i++)); do
            if (($(vercmp "${items[i]}" "${items[best]}") > 0)); then
                best=$i
            fi
        done
        out+=("${items[best]}")
        unset 'items[best]'
        items=("${items[@]}")
    done
    ((${#out[@]})) && printf '%s\n' "${out[@]}"
}

# The newest file of each package among the given ones. repo-add keeps the
# last file it is handed for a name, and a glob puts chiroptera-dots-0.1.10
# before 0.1.9, so passing every retained file publishes the older one.
newest_packages() {
    local -A best_file=() best_ver=()
    local f base name ver
    for f in "$@"; do
        base=$(basename "$f")
        [[ $base =~ ^(.+)-([^-]+-[^-]+)-[^-]+\.pkg\.tar\.[a-z]+$ ]] || continue
        name=${BASH_REMATCH[1]}
        ver=${BASH_REMATCH[2]}
        if [[ -z ${best_ver[$name]:-} ]] || (($(vercmp "$ver" "${best_ver[$name]}") > 0)); then
            best_ver[$name]=$ver
            best_file[$name]=$f
        fi
    done
    ((${#best_file[@]})) && printf '%s\n' "${best_file[@]}"
}

build_one() {
    local pkg=$1
    local dir="$repo_root/pkgs/$pkg"
    local -a outputs

    # --packagelist reports the exact paths makepkg would write, honouring
    # PKGDEST and PKGEXT. Predicting those names by hand gets the arch suffix
    # and compression extension wrong sooner or later.
    #
    # It also lists a -debug package whenever debug is in makepkg's OPTIONS,
    # including for arch=any packages that contain no binaries and so never
    # produce one. Counting that phantom as missing would defeat the skip
    # logic and rebuild everything on every run.
    local line
    outputs=()
    while IFS= read -r line; do
        [[ $(basename "$line") == "$pkg-debug-"* ]] && continue
        outputs+=("$line")
    done < <(cd "$dir" && PKGDEST="$REPO_DIR" makepkg --packagelist)

    if [[ ${#outputs[@]} -eq 0 ]]; then
        echo "$pkg: makepkg reported no package outputs" >&2
        return 1
    fi

    if [[ $FORCE_REBUILD -ne 1 ]]; then
        local missing=0 out
        for out in "${outputs[@]}"; do
            [[ -f $out ]] || missing=1
        done
        if [[ $missing -eq 0 ]]; then
            echo "$pkg: already built, skipping"
            return 0
        fi
    fi

    echo "$pkg: building"
    local -a flags=(--noconfirm --cleanbuild --force)
    # --nodeps skips makedepends along with depends. chiroptera-dots renders its
    # fastfetch logo with rsvg-convert at package time, and used to build only
    # when an earlier --syncdeps package in the same run had pulled librsvg in.
    if [[ ${extra_flags[$pkg]:-} == *--nodeps* ]]; then
        local -a makedeps
        mapfile -t makedeps < <(cd "$dir" && makepkg --printsrcinfo \
            | awk -F' = ' '$1 == "\tmakedepends" { print $2 }')
        if ((${#makedeps[@]})); then
            sudo pacman -S --needed --noconfirm "${makedeps[@]}"
        fi
    fi
    # shellcheck disable=SC2206
    [[ -n ${extra_flags[$pkg]:-} ]] && flags+=(${extra_flags[$pkg]})

    (cd "$dir" && PKGDEST="$REPO_DIR" makepkg "${flags[@]}")
}

fetch_released() {
    local pkg=$1 repo=${released[$1]}
    local -a auth=()
    # Unauthenticated API calls share a 60-an-hour limit per runner address.
    [[ -n ${GITHUB_TOKEN:-} ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")

    local asset name url digest
    asset=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$repo/releases/latest" \
        | jq -r --arg pkg "$pkg" '.assets[]
            | select(.name | test("^" + $pkg + "-[^-]+-[^-]+-[^-]+\\.pkg\\.tar\\.zst$"))
            | [.name, .browser_download_url, (.digest // "")] | @tsv' | head -1)
    IFS=$'\t' read -r name url digest <<<"$asset"
    if [[ -z ${name:-} ]]; then
        echo "$pkg: the latest release of $repo has no package" >&2
        return 1
    fi

    if [[ -f $REPO_DIR/$name && $FORCE_REBUILD -ne 1 ]]; then
        echo "$pkg: $name already fetched, skipping"
        return 0
    fi
    echo "$pkg: fetching $name from $repo"
    curl -fsSL -o "$REPO_DIR/$name.part" "$url"
    if [[ $digest == sha256:* ]] \
        && [[ $(sha256sum "$REPO_DIR/$name.part" | cut -d' ' -f1) != "${digest#sha256:}" ]]; then
        rm -f "$REPO_DIR/$name.part"
        echo "$pkg: $name does not match the release's sha256" >&2
        return 1
    fi
    mv "$REPO_DIR/$name.part" "$REPO_DIR/$name"
}

prune_old_versions() {
    local -A versions_of=()
    local f base name ver rel

    shopt -s nullglob
    for f in "$REPO_DIR"/*.pkg.tar.*; do
        [[ $f == *.sig ]] && continue
        base=$(basename "$f")
        # pkgname may contain dashes; pkgver, pkgrel and arch may not.
        if [[ $base =~ ^(.+)-([^-]+)-([^-]+)-([^-]+)\.pkg\.tar\.[a-z]+$ ]]; then
            name=${BASH_REMATCH[1]}
            ver=${BASH_REMATCH[2]}
            rel=${BASH_REMATCH[3]}
            versions_of[$name]+="${ver}-${rel} "
        fi
    done

    for name in "${!versions_of[@]}"; do
        local -a ordered
        # Deliberately unquoted: each version must arrive as its own argument.
        # shellcheck disable=SC2086
        mapfile -t ordered < <(sort_versions_desc ${versions_of[$name]})
        local i
        for ((i = KEEP; i < ${#ordered[@]}; i++)); do
            echo "$name: dropping ${ordered[i]} (keeping newest $KEEP)"
            rm -f "$REPO_DIR/$name-${ordered[i]}"-*.pkg.tar.*
        done
    done
}

sign_packages() {
    if [[ -z ${PACKAGE_SIGNING_KEY:-} ]]; then
        echo "no PACKAGE_SIGNING_KEY set; publishing unsigned"
        return 0
    fi
    echo "signing packages"
    gpg --batch --import <<<"$PACKAGE_SIGNING_KEY"
    local f
    for f in "$REPO_DIR"/*.pkg.tar.*; do
        [[ $f == *.sig ]] && continue
        [[ -f $f.sig ]] && continue
        gpg --batch --yes --detach-sign --no-armor "$f"
    done
}

build_database() {
    local db="$REPO_DIR/$REPO_NAME.db.tar.zst"
    local -a add_flags=()
    [[ -n ${PACKAGE_SIGNING_KEY:-} ]] && add_flags+=(--sign)

    # A bare *.pkg.tar.* glob also matches detached signatures, which repo-add
    # would try to read as packages once signing is enabled.
    local -a pkgfiles=() f
    for f in "$REPO_DIR"/*.pkg.tar.*; do
        [[ -f $f && $f != *.sig ]] || continue
        pkgfiles+=("$f")
    done

    if [[ ${#pkgfiles[@]} -eq 0 ]]; then
        echo "no packages to put in the database" >&2
        return 1
    fi

    # Rebuild from the retained file set rather than amending, so the database
    # can never drift from what is actually on disk. That makes repo-add's
    # --new and --remove meaningless here: there is no prior database to
    # amend, and --remove only prints a confusing empty-filename notice.
    # Older versions stay on disk for rollback but out of the database.
    rm -f "$REPO_DIR/$REPO_NAME".db* "$REPO_DIR/$REPO_NAME".files*
    mapfile -t pkgfiles < <(newest_packages "${pkgfiles[@]}")
    repo-add "${add_flags[@]}" "$db" "${pkgfiles[@]}"

    # repo-add leaves chiroptera.db and chiroptera.files as symlinks. Static
    # hosts do not serve symlinks, so a published repository would 404 on the
    # database while working perfectly from a local file:// path.
    local ext link
    for ext in db files; do
        link="$REPO_DIR/$REPO_NAME.$ext"
        if [[ -L $link ]]; then
            rm -f "$link"
            cp "$link.tar.zst" "$link"
        fi
    done
}

for pkg in "${packages[@]}"; do
    if [[ -n ${released[$pkg]:-} ]]; then
        fetch_released "$pkg"
    else
        build_one "$pkg"
    fi
done

prune_old_versions
sign_packages
build_database

echo
echo "repository built in $REPO_DIR:"
ls -1 "$REPO_DIR"
