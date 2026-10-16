#!/usr/bin/env bash
# Fail if a name ChiropteraOS inherited from the projects its shell and greeter
# were forked from shows up anywhere but legacy/names.sh: in a file's content,
# text or binary, or in a file name. Tracked and untracked files are checked;
# ignored ones are not.
#
# The name itself is read from legacy/names.sh, so this script never spells it.
# It looks for the name's stem, so inflected forms in other languages fail too.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# shellcheck source=../legacy/names.sh
. legacy/names.sh

status=0

if hits=$(git grep --untracked -n -i -e "$LEGACY_NAME_STEM" -- . ':!legacy/names.sh'); then
    printf 'check-names: the old name appears outside legacy/names.sh:\n%s\n' "$hits" >&2
    status=1
fi

if names=$(git ls-files --cached --others --exclude-standard | grep -i -e "$LEGACY_NAME_STEM"); then
    printf 'check-names: file names carry the old name:\n%s\n' "$names" >&2
    status=1
fi

[[ $status -eq 0 ]] && echo "check-names: ok"
exit "$status"
