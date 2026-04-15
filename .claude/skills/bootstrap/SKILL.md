---
name: bootstrap
description: Bootstrap a fresh Gas City workspace — clone rigs, initialize Dolt/beads, configure remotes, and start the city. Use when setting up a new machine, onboarding a developer, or recovering a broken workspace.
---

# Bootstrap Gas City Workspace

You are an interactive setup assistant. Walk the user through each phase,
**prompting for input** when needed and **verifying every step** before
moving on. If a step fails, diagnose the failure and attempt to fix it
before asking the user for help.

**Golden rule:** Never silently continue past a failed step. Every command
that can fail MUST be checked. Use `--verbose` or `-v` flags wherever
available. Show the user what happened and what you're doing about it.

---

## Phase 0: Environment Setup

Homebrew tools may not be on PATH in non-interactive shell contexts (tmux
sessions, pre_start hooks, cron). Before anything else, ensure PATH is
correct for this machine.

**Detect and fix PATH:**

```bash
# Detect brew location (Intel vs Apple Silicon)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
```

Run this and confirm the output includes brew's bin directory. Then detect
the current environment:

```
Platform:     !`uname -ms`
Shell:        !`echo $SHELL`
Brew prefix:  !`brew --prefix 2>/dev/null || echo "NOT FOUND"`
PATH sample:  !`echo $PATH | tr ':' '\n' | head -5`
```

### Prerequisite check

Check each tool individually. For any that are missing, collect them all
and give the user ONE install command:

| Tool | Check | Install |
|------|-------|---------|
| gc | `gc version` | `brew install gastownhall/tap/gc` |
| bd | `bd version` | `brew install gastownhall/tap/bd` |
| dolt | `dolt version` | `brew install dolt` |
| tmux | `tmux -V` | `brew install tmux` |
| gh | `gh --version` | `brew install gh` |
| jq | `jq --version` | `brew install jq` |
| git | `git --version` | (should be present; `xcode-select --install` if not) |

**If any are missing**, print a single `brew install` command with all
missing packages and STOP. Tell the user to run it and then re-invoke
`/bootstrap`.

**If gh is not authenticated** (`gh auth status` exits non-zero), tell the
user to run `! gh auth login` (the `!` prefix runs it in this session so
the auth token is available immediately). STOP until authenticated.

### Gather identity

Prompt the user:

> **What is your GitHub username?**
> (I'll auto-detect if you have `gh` authenticated)

Auto-detect with `gh api user -q .login`. If it fails, ask explicitly.
Store as `GH_USER`. The integration branch will be `$GH_USER/develop`.

---

## Phase 1: Clone Rig Repos

Read `city.toml` to discover rigs and their paths. For each rig, check if
the directory exists. If missing, clone it.

**Current rig definitions (from city.toml):**

| Rig | Relative Path | GitHub Repo |
|-----|---------------|-------------|
| enterprise | `../enterprise` | `safety-chain/enterprise` |
| designsystem | `../design-system` | `safety-chain/design-system` |

For each missing rig directory:

```bash
BRANCH="${GH_USER}/develop"
git clone https://github.com/safety-chain/<repo>.git ../<dir>

# Try to check out the user's integration branch
if git -C ../<dir> ls-remote --heads origin "$BRANCH" | grep -q "$BRANCH"; then
  git -C ../<dir> checkout "$BRANCH"
else
  echo "Branch $BRANCH does not exist on remote. Creating locally..."
  git -C ../<dir> checkout -b "$BRANCH"
fi
```

### Verify Phase 1

For each rig path in `city.toml`, confirm:
1. Directory exists
2. It's a git repo (`git -C <path> rev-parse --git-dir`)
3. Current branch is correct

**If any fail:** Show which rig failed and why. Check if the user has repo
access (`gh repo view safety-chain/<repo> --json name`). If 403/404, the
user may need org access — tell them to request it and STOP.

---

## Phase 2: Initialize Dolt & Beads

All rigs share a **single Dolt SQL server** with **one database**. Beads in
each repo are just different prefix views into the same database.

### 2a. Prompt for database name

Ask the user:

> **What Dolt database name should I use?**
>
> This is typically your DoltHub username (e.g., `cboyle`). If you're
> joining an existing team, ask your team lead for the shared database
> name. If you don't have a DoltHub account, pick any name — you can
> add a remote later.
>
> Database name:

Store as `DB_NAME`.

### 2b. Prompt for DoltHub remote (optional)

Ask the user:

> **Do you want to sync beads to DoltHub?** (y/n)
>
> If yes, I'll configure push/pull to `safety-chain/$DB_NAME` on DoltHub.
> You'll need write access to the `safety-chain` org on DoltHub.
> If no, beads will work fully offline — you can add a remote later.

Store as `SETUP_REMOTE` (true/false).

If yes, verify access:
```bash
dolt login --check 2>&1 || echo "NOT_LOGGED_IN"
```

If not logged in, tell the user to run `! dolt login` and STOP until done.

### 2c. Initialize beads in gas-city (HQ prefix)

First check if beads is already initialized:
```bash
ls .beads/metadata.json 2>/dev/null
```

**If already initialized:** Ask the user if they want to reinitialize
(destructive) or skip. Default: skip.

**If not initialized:**

```bash
# Gas City uses gc to manage the Dolt server, so start it first
gc dolt start

# Wait for port file
until [ -f .beads/dolt-server.port ]; do sleep 1; done
DOLT_PORT=$(cat .beads/dolt-server.port)
echo "Dolt server running on port $DOLT_PORT"

# Initialize beads with server mode
bd init \
  --prefix hq \
  --server \
  --server-host 127.0.0.1 \
  --server-port "$DOLT_PORT" \
  --database "$DB_NAME" \
  --non-interactive \
  --role maintainer \
  --skip-hooks \
  --skip-agents \
  --verbose
```

### Verify 2c

```bash
bd list --verbose 2>&1
```

**If bd list fails** with connection errors:
1. Check `gc dolt status` — is the server running?
2. Check the port: `cat .beads/dolt-server.port` — does it match?
3. Check `gc dolt logs | tail -20` for server errors
4. Try restarting: `gc dolt stop && gc dolt start`
5. Re-run `bd list --verbose`

**If it still fails**, show the user the error and STOP.

### 2d. Configure HQ beads

After successful init, write the cross-rig routes and config:

**`.beads/config.yaml`** — set auto-start to false (gc manages the server):
```yaml
issue_prefix: hq
issue-prefix: hq
dolt.auto-start: false
```

**`.beads/routes.jsonl`** — enable cross-rig bead routing:
```jsonl
{"prefix":"hq","path":"."}
{"prefix":"sc","path":"../enterprise"}
{"prefix":"de","path":"../design-system"}
```

### 2e. Initialize beads in enterprise (prefix sc)

```bash
cd ../enterprise

bd init \
  --prefix sc \
  --server \
  --server-host 127.0.0.1 \
  --server-port "$DOLT_PORT" \
  --database "$DB_NAME" \
  --non-interactive \
  --role maintainer \
  --skip-hooks \
  --skip-agents \
  --verbose
```

Configure routes:
```jsonl
{"prefix":"hq","path":"../gas-city"}
{"prefix":"sc","path":"."}
{"prefix":"de","path":"../design-system"}
```

And config:
```yaml
issue_prefix: sc
issue-prefix: sc
dolt.auto-start: false
```

### 2e-post. Set issue_prefix in beads database config

**CRITICAL:** The `.beads/config.yaml` file and the beads **database**
config (`bd config`) are separate. The database config controls which
prefix `bd create` uses when minting new bead IDs. If this is wrong,
every new session bead and wisp gets the wrong prefix.

From the city root:
```bash
gc bd config set issue_prefix hq
```

From the enterprise rig:
```bash
gc bd --db ../enterprise/.beads config set issue_prefix sc
```

**Verify both:**
```bash
gc bd config get issue_prefix          # should print: hq
gc bd --db ../enterprise/.beads config get issue_prefix  # should print: sc
```

If the designsystem rig is initialized:
```bash
gc bd --db ../design-system/.beads config set issue_prefix de
```

### 2f. Initialize beads in design-system (prefix de)

Same pattern with `--prefix de`. Configure routes pointing back to siblings.

### 2g. Verify cross-rig routing

From the city root:
```bash
# Create a test bead
TEST_ID=$(bd create "Bootstrap smoke test" -t chore --json | jq -r '.id')
echo "Created: $TEST_ID"

# Verify it's visible from enterprise
cd ../enterprise
bd show "$TEST_ID" --verbose

# Clean up
cd ../gas-city  # or city root
bd update "$TEST_ID" --status closed
```

**If cross-rig routing fails:**
1. Check `routes.jsonl` exists in both repos
2. Verify paths are correct (relative to each repo's `.beads/` location)
3. Verify both repos point to the same `--database` name
4. Run `BD_DEBUG_ROUTING=1 bd show $TEST_ID` for debug output

---

## Phase 3: DoltHub Remote Setup

**Skip this phase if `SETUP_REMOTE` is false.**

```bash
cd <city-root>/.beads/dolt/$DB_NAME

# Add remote
dolt remote add origin \
  "https://doltremoteapi.dolthub.com/safety-chain/$DB_NAME"

# Check if remote has existing data
dolt fetch origin 2>&1
```

**If fetch succeeds and remote has data:**
```bash
# Pull remote data (merge with local)
dolt pull origin main
```

**If fetch fails with auth errors:**
Tell user to run `! dolt login` and verify they have write access to the
`safety-chain` org on DoltHub.

**If remote repo doesn't exist yet:**
Tell user to create it on DoltHub: `https://www.dolthub.com/organizations/safety-chain`
or run:
```bash
# Push local to create the remote repo (if they have org permissions)
dolt push -u origin main
```

### Verify sync

```bash
gc dolt sync --dry-run
```

Should show the database and remote URL without errors. If it shows
"no common ancestor", this means local and remote diverged. Ask the user
which is authoritative before proceeding:

> **Local and remote have no common ancestor.**
> This usually means one was initialized independently.
>
> - If this is a **fresh setup** and the remote has team data: pull from remote
> - If this is a **fresh setup** and remote is empty: push local to remote
> - If **unsure**: STOP and ask your team lead
>
> Which should I do? (pull / push / stop)

**NEVER force-push without explicit user confirmation.**

---

## Phase 3b: Patch Formula Errata

The installed gastown pack formulas may have known issues that need patching.
Apply these fixes to `.gc/system/packs/gastown/formulas/` after `gc start`
generates the pack directory.

### Refinery: remote branch cleanup after merge

The refinery merge-push step's cleanup block must have the remote branch
delete in a proper bash code block. Without this, the refinery skips
deleting merged polecat branches from origin, leaving stale remote refs.

**File:** `.gc/system/packs/gastown/formulas/mol-refinery-patrol.formula.toml`

Find the direct-mode cleanup block (step 4 in merge-push). It should read:

```
**4. Cleanup:**
```bash
git branch -d temp
if [ "{{delete_merged_branches}}" = "true" ]; then
  git push origin --delete "$BRANCH" || echo "WARNING: failed to delete remote branch $BRANCH"
fi
```
```

If instead it reads as a prose conditional like:
```
If delete_merged_branches = "true": `git push origin --delete $BRANCH`
```

Replace the cleanup block so the `git push origin --delete` is inside the
bash code fence. The refinery agent interprets code blocks reliably but may
skip prose conditionals.

**Verify:** `grep -A4 'git branch -d temp' .gc/system/packs/gastown/formulas/mol-refinery-patrol.formula.toml`
should show the `if` block, not a prose line.

---

## Phase 4: Start the City

```bash
cd <city-root>
gc start
```

Wait for startup, then check:

```bash
gc status
```

**Expected:** Controller running, mayor + deacon sessions appearing.

### Verify startup health

```bash
gc doctor
```

**Handle findings:**

| Doctor finding | Severity | Action |
|----------------|----------|--------|
| `rig:*:path — not found` | ERROR | Rig directory missing — go back to Phase 1 |
| `rig:*:git — not a git repository` | WARN | Check `.git` exists; may be a submodule issue |
| `beads-store — not accessible` | ERROR | Dolt server not running — `gc dolt start` |
| `dolt-server — not reachable` | ERROR | Check `gc dolt status`, restart if needed |
| `events-log-size` warning | WARN | OK to ignore on fresh setup |

**If doctor has errors**, fix them before continuing. If warnings only, proceed.

### Check session startup

```bash
gc session list
```

**Expected:** Mayor and deacon should reach `active` state within ~60s.

**If sessions are stuck in `creating` for >2 minutes:**

The `[session] startup_timeout` in city.toml controls how long the
controller waits. The default is 60s which is often too short for large
repos. Check city.toml:

```bash
grep -A1 '\[session\]' city.toml
```

If `startup_timeout` is missing or less than 120s, add/update it:
```toml
[session]
startup_timeout = "180s"
```

Then restart the rig: `gc rig restart <rig>`

**If sessions hit `quarantine`:**
```bash
gc session wake <session-id>
```

This clears the quarantine and lets the reconciler retry.

---

## Phase 5: Final Verification Checklist

Run each check and report pass/fail to the user:

```bash
# 1. Controller
gc status | head -3

# 2. Health
gc doctor 2>&1 | tail -3

# 3. Sessions
gc session list

# 4. Beads from HQ
cd <city-root>
bd list --limit 5

# 5. Beads from enterprise (cross-rig)
cd ../enterprise
bd list --limit 5

# 6. Dolt sync (if remote configured)
gc dolt sync --dry-run 2>&1

# 7. Rig status
gc rig status enterprise
```

Present results as a checklist:

```
Bootstrap Results:
  [x] Controller running
  [x] Doctor passed (N warnings)
  [x] Mayor active
  [x] Deacon active
  [x] Beads accessible from HQ
  [x] Beads accessible from enterprise (cross-rig routing)
  [x] DoltHub remote configured and syncing
  [x] Enterprise rig path valid
  [ ] Polecats spawning (may take 1-2 minutes)
```

---

## Troubleshooting Reference

These are real issues encountered in production. Check for them proactively.

### Polecat startup timeout (deadline_exceeded)

**Symptom:** `gc trace show --template <rig>/polecat --since 10m` shows
`outcome_code: deadline_exceeded` after ~60s.

**Root cause:** Enterprise repo is large; Claude session takes >60s to
initialize (loading context, MCP servers, extended thinking on first turn).

**Fix:** Add to city.toml:
```toml
[session]
startup_timeout = "180s"
```

Ref: https://github.com/gastownhall/gascity/commit/4aac23aef36c69c2c6eda13f092a02676c8b7cd8
This is a `[session]` key, NOT `[daemon]`.

### Dolt auto-push fails (no common ancestor)

**Symptom:** `bd update` commands show warning: `dolt auto-push failed:
no common ancestor`

**Root cause:** Local Dolt database and DoltHub remote have independent
histories (e.g., local was init'd fresh while remote has existing data).

**Fix:**
1. Check how much data each side has before acting
2. If remote has the team's data: `dolt pull origin main` (may need merge)
3. If local is authoritative: `gc dolt sync --force` (DESTROYS remote history)
4. **NEVER force-push without verifying what's on the remote first**

After fixing, verify: `bd update <any-bead> --set-metadata test=1` should
complete without warnings. Then `bd update <bead> --unset-metadata test`.

### Beads assigned to personal names

**Symptom:** Beads have `assignee: "Casey Boyle"` or `owner: boylec@live.com`
instead of Gas City agent names.

**Root cause:** Beads were migrated from a non-Gas-City source (e.g., Linear
import) and carried personal identifiers.

**Fix:** Pool-routed beads should be unassigned:
```bash
bd update <bead-id> --assignee ""
```

### Session prefix mismatch

**Symptom:** Sessions or wisps get the wrong prefix (e.g., `de-` for
enterprise sessions that should be `sc-`).

**Root cause:** The beads **database** config (`bd config get issue_prefix`)
was set to the wrong prefix. The `.beads/config.yaml` file and the database
config are separate — both must agree. New beads (including session beads)
use the database config value, not the YAML file.

**Diagnose:**
```bash
gc bd config get issue_prefix                            # city — should be: hq
gc bd --db ../enterprise/.beads config get issue_prefix  # enterprise — should be: sc
```

**Fix the prefix config:**
```bash
gc bd config set issue_prefix hq
gc bd --db ../enterprise/.beads config set issue_prefix sc
```

**Fix existing wrongly-prefixed session beads:**

`gc session close` will NOT work on config-managed always-on sessions.
Instead, stop the city, close the beads directly, and rename or recreate:

```bash
gc stop

# Option A: Rename existing beads (preserves history)
gc bd rename de-abc hq-abc   # city agents → hq prefix
gc bd rename de-xyz sc-xyz   # enterprise agents → sc prefix

# Option B: Close beads and let controller create fresh ones
gc bd close de-abc de-xyz

gc start
```

After restart, verify with `gc session list` that all session IDs use the
correct prefix for their rig.

### Refinery stuck at permission prompts

**Symptom:** Witness reports refinery stuck; tmux shows permission prompts
despite `--dangerously-skip-permissions`.

**Fix:** Reset the session:
```bash
gc session reset <session-id>
```

### MCP server auth failures

**Symptom:** Polecat tmux shows "N MCP servers failed" or "needs auth".

**Impact:** Non-fatal. Polecats work without MCP servers. The failing
servers are typically Linear (needs OAuth) and Aspire (needs local setup).

**Fix (if needed):**
- Linear: Configure token via Linear settings
- Aspire: Run Aspire setup locally
- To disable: Remove from `.mcp.json` in the rig repo

### Dolt server health

**Symptom:** bd commands hang, timeout, or return empty results.

**Diagnostics:**
```bash
gc dolt status
gc dolt health
gc dolt logs | tail -20
```

**Fix:**
```bash
gc dolt stop
gc dolt start
gc dolt health  # verify
```

If orphan databases accumulate: `gc dolt cleanup`
**Never use `rm -rf` on Dolt data directories.**
