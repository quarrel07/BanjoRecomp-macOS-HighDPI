# Publishing this fork — one-time setup

All commits are already prepared locally on `macos-highdpi` branches, and a `fork` git remote is
already configured in each repo. You just need to (1) create the forks on GitHub and (2) push.
These steps require **your** GitHub login (they can't be done from an automated environment).

## 1. Create the forks on GitHub
Click **Fork** on each of these (keep the default name, owner = `quarrel07`):

- https://github.com/renderbag/plume  → `quarrel07/plume`
- https://github.com/rt64/rt64  → `quarrel07/rt64`
- https://github.com/N64Recomp/RecompFrontend  → `quarrel07/RecompFrontend`
- https://github.com/N64Recomp/N64Recomp  → `quarrel07/N64Recomp`

(Your `quarrel07/BanjoRecomp-macOS-HighDPI` main fork already exists.)

## 2. Push the branches (order matters — innermost first)
`plume` must be pushed before `rt64`, because `rt64` records a pointer to the plume fork commit.

```bash
cd /Users/Andy/Documents/GitHub/BanjoRecomp

git -C lib/rt64/src/contrib/plume push fork macos-highdpi      # plume (3ffc1f6)
git -C lib/rt64                    push fork macos-highdpi      # rt64  (fa1b97c)
git -C lib/RecompFrontend          push fork macos-highdpi      # RecompFrontend (fbd7953)
git -C /Users/Andy/Documents/GitHub/N64Recomp push fork macos-highdpi   # N64Recomp tool (5ab5e0c)

git push fork macos-highdpi                                     # this repo (a1fd1bd)
```

The first time, git may prompt for your GitHub username + a Personal Access Token (use a token, not
your password). The macOS keychain will remember it after that.

## 3. Verify a clean recursive clone builds the right tree
```bash
git clone --recurse-submodules https://github.com/quarrel07/BanjoRecomp-macOS-HighDPI /tmp/bk-fork-test
cd /tmp/bk-fork-test && git checkout macos-highdpi && git submodule update --init --recursive
# Confirm the fix files are present:
grep -c "ApplePressAndHoldEnabled" src/main/main.cpp
grep -c "retain()" lib/rt64/src/contrib/plume/plume_metal.cpp   # expect 4 (plus context)
```
> Note: `BanjoRecompSyms` and `lib/bk-decomp` still point upstream (unchanged), and the ROM is never
> included — a builder supplies their own, exactly as with upstream.

## 4. (Optional) make `macos-highdpi` the default
On github.com → `quarrel07/BanjoRecomp-macOS-HighDPI` → Settings → Branches → set default to
`macos-highdpi`, or open a PR `macos-highdpi` → `main` within your fork and merge. Do the same on the
dependency forks if you want their default branch to show the changes.

## Keeping up with upstream later
In any fork, add the original as a second remote so you can pull updates:
```bash
git -C lib/rt64 remote add upstream https://github.com/rt64/rt64
git -C lib/rt64 fetch upstream && git -C lib/rt64 merge upstream/main   # then resolve, re-push
```
