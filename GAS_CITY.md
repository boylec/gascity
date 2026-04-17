# SafetyChain Gas City

Operational reference for how this workspace turns ideas into merged code.
For agents, the canonical source of behavior is
`template-fragments/sc-policy.md.tmpl`. For humans, this is the map.

## TL;DR

```plaintext
Linear issue or free-text idea
      │
      ▼
Talk to hq/mayor
      │
      ▼
Mayor slings mol-sc-idea-to-plan to a polecat-opus-max-1m coordinator
      │
      ▼
Coordinator produces a reviewed plan (PRD + design + review legs + gate)
      │
      ▼
Casey approves via mail → convoy + beads created, Linear-linked
      │
      ▼
Mayor slings mol-sc-sling-convoy → polecats (sonnet by default, opus-high
for complex, trivial skips ralph)
      │
      ▼
Polecats rebase on boylec/develop, implement (ralph-loop unless trivial),
push directly. No PRs, no feature branches, no merge queue.
      │
      ▼
Convoy auto-closes → Linear transitions to In Review
```

## Entrypoint: talk to the mayor

The mayor (`hq/mayor`) is always running. Attach to its session and tell
it what you want. Examples:

```bash
plan SAF-123                       # Linear path: mayor pulls issue via MCP
plan add convoy dispatch timeouts  # free-text path: mayor uses your text
dispatch <convoy-id>               # implement a previously-planned convoy
```

Mayor reads `template-fragments/sc-policy.md.tmpl` at startup, so it knows:
entry-mode detection, polecat variant selection, ralph-loop default, how
to notify you, and branch rules.

## Linear ↔ bead ↔ convoy linkage

- **A Linear issue can spawn many beads.** Do not enable `bd linear` sync
  — we don't want one-bead-per-Linear-issue mirroring.
- The **convoy** (parent bead, type=convoy) represents an initiative
  traceable to a Linear issue.
- The **children** (task beads) are implementation slices. Polecats claim
  and close them.
- Linear linkage is stamped by `mol-sc-idea-to-plan.create-beads`:
  - convoy: `metadata.linear_id=SAF-XX`, `--external-ref linear-SAF-XX`,
    label `linear:SAF-XX`
  - each child bead: same metadata + external-ref
- Agents read `External:` from `bd show --long`; it feeds the existing
  `linear-transitions.md.tmpl` global fragment (per-bead state
  transitions on claim + push).
- On convoy close, `mol-convoy-cleanup.sc-linear-transition` flips Linear
  to **In Review**. `mol-sc-linear-sync` (order, every 10m) catches any
  misses.

## Model / effort / variant selection

Three polecat variants are stamped into every rig (see `packs/safetychain/pack.toml`):

| Variant               | Model + effort        | When mayor picks it                                                                                  |
| --------------------- | --------------------- | ---------------------------------------------------------------------------------------------------- |
| `polecat-sonnet`      | sonnet, effort=medium | Default. Implementation beads. Parallel review legs.                                                 |
| `polecat-opus-high`   | opus, effort=high     | Architecture, migration, cross-cutting, hard debug, security-sensitive, data model, new subsystem.   |
| `polecat-opus-max-1m` | opus[1m], effort=max  | Planning coordinator (`mol-sc-idea-to-plan` runs here). Needs 1M context for PRD + many review legs. |

Model/effort are passed to the `claude` CLI via provider presets in
`city.toml` (`[providers.claude-sonnet]`, `[providers.claude-opus-high]`,
`[providers.claude-opus-max-1m]`).

## Ralph usage

Non-trivial implementation beads invoke the
`ralph-loop:ralph-loop` plugin skill during their implement step.
**Trivial beads** (mayor stamps `metadata.trivial=true` at sling, or
polecat judges it on claim) skip ralph. Trivial = single-file edit /
typo / dependency bump / config or string rename / comment-only / small
doc fix.

Pre-Gas-City `--ralph` sling flag does **not** exist. Anywhere you see it
referenced is stale.

## Branch strategy

- **Target branch: `boylec/develop`** for every rig. Enforced by
  `GC_TARGET_BRANCH=boylec/develop` env override on polecat variants and
  refinery (`city.toml` `[[rigs.overrides]]`).
- **No feature branches.** Polecats rebase onto boylec/develop, commit,
  push directly (`--merge=direct`). No merge queue, no PRs.
- Casey accumulates all work on `boylec/develop`, then raises the branch
  to `develop` (or upstream main) when ready.
- **Commit suffix**: `[SAF-XX]` if Linear-linked, else `[<bead-id>]`.
  Never `Closes SAF-XX` / `Fixes SAF-XX` on PR bodies — Gas City
  lifecycle owns Linear transitions, not GitHub auto-close.

## File map

```plaintext
/Users/caseyboyle/src/SafetyChain/gas-city/
├── city.toml                                  # workspace + rig + provider config
├── GAS_CITY.md                                # this file
├── formulas/                                  # local formulas
│   ├── mol-sc-idea-to-plan.formula.toml       # planning wrapper (extends mol-idea-to-plan)
│   ├── mol-sc-sling-convoy.formula.toml       # convoy dispatch + classification
│   ├── mol-sc-linear-sync.formula.toml        # safety-net Linear reconciliation
│   ├── mol-convoy-cleanup.formula.toml        # modified: adds sc-linear-transition step
│   ├── mol-polecat-base.formula.toml          # (existing) shared polecat steps
│   ├── mol-polecat-work-monorepo.formula.toml # (existing) monorepo implementation
│   └── ... 20+ more existing local formulas
├── packs/
│   └── safetychain/
│       ├── pack.toml                          # polecat sub-pack (flattens to root in step 9)
│       └── agents/
│           ├── polecat-sonnet/agent.toml
│           ├── polecat-opus-high/agent.toml
│           └── polecat-opus-max-1m/agent.toml
├── orders/
│   ├── beads-health.toml
│   └── linear-sync.toml                       # 10m cron for mol-sc-linear-sync
├── template-fragments/
│   └── sc-policy.md.tmpl                      # policy fragment (append_fragments in pack.toml)
├── scripts/
│   ├── sc-notify-human.sh                     # multi-channel human notifier
│   └── ... existing shared scripts
└── .gc/system/packs/gastown/                  # upstream gastown pack (unmodified)
```

## Notification and reply channels

**Outbound (agents → Casey):** `scripts/sc-notify-human.sh "<subject>" "<body>"`.
Fans out to:

1. `gc mail send human` for inbox audit trail
2. `osascript` macOS banner
3. Outbound webhook (optional; set `SC_NOTIFY_WEBHOOK` to a
   Slack/ntfy.sh/Pushover endpoint for phone push)
4. tmux bell when `$TMUX` is set

Do **not** rely on `gc mail send human --notify` alone — `--notify` is a
no-op for the `human` recipient in this Gas City version (tracked
upstream in `examples/gastown/FUTURE.md`).

**Inbound (Casey → coordinator):** mail-based, not live conversation.
When a formula step pauses waiting for you, it emits the exact reply
command. Typical form:

```bash
gc mail send <coordinator-session-id> -s "plan-approval" -m "y"
# or "request-changes: <notes>"
# or "abort"
```

The coordinator polls its own inbox (60s cadence, 24h hard timeout) for
that subject and acts on the body.

## Recipe: plan a new Linear issue

1. Create or adopt a Linear issue (e.g. SAF-123) with a real PRD section
   or linked Confluence/Notion doc.
2. Attach to mayor: `tmux -L gt-<socket> attach -t mayor` (socket at
   `/tmp/tmux-*/gt-*`).
3. Say: `plan SAF-123`.
4. Mayor slings `mol-sc-idea-to-plan` to a coordinator. Go do something
   else.
5. When the coordinator needs PRD clarification (one mid-flow gate), it
   posts into the live conversation. Attach, answer, detach.
6. When the plan is ready for final approval, your phone buzzes (if
   you've set `SC_NOTIFY_WEBHOOK`). Open the design doc from
   `.designs/<review-id>/design-doc.md`.
7. Reply: `gc mail send <coord-id> -s "plan-approval" -m "y"`.
8. Convoy + beads materialize. Linear state stays "In Progress".

## Recipe: dispatch a convoy

1. `gc sling hq/mayor mol-sc-sling-convoy --formula --var convoy_id=<id>`.
2. Polecats spin up, rebase onto boylec/develop, implement, push.
3. Watch `.convoy-logs/<id>/dispatch.tsv` for the plan of attack.
4. When the convoy auto-closes, Linear transitions to "In Review" and
   you get a notification.

## Troubleshooting

| Symptom                                       | First check                                                                                                                              |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Mayor doesn't recognize the plan command      | `gc doctor`; `gc config explain --agent mayor`; restart mayor session                                                                    |
| Polecat slings but work doesn't start         | `gc rig list`; check rig isn't suspended; `gc config explain --agent polecat-sonnet --rig enterprise`                                    |
| Approval gate never fires notification        | Check `scripts/sc-notify-human.sh` executable; verify `SC_NOTIFY_WEBHOOK` if you expect webhook; tail macOS Console for osascript errors |
| Linear stays "In Progress" after convoy close | `gc order run linear-sync` (force safety-net run); check `linear-server` MCP auth in `claude mcp list`                                   |
| Polecat pushes to wrong branch                | Check `echo $GC_TARGET_BRANCH` inside polecat worktree; verify `[[rigs.overrides]]` for that variant in `city.toml`                      |
| MCP `linear-server` fails with 401            | `claude mcp list` shows auth state; reauthenticate via your Claude Code session                                                          |
| Convoy dispatch misclassifies a bead          | Fix the heuristic in `mol-sc-sling-convoy.classify-and-sling`; or pass `--meta trivial=true/false` inline when slinging manually         |

## Non-goals / what this flow does NOT do

- **No `bd linear` sync.** We do not mirror beads to Linear one-for-one.
  Linear is the "where do ideas come from" system; beads are "how we
  split implementation". The linkage is many-to-one, intentional.
- **No feature branches, no merge queue.** Direct push to
  boylec/develop. Casey owns the branch's integrity and promotes it to
  `develop` when ready.
- **No first-class push notifications from Gas City itself.** Delegated
  to `sc-notify-human.sh`. When upstream adds it, we swap the helper's
  body.
- **No automatic Linear Done transitions.** Mayor moves issues to "In
  Review"; Casey moves them to "Done" manually after human review.

## Where to change what

- Policy for mayor / polecats: `template-fragments/sc-policy.md.tmpl`
- Polecat variants + provider bindings: `pack.toml` (providers) +
  `packs/safetychain/agents/<variant>/agent.toml`
- Planning flow shape: `formulas/mol-sc-idea-to-plan.formula.toml`
- Convoy dispatch heuristic: `formulas/mol-sc-sling-convoy.formula.toml`
- Linear in-formula transition: `formulas/mol-convoy-cleanup.formula.toml`
- Linear safety-net: `formulas/mol-sc-linear-sync.formula.toml` +
  `packs/safetychain/formulas/orders/linear-sync/order.toml`
- Notification channels: `scripts/sc-notify-human.sh`
- Branch enforcement: `city.toml` `[[rigs.overrides]]` env
