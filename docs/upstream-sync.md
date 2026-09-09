# Upstream sync ritual

`chiroptera-shell` is a full-history copy of Noctalia with the rename transform
(`chiroptera/rename.sh`) and the plugin-API alias committed on top. Syncing
means: apply the same transform to upstream's new tree on a branch, then merge
that. Because the transform is deterministic, the rename itself never
conflicts; only upstream edits adjacent to renamed text do, and those are
mechanical. The alias commit merges like any other source change.

Nothing here runs automatically. Do it when an upstream change is worth
having. Check upstream's release notes for plugin API level bumps: the shell
must keep `version:` in `meson.build` equal to upstream's so plugins gate
correctly.

```sh
cd ~/git/chiroptera-shell
git fetch upstream
git log --oneline "$(cut -d' ' -f2 .upstream-sync)..upstream/main"   # what changed
git checkout -b sync upstream/main
bash <(git show main:chiroptera/rename.sh)
git add -A && git commit -m "Apply Chiroptera transform to upstream $(git rev-parse --short upstream/main)"
git checkout main
git merge sync            # resolve conflicts: keep both the rename and upstream's edit
echo "upstream $(git rev-parse upstream/main)" > .upstream-sync
chiroptera/check-rename.sh
meson setup build --reconfigure --buildtype=debug -Dtests=enabled && meson compile -C build && meson test -C build
git add -A && git commit -m "Merge upstream $(git rev-parse --short upstream/main)"
git branch -D sync
```

## After a sync

Tag `v<upstream version>-chiroptera<N>` (N restarts at 1 when the upstream
version changes), bump `pkgver` and `_tag` in
`ChiropteraOS/pkgs/chiroptera-shell/PKGBUILD` (`pkgver` is the tag with `-`
replaced by `.`), push with `--tags`, rebuild, install, and run the laptop
checks from the step 1 plan, Task 6.
