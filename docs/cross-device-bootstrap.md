# Cross-device bootstrap

How to get a new (or refreshed) device set up to run this Gas City workspace.

## Before you start

Stop the running city and kill any errant processes so the install replaces
nothing in flight:

```bash
gc stop
# Belt-and-suspenders if anything lingers:
pkill -f 'tmux .* -L gas-city'
pkill -f 'gc supervisor'
```

## Prerequisites

If not already installed on this device:

- Go 1.26+ (for building `gc`): `brew install go`
- `git`
- `gh` authenticated as `boylec`

## 1. gascity fork (build/install the `gc` binary)

If **not** already cloned:

```bash
mkdir -p ~/src/gastownhall && cd ~/src/gastownhall
git clone git@github.com:boylec/gascity.git
cd gascity
git remote add upstream git@github.com:gastownhall/gascity.git
git fetch upstream
```

If **already** cloned:

```bash
cd ~/src/gastownhall/gascity
git fetch origin
git fetch upstream
```

Check out the stacked branch and build:

```bash
git checkout local/all-prs-stacked
git pull origin local/all-prs-stacked   # in case of further updates

make install
```

Verify:

```bash
which gc        # should show ~/go/bin/gc (or a symlink)
gc version
```

## 2. gas-city workspace (config + schemas)

If **not** already cloned:

```bash
mkdir -p ~/src/SafetyChain && cd ~/src/SafetyChain
git clone https://github.com/boylec/safety-chain-gascity.git gas-city
cd gas-city
```

If **already** cloned:

```bash
cd ~/src/SafetyChain/gas-city
git checkout main
git pull --rebase
```

Sanity check that the new `gc` parses the new `[workspace.env]`:

```bash
gc config show | grep -A2 'workspace.env'
# Should print:
#   GC_TARGET_BRANCH = "boylec/develop"
```

## Notes

1. **Rig repos.** `city.toml` references `enterprise`, `gascity`, and
   `designsystem`. If they aren't cloned to the same paths as on the
   source machine, `gc doctor` will flag missing rig paths.
2. **Editor caches.** After `gc` is reinstalled and the schemas are
   pulled, reload the editor (Cmd+Shift+P → Developer: Reload Window) so
   taplo / Even Better TOML re-reads the new
   `docs/schema/{city,pack}-schema.json`.
3. **Refreshing later.** If `local/all-prs-stacked` has new merges,
   `make install` is the only step needed to refresh the binary — no
   other action.
4. **Maintaining the stack.** `local/all-prs-stacked` is a local-style
   integration branch, not for upstream review. As individual PRs
   (`#1227`, `#1230`, `#1239`, etc.) merge upstream, periodically
   rebuild it:

   ```bash
   cd ~/src/gastownhall/gascity
   git checkout local/all-prs-stacked
   git reset --hard upstream/main
   # re-merge remaining open branches
   make install
   git push -f origin local/all-prs-stacked
   ```
