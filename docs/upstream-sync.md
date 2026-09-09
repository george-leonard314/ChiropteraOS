# Upstream sync ritual

`chiroptera-shell` is a full-history copy of Noctalia with the rename transform
(`chiroptera/rename.sh`) and the plugin-API alias committed on top. Syncing
means: apply the same transform to upstream's new tree on a branch, then merge
that. Expect many conflicts: every upstream edit to a line that contained the
old name is a both-sides-changed hunk (main renamed it, the sync branch renamed
it and carries upstream's edit). They all resolve the same way: take the sync
branch's side. The only main-only hunks that must survive are the alias block
in `src/scripting/luau_host.cpp` (marked `noctalia-compat`) and the
`plugin_api_alias` entry in `meson.build`; `chiroptera/check-rename.sh` and the
`plugin_api_alias` test prove they did. So merge with `-X theirs` and let the
checks catch a lost hunk.

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
git merge --no-commit -X theirs sync
echo "upstream $(git rev-parse upstream/main)" > .upstream-sync
git add .upstream-sync
chiroptera/check-rename.sh
meson setup build --reconfigure --buildtype=debug -Dtests=enabled && meson compile -C build && meson test -C build
git commit -m "Merge upstream $(git rev-parse --short upstream/main)"
git branch -D sync
```

## After a sync

Tag `v<upstream version>-chiroptera<N>` (N restarts at 1 when the upstream
version changes), bump `pkgver` and `_tag` in
`ChiropteraOS/pkgs/chiroptera-shell/PKGBUILD` (`pkgver` is the tag with the
leading `v` dropped and `-` replaced by `.`; `v5.0.1-chiroptera2` becomes
`5.0.1.chiroptera2`), push with `--tags`, rebuild, install, and run the laptop
checks from the step 1 plan, Task 6.
