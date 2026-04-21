---
name: bootstrap
description: Bootstrap a fresh Gas City workspace — clone rigs, run `gc init` (which handles Dolt/beads/routes/sessions/pack fetch), optionally configure DoltHub remotes, and verify. Use when setting up a new machine, onboarding a developer, or recovering a broken workspace.
---

# Bootstrap Gas City Workspace

You are an interactive setup assistant. Walk the user through each phase,
**prompting for input** when needed and **verifying every step** before
moving on. If a step fails, diagnose the failure and attempt to fix it
before asking the user for help.

**Golden rule:** Never silently continue past a failed step. Every command
that can fail MUST be checked. Use `--verbose` or `-v` flags wherever
available. Show the user what happened and what you're doing about it.

**Architecture note (gc 0.14.1+):** `gc init` is the single command that
bootstraps the city runtime. It creates `.beads/` in the city root and every
rig, starts the Dolt server, writes `routes.jsonl` + `config.yaml` with
correct prefixes, fetches the configured pack (`gastown`), registers the
city with the machine-wide supervisor (launchd on macOS), and starts the
controller. This replaces the older multi-step flow of `gc dolt start` +
`bd init --server` per rig + hand-written config files.

---

## Phase 0: Environment Setup

Homebrew tools may not be on PATH in non-interactive shell contexts (tmux
sessions, pre_start hooks, cron). Before anything else, ensure PATH is
correct for this machine.

**Detect and fix PATH:**

```bash
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
```

Detect and report the current environment:

```
Platform:     !`uname -ms`
Shell:        !`echo $SHELL`
Brew prefix:  !`brew --prefix 2>/dev/null || echo "NOT FOUND"`
PATH sample:  !`echo $PATH | tr ':' '\n' | head -5`
```

### Prerequisite check

Formula names per docs.gascityhall.com/getting-started/installation.
Installing `gastownhall/gascity/gascity` transitively installs tmux, jq,
dolt, beads, and flock — but check each individually in case of partial
install.

| Tool | Check | Install |
|------|-------|---------|
| gc | `gc version` | `brew install gastownhall/gascity/gascity` |
| dolt | `dolt version` | `brew install dolt` |
| tmux | `tmux -V` | `brew install tmux` |
| flock | `flock --version` | `brew install flock` |
| gh | `gh --version` | `brew install gh` |
| jq | `jq --version` | `brew install jq` |
| git | `git --version` | (should be present; `xcode-select --install` if not) |

**If any are missing**, print a single `brew install` command with all
missing packages and STOP. Tell the user to run it and then re-invoke
`/bootstrap`.

**If gh is not authenticated** (`gh auth status` exits non-zero), tell the
user to run `! gh auth login`. STOP until authenticated.

### Shell alias conflict check

Oh-my-zsh's `git` plugin defines `alias gc='git commit --verbose'`, which
shadows the Gas City binary in interactive zsh. Bootstrap itself runs in
non-interactive bash and is unaffected, but the user will hit it the
moment they run `gc` manually.

Detect with:
```bash
zsh -i -c 'type gc' 2>&1 | grep -q "alias for" && echo "CONFLICT"
```

**If conflict detected**, offer to patch `~/.zshrc` by adding
`unalias gc 2>/dev/null` after the `source $ZSH/oh-my-zsh.sh` line, then
tell the user to `source ~/.zshrc` or open a new shell. STOP until
resolved — their terminal will appear broken later if we proceed.

### Gather identity

Prompt the user:

> **What is your GitHub username?**
> (I'll auto-detect if you have `gh` authenticated)

Auto-detect with `gh api user -q .login`. If it fails, ask explicitly.
Store as `GH_USER`. The integration branch will be `$GH_USER/develop`.

---

## Phase 1: Clone Rig Repos

Read `city.toml` to discover rigs and their paths. For each rig, check
if the directory exists. If missing, clone it.

Rig definitions come from `city.toml`. Don't hard-code them — read the
`[[rigs]]` tables for `name`, `path`, and the corresponding GitHub repo.

For each missing rig directory:

```bash
BRANCH="${GH_USER}/develop"
# Use `gh repo clone` — reuses the authenticated gh session (token or SSH
# per the user's `gh config get git_protocol`). Raw `git clone https://...`
# falls through to a password prompt when no credential helper is cached,
# and GitHub rejects password auth for git operations.
gh repo clone safety-chain/<repo> <path>

if git -C <path> ls-remote --heads origin "$BRANCH" | grep -q "$BRANCH"; then
  git -C <path> checkout "$BRANCH"
else
  echo "Branch $BRANCH does not exist on remote. Creating locally..."
  git -C <path> checkout -b "$BRANCH"
fi
```

### Verify Phase 1

For each rig path in `city.toml`, confirm:
1. Directory exists
2. It's a git repo (`git -C <path> rev-parse --git-dir`)
3. Current branch is correct

**If any fail:** Check if the user has repo access
(`gh repo view safety-chain/<repo> --json name`). If 403/404, they may need
org access — tell them to request it and STOP.

### Rig worktree hygiene for gc-deployed skills

`gc init` (Phase 2) deploys per-rig agent skills into each rig's
`.claude/skills/gc-*/` (gc-agents, gc-city, gc-dashboard, gc-dispatch,
gc-mail, gc-rigs, gc-work). These are **local-user artifacts** — they
should NOT be committed to the rig repos, because other teammates may
not even use Gas City and their `.claude/skills/` layout differs.

For each rig, add a surgical local exclude to `.git/info/exclude`
(preferred over `.gitignore` — this is a per-developer concern, not a
team-wide one):

```bash
for rig_path in $(read rig paths from city.toml); do
  if ! grep -q "^\.claude/skills/gc-\*/" "$rig_path/.git/info/exclude" 2>/dev/null; then
    printf '# gc init deploys per-rig agent skills into .claude/skills/gc-*/ ; these\n# are local-user artifacts, not committable to the shared rig repo.\n.claude/skills/gc-*/\n' \
      >> "$rig_path/.git/info/exclude"
  fi
done
```

**Do NOT add `.claude/` as a blanket exclude** — rigs typically have
team-shared skills under `.claude/skills/` (e.g. `.claude/skills/aspire`,
`api-endpoint-builder`, etc.) that are tracked and must remain visible to
git. The surgical `.claude/skills/gc-*/` rule only hides the gc-injected
ones.

**Verify:** after adding the rule, `git status` in each rig should show a
clean worktree (no stray `.claude/skills/gc-*/` entries).

---

## Phase 2: Initialize the City

**One command does everything:** `gc init`. It creates `.beads/` (with
0700 perms) in the city root and each rig, starts the Dolt server,
generates `routes.jsonl` + `config.yaml` with correct per-rig prefixes,
creates three Dolt databases (one per prefix: hq, sc, de, …), fetches the
pack (usually `gastown`), registers the city with the supervisor, and
starts the controller.

### 2a. Choose the init path

- **Existing city.toml committed in the target dir** (most common for
  onboarding): use `--file` to reuse it.
  ```bash
  cd <city-dir>
  # Temporarily move the file so gc doesn't refuse ("already initialized")
  mv city.toml /tmp/city.toml.real
  gc init --file /tmp/city.toml.real <city-dir>
  ```

- **Fresh setup, no city.toml yet**: run interactively.
  ```bash
  gc init <city-dir>
  # Prompts: template (tutorial/gastown/custom), coding agent
  ```

### 2b. Restore city.toml (if needed)

`gc init` rewrites `city.toml` into canonical form — it expands inline
tables into sections, and it changes `name` to the directory basename.
Semantic content is preserved, but if the user has a committed `city.toml`
with a specific `name` (e.g. company name, not dir name), restore it:

```bash
git -C <city-dir> checkout -- city.toml
```

The runtime state (`.beads/`, `.gc/`) is independent of `city.toml`
formatting, so the restore is cosmetic unless the runtime re-reads
`city.toml` on next restart — which it does — so the restored name WILL
stick.

### 2c. Verify init succeeded

```bash
gc status          # controller should be running
gc doctor          # run health checks; expect mostly green
gc doctor --fix    # auto-fix rig-index and similar warnings
gc bd list --limit 5   # beads should be accessible; you'll see session beads for mayor/deacon/boot
```

**If `gc status` shows "city runtime not bootstrapped":** `gc init` didn't
complete. Check logs, verify no stale `.gc/` dir is blocking, and re-run.

**If `gc doctor` has unfixable errors:** STOP and surface them to the
user. Common real errors:
- `rig:*:path — not found` → rig directory missing, back to Phase 1
- `rig:*:git — not a git repository` → rig was cloned incorrectly
- `dolt-server — not reachable` → Dolt didn't come up; try
  `gc service restart` or re-init

### 2d. Note on Dolt database layout

`gc init` creates one database per prefix under a single Dolt server:

```
.beads/dolt/
├── hq/    # city root beads
├── sc/    # enterprise rig beads
└── de/    # design-system rig beads
```

The server listens on 127.0.0.1:<port> (see `.beads/dolt-server.port`),
and each rig's `.beads/metadata.json` records `dolt_database` = its
prefix. This matters for Phase 3 — **DoltHub remotes are per-database**,
not one remote for the whole city.

---

## Phase 3: DoltHub Remote Setup (optional)

**Skip this phase** if the user chose offline-only. Remotes can be added
later.

Ask the user for DoltHub org/username. The skill's working assumption is
the `safety-chain` org, but confirm.

### 3a. Check DoltHub auth

```bash
dolt creds check
```

**If auth fails:** tell user to run `! dolt login` and STOP until done.

### 3b. Check for pre-existing remotes

**`gc init` often pre-configures an `origin` remote** on each Dolt DB
pointing at a `git+ssh://…/…git` URL — this is dolt-over-git storage
using the rig's own github repo (or, for hq, a personal repo). That
channel may or may not hold real data.

Before adding DoltHub, inspect what's already there:

```bash
for prefix in hq sc de; do
  cd <city-root>/.beads/dolt/$prefix
  echo "=== $prefix ==="
  dolt remote -v
  dolt fetch origin 2>&1 | tail -3
  # If origin has data, compare:
  dolt log origin/main --oneline | head -3
  dolt rev-list --left-right --count HEAD...origin/main 2>/dev/null
done
```

If `origin` has content, decide per-DB: keep it, add DoltHub as a second
remote (e.g. named `dolthub`), or replace `origin` with DoltHub. Replacing
is destructive to whatever was on the `git+ssh` remote — confirm with the
user before `dolt remote remove origin`.

### 3c. Add / replace remote per database

Naming convention observed in this workspace: **`<user>-gas-city-<rig>`**
(e.g. `cboyle-gas-city-hq`, `cboyle-gas-city-enterprise-rig`,
`cboyle-gas-city-designsystem-rig`). Confirm the convention the user's
team uses; it varies.

For each DB (one per rig prefix):

```bash
cd <city-root>/.beads/dolt/<prefix>

# If origin already exists and the user chose to replace it:
dolt remote remove origin 2>/dev/null

# Add DoltHub
dolt remote add origin \
  "https://doltremoteapi.dolthub.com/<org>/<repo-name>"

# Check if remote has data
if dolt fetch origin 2>&1; then
  echo "Remote reachable"
  dolt log origin/main --oneline | head -5
else
  echo "Fetch failed — remote may not exist yet"
fi
```

### 3d. Reconcile local ↔ remote

Four cases, handle each:

| Case | Action |
|------|--------|
| Remote has no data yet | `dolt push -u origin main` to create it (requires org write access) |
| Remote has team data, local is fresh | `dolt pull origin main` |
| Local and remote share history | No action; sync will happen on auto-push |
| Local and remote have **no common ancestor** | **STOP.** Ask which is authoritative before destroying history. Never force-push without explicit user confirmation. |

### 3e. Verify sync

```bash
cd <city-root>/.beads/dolt/<prefix>
dolt status               # should be clean
dolt log --oneline -5     # should show recent commits
```

**NEVER force-push (`dolt push -f`) without explicit user confirmation,
and never to a remote holding team data.**

---

## Phase 3b: Patch Formula Errata (check-only)

The `gastown` pack was fetched by `gc init` into
`.gc/system/packs/gastown/`. Check for known errata; patch if present,
otherwise skip.

### Refinery: remote branch cleanup after merge

The direct-mode cleanup block in `mol-refinery-patrol.formula.toml` step 4
of merge-push must have the remote-branch delete inside a bash code fence.
The prose conditional form causes the refinery to skip the delete.

Verify with:
```bash
grep -A4 'git branch -d temp' .gc/system/packs/gastown/formulas/mol-refinery-patrol.formula.toml
```

**Correct form** (cleanup inside a single bash fence):
```
**4. Cleanup:**
\`\`\`bash
git branch -d temp
if [ "{{delete_merged_branches}}" = "true" ]; then
  git push origin --delete "$BRANCH" || echo "WARNING: failed to delete remote branch $BRANCH"
fi
\`\`\`
```

**Buggy form** (prose conditional after a closed bash fence — patch this):
```
\`\`\`bash
git branch -d temp
\`\`\`
If delete_merged_branches = "true": `git push origin --delete $BRANCH`
```

If you see the buggy form in the direct-mode cleanup block (around the
first occurrence of `git branch -d temp`), replace it with the correct
form above. The second occurrence of `git branch -d temp` in the file is
in MR mode — do NOT add a delete there, MR mode needs the source branch
to stay.

---

## Phase 4: Verify and Fix

**Note:** `gc init` already starts the controller, so this phase is
verify-only, not start-the-city. `gc start` is used only to resume a
stopped city or if init didn't leave the controller running.

### 4a. Confirm city is running

```bash
gc status                # expect: Controller running, agents listed
gc service list          # expect: dolt-server, controller healthy
gc service doctor        # detailed service status
```

### 4b. Run doctor with auto-fix

```bash
gc doctor --fix
gc doctor                # re-run to verify clean
```

Expected: `N passed, 0 warnings`.

### 4c. Check sessions

```bash
gc session list
```

Mayor, deacon, boot should reach `active` (or be mintable on demand);
polecats are `stopped` until work arrives (pool pattern).

**If sessions are stuck in `creating` for >2 minutes:**

Check `[session] startup_timeout` in `city.toml`. Default is 60s — often
too short for large repos like enterprise. Set to 180s:

```toml
[session]
startup_timeout = "180s"
```

Then `gc rig restart <rig>` to pick up the change.

**If sessions hit `quarantine`:**

```bash
gc session wake <session-id>
```

### 4d. Rig-specific status

```bash
gc rig status enterprise
gc rig status designsystem      # skip if suspended in city.toml
```

---

## Phase 5: Final Verification Checklist

Run each check and report pass/fail:

```bash
gc status | head -5
gc doctor 2>&1 | tail -3
gc service list
gc beads health
gc session list
bd list --limit 5                    # from city root (hq)
bd list --limit 5                    # cd into each rig dir to verify cross-rig accessibility
gc rig status enterprise
```

Present results as a checklist:

```
Bootstrap Results:
  [x] Controller running
  [x] Doctor passed (0 warnings after --fix)
  [x] Services healthy (dolt-server, controller)
  [x] Session beads minted (mayor, deacon, boot)
  [x] Beads accessible from HQ
  [x] Beads accessible from enterprise (cross-rig routing)
  [x] DoltHub remotes configured (skip if user declined)
  [x] Rig paths valid
  [x] Refinery formula patched (or already correct)
  [ ] Polecats spawning (may take 1-2 minutes after first work arrives)
```

---

## Troubleshooting Reference

Real issues encountered in production. Check proactively.

### Polecat startup timeout (deadline_exceeded)

**Symptom:** `gc trace show --template <rig>/polecat --since 10m` shows
`outcome_code: deadline_exceeded` after ~60s.

**Root cause:** Enterprise repo is large; Claude session takes >60s to
initialize (context loading, MCP servers, extended thinking on first turn).

**Fix:** Add to `city.toml`:
```toml
[session]
startup_timeout = "180s"
```

This is a `[session]` key, NOT `[daemon]`.

### city.toml gets rewritten by gc init

**Symptom:** After `gc init`, `city.toml` differs from the committed
version — inline tables expanded into sections, `name` changed to
directory basename, `[session]` moved relative to `[daemon]`.

**Root cause:** `gc init` serializes `city.toml` in canonical form.
Semantic content is preserved.

**Fix:** `git checkout -- city.toml`. Runtime state (`.beads/`, `.gc/`)
is independent of formatting, so the restore is safe. The original
`name` will be used on next controller reload.

### Dolt auto-push fails (no common ancestor)

**Symptom:** `bd update` commands show `dolt auto-push failed: no common
ancestor`.

**Root cause:** Local Dolt database and DoltHub remote have independent
histories (local was init'd fresh while remote has existing data, or vice
versa).

**Fix:**
1. `cd <city-root>/.beads/dolt/<prefix>` to inspect the specific DB
2. Check each side's history: `dolt log --oneline -5` (local),
   `dolt log origin/main --oneline -5` (remote)
3. If remote has team data: `dolt pull origin main` (may conflict —
   resolve manually)
4. If local is authoritative AND remote history is disposable:
   `dolt push -f origin main` (**DANGEROUS**; never without explicit
   user confirmation)
5. **NEVER force-push without verifying what's on the remote first**

After fixing, `bd update <any-bead> --set-metadata test=1` should
complete without warnings. Then unset: `bd update <bead> --unset-metadata test`.

### Beads assigned to personal names

**Symptom:** Beads have `assignee: "Casey Boyle"` or `owner: boylec@live.com`
instead of Gas City agent names.

**Root cause:** Beads were migrated from a non-Gas-City source (Linear
import, manual dolt push) and carried personal identifiers.

**Fix:** Pool-routed beads should be unassigned:
```bash
bd update <bead-id> --assignee ""
```

### Session prefix mismatch

**Symptom:** Sessions or wisps get the wrong prefix (e.g. `de-` for an
enterprise session that should be `sc-`).

**Root cause:** The beads **database** config (`bd config get issue_prefix`)
is separate from `.beads/config.yaml`. Both must agree. New beads use the
database config value.

**Diagnose:**
```bash
gc bd config get issue_prefix                            # city — expect: hq
gc bd --db ../enterprise/.beads config get issue_prefix  # expect: sc
gc bd --db ../design-system/.beads config get issue_prefix  # expect: de
```

**Fix:**
```bash
gc bd config set issue_prefix hq
gc bd --db ../enterprise/.beads config set issue_prefix sc
gc bd --db ../design-system/.beads config set issue_prefix de
```

**Fix existing wrongly-prefixed session beads:**

`gc session close` does NOT work on config-managed always-on sessions.
Instead, stop the city, rename (or close) beads, restart:

```bash
gc stop

# Option A: Rename existing beads (preserves history)
gc bd rename de-abc hq-abc
gc bd rename de-xyz sc-xyz

# Option B: Close and let controller recreate
gc bd close de-abc de-xyz

gc start
```

Verify with `gc session list` after restart.

### Refinery stuck at permission prompts

**Symptom:** Witness reports refinery stuck; tmux shows permission prompts
despite `--dangerously-skip-permissions`.

**Fix:**
```bash
gc session reset <session-id>
```

### MCP server auth failures

**Symptom:** Polecat tmux shows "N MCP servers failed" or "needs auth".

**Impact:** Non-fatal. Polecats work without MCP servers. Failing servers
are typically Linear (OAuth) and Aspire (local setup).

**Fix (if needed):**
- Linear: configure token via Linear settings
- Aspire: run Aspire setup locally
- To disable per-rig: remove from `.mcp.json`

### Dolt / beads service health

**Symptom:** `bd` commands hang, timeout, or return empty results.

**Diagnostics (0.14.1 — `gc dolt *` no longer exists):**
```bash
gc beads health                             # beads-provider diagnostics
gc service list                             # all workspace services
gc service doctor                           # detailed service status
ls .beads/dolt/                             # confirm databases present
cat .beads/dolt-server.port                 # confirm port file
lsof -iTCP:$(cat .beads/dolt-server.port)   # confirm server listening
```

**Fix:**
```bash
gc service restart dolt-server              # or whatever name `gc service list` uses
gc beads health                             # verify
```

For manual Dolt inspection (last resort):
```bash
cd .beads/dolt/<prefix>
dolt status
dolt log --oneline -5
```

**Never use `rm -rf` on Dolt data directories** — use `gc service restart`
or re-init the city via `gc init` on a fresh workspace.

### Offline maintenance: really stopping gc + dolt

**Symptom:** Trying to run `dolt table import`, bulk SQL updates, or any
file-level maintenance on `.beads/dolt/<prefix>/` fails with
`cause: cannot update manifest: database is read only`, even after
`gc stop` and killing `dolt sql-server` by hand.

**Root cause:** `gc stop` only *unregisters* the city from the
machine-wide supervisor; it doesn't kill the launchd service that
re-spawns the supervisor, which in turn re-spawns the Dolt server. Any
time you kill the Dolt process, launchd (or the supervisor) brings it
back within seconds, and it reacquires the lock files under
`.dolt/noms/`.

**Fix — fully stop the daemon tree:**

```bash
# 1. Unregister the city (releases launchd job)
gc stop

# 2. Bootout the launchd service so nothing respawns
launchctl bootout gui/$(id -u)/com.gascity.supervisor

# 3. Kill any surviving dolt sql-server processes
pkill -f "dolt sql-server" 2>/dev/null

# 4. Verify nothing is holding locks
pgrep -lf "dolt\|gascity" || echo "(clean)"
lsof +D .beads/dolt/<prefix> 2>&1 | head
```

Now `dolt sql`, `dolt table import`, `dolt push/pull`, etc. work
directly against the on-disk data.

**To bring gas-city back up:**

```bash
gc start     # re-registers the launchd service and starts the controller
```

**When to use this:** bulk data migrations (see "Migrating beads from an
older DoltHub repo" below), schema surgery, manual dolt branch grafting,
or any sustained period of offline DB editing. For quick read-only
inspection you don't need this — `dolt sql` routes through the running
server transparently.

### Migrating beads from an older bd version DoltHub repo

**Scenario:** A new gas-city workspace wants to bring in historical beads
from an old, single-DB DoltHub repo (bd v0.61-era or similar), split into
the three per-prefix DBs that `gc init` created (hq / sc / de), possibly
with prefix renames (e.g. legacy `gt-*` / `api-*` → `hq-*`).

**Why it's non-trivial:**

1. `bd export` is the portable cross-version format — it handles schema
   differences internally. **But `bd export` omits the `comments` and
   `events` tables** (only `comment_count` is exported). Those require
   raw-SQL migration on top.
2. Source (old-version) and target (new-version) DBs may have divergent
   `issues` columns (v1.0 dropped `hook_bead`, `role_bead`, `agent_state`,
   `last_activity`, `role_type`, `rig` and others). `bd import` handles
   the upgrade, raw SQL won't.
3. v1.0 adds validation — e.g. *non-closed issues cannot have
   `closed_at`*. v0.61-era data will have records that violate this; the
   whole `bd import` aborts on the first one.
4. `gc init` creates per-rig Dolt databases (hq, sc, de …). A legacy
   single-DB source must be SPLIT by prefix, not just copied.
5. Cross-rig dependencies (e.g. `sc-idp-epic.* → de-*`) are legitimate
   and should stay in the originating rig's DB — the runtime resolves
   cross-DB via `routes.jsonl`.

**End-to-end playbook:**

```bash
# 1. Stand up the legacy DB as a readable bd workspace
dolt clone <org>/<old-repo> /tmp/legacy-source
dolt sql-server --host 127.0.0.1 --port 14000 --data-dir /tmp/legacy-source &
mkdir -p /tmp/bd-src/.beads
echo 14000 > /tmp/bd-src/.beads/dolt-server.port
cat > /tmp/bd-src/.beads/metadata.json <<EOF
{"database":"dolt","backend":"dolt","dolt_mode":"server",
 "dolt_server_host":"127.0.0.1","dolt_database":"<source-db-name>",
 "dolt_host":"127.0.0.1","dolt_user":"root"}
EOF

# 2. Export issues (incl. memories, infra, labels, deps) to JSONL
(cd /tmp/bd-src && bd export --all --include-infra -o /tmp/src.jsonl)

# 3. Write a Python filter/rename script that:
#    - Routes records by id prefix (hq/sc/de)
#    - Renames legacy prefixes (gt-* -> hq-*, api-* -> hq-*)
#    - Rewrites refs in dependencies[].issue_id / depends_on_id
#    - Scrubs v0.61-era validation violations (e.g. closed_at on open issues)
#    Output: /tmp/migrate-hq.jsonl, migrate-sc.jsonl, migrate-de.jsonl

# 4. Fully stop gc (see "Offline maintenance" above)
gc stop
launchctl bootout gui/$(id -u)/com.gascity.supervisor
pkill -f "dolt sql-server"

# 5. Wipe data tables in each target local DB, then bd import
for prefix in hq sc de; do
  (cd .beads/dolt/$prefix && \
   dolt sql -q "DELETE FROM issues; DELETE FROM dependencies; \
                DELETE FROM labels; DELETE FROM events; \
                DELETE FROM comments; DELETE FROM issue_snapshots; \
                DELETE FROM compaction_snapshots; \
                DELETE FROM child_counters; DELETE FROM issue_counter;")
done

# import in each rig's cwd so bd picks up the right .beads/
(cd <city-root>     && bd import /tmp/migrate-hq.jsonl)
(cd <enterprise>    && bd import /tmp/migrate-sc.jsonl)
(cd <design-system> && bd import /tmp/migrate-de.jsonl)

# 6. Backfill events + comments via raw SQL (bd export skips them)
#    Export filtered CSVs from the legacy source, import into each target.
(cd /tmp/legacy-source && dolt sql -r csv -q "
  SELECT id,
    CASE WHEN issue_id LIKE 'gt-%'  THEN CONCAT('hq-', SUBSTRING(issue_id, 4))
         WHEN issue_id LIKE 'api-%' THEN CONCAT('hq-', SUBSTRING(issue_id, 5))
         ELSE issue_id END AS issue_id,
    event_type, actor, old_value, new_value, comment, created_at
  FROM events
  WHERE issue_id LIKE 'hq-%' OR issue_id LIKE 'gt-%' OR issue_id LIKE 'api-%'
") > /tmp/hq-events.csv
# ...similar for sc, de, and for comments
for prefix in hq sc de; do
  (cd .beads/dolt/$prefix && dolt table import -u events /tmp/$prefix-events.csv)
  (cd .beads/dolt/$prefix && dolt table import -u comments /tmp/$prefix-comments.csv)
done

# 7. Commit + force-push each target DB to its DoltHub remote
for prefix in hq sc de; do
  (cd .beads/dolt/$prefix && \
   dolt add . && \
   dolt commit -m "migrate: snapshot from <legacy-db>" && \
   dolt push -f origin main)
done

# 8. Bring the city back up
gc start
```

**Common pitfalls:**

- *"database is read only"* during `dolt table import` → supervisor
  respawned; see "Offline maintenance" above.
- *"validation failed for issue X: non-closed issues cannot have
  closed_at timestamp"* → add `closed_at` scrubbing to the filter script
  (pop it when `status != "closed"`).
- Mismatch in `bd list` counts between pre-push local state and
  post-start state → `gc start` auto-creates session beads (mayor,
  deacon, boot, dog pool). Expect +small-N deltas in the `hq` DB.
- Pre-existing `git+ssh://` origin on each Dolt DB (from `gc init`) must
  be explicitly removed before adding a DoltHub URL; `dolt remote add
  origin` errors out if origin already exists.
