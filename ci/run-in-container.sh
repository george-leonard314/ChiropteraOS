#!/usr/bin/env bash
# Run the full pipeline -- lint, build, smoke test -- in a throwaway Arch
# container, the same way CI does.
#
# This exists so the workflow can be exercised without pushing and waiting.
# Point SOURCES at a directory holding local clones of the private source
# repositories to build without a deploy token:
#
#   SOURCES=$HOME/git ./ci/run-in-container.sh
#
# Results are left in ./repo unless REPO_OUT says otherwise.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMAGE=${IMAGE:-archlinux:base-devel}
SOURCES=${SOURCES:-}
REPO_OUT=${REPO_OUT:-$repo_root/repo}
FORCE_REBUILD=${FORCE_REBUILD:-0}
PACKAGES=${PACKAGES:-}

mkdir -p "$REPO_OUT"

docker_args=(
    --rm
    -v "$repo_root:/work:ro"
    -v "$REPO_OUT:/out"
    -e "FORCE_REBUILD=$FORCE_REBUILD"
)
[[ -n $PACKAGES ]] && docker_args+=(-e "PACKAGES=$PACKAGES")

if [[ -n $SOURCES ]]; then
    docker_args+=(
        -v "$SOURCES:/sources:ro"
        -e "CHIROPTERA_SHELL_REPO=file:///sources/chiroptera-shell"
        -e "CHIROPTERA_DOTS_REPO=file:///sources/chiroptera-dots"
    )
elif [[ -n ${SOURCE_REPO_TOKEN:-} ]]; then
    docker_args+=(-e "SOURCE_REPO_TOKEN=$SOURCE_REPO_TOKEN")
else
    echo "warning: neither SOURCES nor SOURCE_REPO_TOKEN set;" >&2
    echo "         the private source repositories will not clone" >&2
fi

exec docker run "${docker_args[@]}" "$IMAGE" bash -euo pipefail -c '
    pacman -Syu --needed --noconfirm git sudo >/dev/null

    useradd -m builder
    echo "builder ALL=(ALL) NOPASSWD: /usr/bin/pacman" > /etc/sudoers.d/builder

    # makepkg writes into the package directories, so work on a copy and leave
    # the mounted checkout untouched.
    cp -a /work /build

    # A working tree may carry leftovers from a previous local build. makepkg
    # pins each bare source clone to the URL it came from and aborts if the
    # PKGBUILD now points elsewhere, so a stale clone breaks the run. CI never
    # sees this -- its checkout is clean and these paths are gitignored.
    rm -rf /build/pkgs/*/src /build/pkgs/*/pkg /build/pkgs/*/*.pkg.tar.*
    find /build/pkgs -mindepth 2 -maxdepth 2 -type d -exec test -e "{}/HEAD" \; -print0 \
        | xargs -0 --no-run-if-empty rm -rf
    chown -R builder:builder /build
    git config --global --add safe.directory "*"

    if [ -n "${SOURCE_REPO_TOKEN:-}" ]; then
        sudo -u builder git config --global \
            url."https://x-access-token:${SOURCE_REPO_TOKEN}@github.com/".insteadOf \
            "https://github.com/"
    fi

    sudo -u builder --preserve-env=CHIROPTERA_SHELL_REPO,CHIROPTERA_DOTS_REPO,FORCE_REBUILD,PACKAGES \
        bash -c "cd /build && ./ci/lint-pkgbuilds.sh && REPO_DIR=/out ./ci/build-repo.sh"

    REPO_DIR=/out /build/ci/smoke-test.sh
'
