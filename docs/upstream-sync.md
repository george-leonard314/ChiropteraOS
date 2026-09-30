# Upstream sync ritual

`chiroptera-shell` is Noctalia with the rename transform
(`chiroptera/rename.sh`) and a few Chiroptera commits on top: the plugin-API
alias, the bat icon, the default wallpaper, the README credit, and
`chiroptera <name>` running `chiroptera-<name>`. Syncing means: apply the same
transform to upstream's new tree on a branch, then merge that.

Expect many conflicts: every upstream edit to a line that contained the old
name is a both-sides-changed hunk (main renamed it, the sync branch renamed it
and carries upstream's edit). They all resolve the same way: take the sync
branch's side, so merge with `-X theirs`. `-X theirs` only settles
line-level conflicts; three kinds of file-level conflict are left for you, and
each has a fixed answer:

- `assets/chiroptera-wallpaper.png` and `assets/chiroptera.svg` (rename/delete
  or add/add): these are our wallpaper and bat icon, which replace upstream's.
  Keep main's: `git checkout HEAD -- <file>`.
- A file upstream deleted and main still has (modify/delete, `UD`): delete it
  with `git rm <file>`, unless it is one of ours (under `chiroptera/`, or
  `tests/plugin_api_alias_test.cpp`).
- Anything else: read it; it is new.

`chiroptera/check-rename.sh` and the `plugin_api_alias` test prove the
Chiroptera hunks survived.

Nothing here runs automatically. Do it when an upstream release is worth
having; sync to release tags (`vX.Y.Z`), not `main`, so the Chiroptera tag
names a real upstream version. Upstream reads its version from `VERSION`;
leave it equal to upstream's so plugins gate correctly.

```sh
cd ~/Projects/chiroptera-shell
git fetch upstream --tags
new=v5.3.0                                                           # the upstream release to sync to
git log --oneline "$(cut -d' ' -f2 .upstream-sync)..$new"            # what changed
git checkout -b sync "$new"
bash <(git show main:chiroptera/rename.sh)
git add -A && git commit -m "Apply Chiroptera transform to upstream $new"
git checkout main
git merge --no-commit -X theirs sync
git status --short | grep -E '^(AA|UD|DU|AU|UA)'                     # resolve these as above
echo "upstream $(git rev-parse "$new^{commit}")" > .upstream-sync
git add -A
chiroptera/check-rename.sh
meson setup build --reconfigure --buildtype=debug -Dtests=enabled && meson compile -C build && meson test -C build
git commit -m "Merge upstream $new"
git branch -D sync
```

## Why the history was rebuilt for v5.2.0

Up to v5.0.1 the fork's commits carried the same content as upstream's but
different commit ids (upstream's history had been rewritten after the fork
was taken), so the newest common ancestor Git could find was from April 2026
and the merge above reconciled thousands of commits. The v5.2.0 sync was
therefore built by hand: a clean v5.2.0, the transform, then the Chiroptera
commits replayed with `git cherry-pick -x`, recorded as a merge whose second
parent descends from upstream's v5.2.0. From then on the merge base is a real
upstream release and the ritual above works; a rehearsal against the 64
upstream commits after v5.2.0 left only the three file-level conflicts listed.

If upstream ever rewrites its history again, do the same: branch from the
upstream release, run the transform, cherry-pick the Chiroptera commits since
the last sync, and commit the result with
`git commit-tree <sync>^{tree} -p main -p <sync>`.

## After a sync

Tag `v<upstream version>-chiroptera<N>` (N restarts at 1 when the upstream
version changes), bump `pkgver` and `_tag` in
`ChiropteraOS/pkgs/chiroptera-shell/PKGBUILD` (`pkgver` is the tag with the
leading `v` dropped and `-` replaced by `.`; `v5.2.0-chiroptera1` becomes
`5.2.0.chiroptera1`), and check upstream's `PACKAGING.md` for new runtime
dependencies. Push main and the new tag by name (not `--tags`: the upstream
remote's tags are in the local repository too), push ChiropteraOS so CI
rebuilds, install, and run the laptop checks from the step 1 plan, Task 6.
