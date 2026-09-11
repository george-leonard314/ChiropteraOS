#!/usr/bin/env bash
# Run chiroptera-hwd's bats suite.
#
# CI runs this inside the Arch container. Locally bats is not assumed, so run
# it through docker -- see docs/hwd.md. Pass test files to run a subset.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

bash -n "$repo_root/hwd/chiroptera-hwd"

if (($#)); then
    exec bats "$@"
fi
exec bats "$repo_root/hwd/tests"
