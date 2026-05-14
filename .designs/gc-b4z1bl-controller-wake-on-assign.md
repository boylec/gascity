# gc-b4z1bl — Wake-on-assign for already-running sessions

**Status:** Design note (per mayor 2026-05-14). No implementation until a choice is made.

## Problem (recap)

A wisp/work bead reassigned to an **already-running** session does not wake
that session. The controller's wake path only fires for `!target.alive`
sessions (see `cmd/gc/session_reconciler.go:1488` — `if shouldWake && !target.alive`).
Live sessions sitting at the `❯` prompt stay idle until something else
nudges them. Observed in witness patrol loops on three cities; ~10–15
min per cycle stall.

The stub at `cmd/gc/city_runtime.go:1523` ("Idle recovery: detect pool
sessions stuck at the prompt after …") is the empty placeholder for this.

## Where assignment happens today

The gap exists wherever a bead is reassigned without going through
`gc sling`. `internal/sling/sling_core.go:423–432` does the right thing
— pokes the controller and sets `NudgeAgent` so the caller delivers a
nudge. `bd update --assignee` does neither: it is a pure store mutation.

Formula/script call sites of `bd update … --assignee=` that target an
**already-running** session (so would silently regress under Approach 3
alone):

| Call site | Line | Target |
|---|---|---|
| `mol-witness-patrol.toml` next-iteration | 488 | self (witness) |
| `mol-deacon-patrol.toml` next-iteration | 412 | self (deacon) |
| `mol-refinery-patrol.toml` next-iteration | 179, 251, 306, 610, 625 | self (refinery) |
| `mol-polecat-work.toml` submit-and-exit → refinery | 217 | refinery (live) |
| `mol-witness-patrol.toml` salvage warrants | various | other live agents |
| `examples/lifecycle/.../mock-polecat.sh` | 173 | refinery |
| `examples/maintenance/.../orphan-sweep.sh` | 112 | clears (no wake needed) |

Plus the patrol-cycle initial `bd update $WISP --assignee=$GC_AGENT` at
the top of each `mol-*-patrol.toml` (line 5). Those fire on a session
that's just been started, so the *initial* hook covers them, but any
subsequent re-pour hits the gap.

Go-side: only `cmd/gc/convergence_store.go:207` sets `Assignee` directly,
inside the convergence path; the API handler in
`internal/api/handler_sling.go:400` already pokes the controller. The
CLI `bd update` flag is parsed in `cmd/gc/cmd_bd_store_bridge.go:210` and
applied via the embedded store call — no post-write hook.

## Approach 1 — Controller-side scan (fill in the `Idle recovery` stub)

**What:** In each reconciler tick, after `dispatchReadyWaitNudges` /
`nudgeDispatchTick`, walk sessions that are `alive`, `at-prompt`
(`provider.IsAtPrompt(name)` or equivalent), and have at least one open
in-progress assigned bead whose `updated_at` is newer than the session's
`last_woke_at` / `last_prompt_ready_at`. For each, deliver a wake nudge
("you have new work — run `gc hook`").

**Where:** `cmd/gc/city_runtime.go` — replace the stub at line 1523 with
a new method `cr.idleRecoveryTick(ctx)`. Likely adds ~60–90 lines plus a
small helper to query open assigned beads per live session (the
`sessionHasOpenAssignedWorkForReachableStore` predicate already exists at
`cmd/gc/session_reconciler.go:682` and friends — reuse it). One new test
file (`cmd/gc/city_runtime_idle_recovery_test.go`, ~150 lines).

**Blast radius:** Self-contained in the reconciler. No formula or CLI
change. All bead-assignment paths benefit, including third-party scripts
the SDK does not own (e.g., user pack `bd update` calls).

**Hot-loop risk (mayor's explicit ask):** Yes — witness pours+assigns
every `event_timeout` cycle (default 30s). If the reconciler tick
discovers the assigned wisp and the session is at the prompt, it will
nudge. The session wakes, runs the wisp, eventually returns to the
prompt with a *new* assigned wisp (next-iteration), and the next
reconciler tick (default 1s–5s) sees a "new" assignment again. We must
prevent a duplicate-nudge storm. Mitigation:

- Track per-bead "wake delivered" — e.g., set `metadata.wake_dispatched_at=<ts>`
  on the bead at nudge time and skip if already set within the session's
  current prompt cycle (clear on session-not-at-prompt → at-prompt
  transition, or on bead.updated_at advance past the marker).
- Or track per-session: skip if `last_idle_recovery_at >= last_prompt_ready_at`
  for this session. Resets cleanly when the session leaves the prompt.

The second is simpler and avoids touching the bead store. Choose it.

**Risks not addressed:** If the controller is down or the reconciler tick
is wedged, recovery still stalls. (Acceptable — that's "controller is
broken," a different bug class.) Provider must expose a reliable
"at-prompt" / "idle" signal; tmux/acp both already track this via
`pending_interaction_ready`, but the fake provider needs parity.

## Approach 2 — CLI ping (`bd update` pokes the controller)

**What:** When `gc bd update --assignee` succeeds, fire the same
`pokeController(cityPath)` that sling uses, and — if the new assignee is
a live session — deliver a nudge to it. The poke just wakes the
reconciler; the nudge wakes the session.

**Where:** `cmd/gc/cmd_bd.go` (post-update hook on the `update` subcommand,
after the store write returns success). Lookup of `cityPath` from
`GC_CITY_PATH` / cwd walk is already done by other `cmd_bd*` paths.
~30–50 lines. The nudge delivery would reuse `deliverSessionNudge`
(`cmd/gc/cmd_nudge.go:485`) keyed off the resolved agent for the
qualified-name assignee. We'd also need an analogous hook for the API
PATCH path (`internal/api/` — the `Update` handler that accepts assignee
mutations). ~20 lines there. Total ~80 lines + tests (~150).

**Blast radius:** All `bd update --assignee` call sites benefit
automatically — formulas, scripts, third-party packs, refinery handoff,
polecat submission. This is the broadest coverage of the three.

But it also changes the contract of `bd update`: today it is a pure
store mutation with no runtime side effects. After this change it
acquires a controller dependency and a (best-effort) network/IPC call.

**Risks not addressed:**

- `bd update` is run by humans at the CLI, by tests with no controller
  running, and inside the bead store as a primitive. The poke must be
  silent-on-fail (matches sling's `_ = slingPokeController(...)`
  pattern) and gated so non-city contexts don't try to resolve a
  cityPath.
- Pure-Go callers that mutate `Assignee` via `Store.Update` (e.g.,
  `cmd/gc/convergence_store.go:207`) won't hit the CLI hook. Either
  push the hook down to the store layer (much larger blast radius —
  the store has no Notify interface today) or accept they remain
  uncovered. The latter is fine in practice: those callers are
  controller-internal and already trigger reconciler ticks via other
  paths.

## Approach 3 — Formula switch (witness uses `gc sling`)

**What:** Replace `gc bd update "$NEXT" --assignee=$GC_AGENT` in the
patrol `next-iteration` steps with `gc sling`. Sling already pokes the
controller and signals a nudge (`internal/sling/sling_core.go:423–432`).

**Where:** `examples/gastown/packs/gastown/formulas/mol-witness-patrol.toml:488`,
plus `mol-deacon-patrol.toml:412` and the multiple sites in
`mol-refinery-patrol.toml` (179, 251, 306, 610, 625). ~10–20 lines of
TOML across three files. Plus updating `mol-polecat-work.toml:217` to
sling instead of `bd update --assignee` for the refinery handoff. The
mock-polecat.sh equivalent.

**Blast radius:** Touches only user-facing pack TOML. No Go changes. Per
the "ZERO hardcoded roles" invariant this is the most architecturally
honest fix — the bug is "formula uses the wrong primitive," not "the
SDK is broken."

**Risks not addressed (this is the cross-cutting question the mayor flagged):**

- **Every other `bd update --assignee` call site we don't migrate still
  has the bug.** This isn't a one-formula fix; it's an audit of every
  user pack and every script. The table above enumerates the gastown
  set, but the SDK is built to support arbitrary user packs — we have
  no way to fix theirs.
- `gc sling` requires a sling target (an agent) and a formula or query.
  The witness next-iteration is pouring an *unstructured* next wisp into
  its own queue, not dispatching a new molecule. Migrating to sling
  changes semantics: sling expects an agent+formula pair, witness's
  next-iteration is "self-assign the pre-poured wisp." We may end up
  introducing a `gc sling --reassign-only` mode or similar, which
  imports complexity into sling.
- Future formula authors will hit the same gap whenever they write
  `bd update --assignee` against a live session. The bug becomes
  *folklore* ("don't do that, use sling") rather than fixed.

## Recommendation

**Approach 1 (controller-side scan), with the per-session
`last_idle_recovery_at` cooldown.** It addresses the root cause —
"controller doesn't wake live sessions on assignment" — at the layer
where the wake decision actually lives, and it fixes every present and
future call site (gastown, polecat handoff, user packs, raw `bd update`
in shells) without requiring formula authors to remember a rule. The
hot-loop is bounded by the session's own at-prompt transition, so the
worst case is one extra nudge per prompt cycle. Approach 3 is the most
architecturally pure but silently regresses anywhere a user forgets to
use sling, and Approach 2 quietly couples a store-mutation primitive
to runtime state, which is the wrong direction for the SDK's layering
invariants (CLAUDE.md: "side effects … confined to Layer 0"). The
controller is already Layer 0 and already owns the wake decision —
filling in its existing stub keeps the responsibility there.
