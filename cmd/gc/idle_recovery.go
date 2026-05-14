package main

import (
	"context"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/gastownhall/gascity/internal/beads"
	"github.com/gastownhall/gascity/internal/config"
	"github.com/gastownhall/gascity/internal/runtime"
	sessionpkg "github.com/gastownhall/gascity/internal/session"
)

// idleRecoveryLastDeliveredMetadata records the timestamp of the most recent
// idle-recovery wake nudge a session received. The reconciler uses this as a
// per-session cooldown: while the marker is set, no further idle-recovery
// nudges fire for that session. The marker is cleared whenever the runtime
// observation reports activity newer than the marker — that signals the
// session has acted on the prior nudge and is eligible for another one if a
// fresh reassignment arrives. Sessions that go fully offline drop the marker
// alongside their other live-state metadata via the normal lifecycle paths.
const idleRecoveryLastDeliveredMetadata = "last_idle_recovery_at"

// idleRecoveryMessage is the prompt delivered to a live session that has
// stranded assigned work. Plain English is sufficient — the receiving polecat
// formula re-runs `gc hook` on any nudge.
const idleRecoveryMessage = "new work assigned — run `gc hook`"

// idleRecoverySource tags queued nudges produced by idle recovery so the
// dispatcher's telemetry distinguishes them from session-level prompts.
const idleRecoverySource = "idle-recovery"

// idleRecoveryAtPromptThreshold is the quiescence window after which a live
// session is considered to be at the prompt rather than actively processing a
// turn. Sessions whose LastActivity is younger than this are skipped — they
// are still in the middle of an action that will eventually re-evaluate the
// reconciler queue on its own. This prevents the reconciler tick (1–5s) from
// piling on while a session is reacting to a previously-delivered nudge.
const idleRecoveryAtPromptThreshold = 2 * time.Second

// dispatchIdleRecoveryTick scans the running session set and enqueues a
// queued nudge for any alive session that holds open assigned work but is
// not eligible because it is already at the prompt. The reconciler's primary
// wake path only fires for !alive sessions; this fills the gap exposed when
// a wisp is reassigned to a session already at the prompt (e.g., a witness
// patrol next-iteration self-assignment, or a refinery handoff).
//
// Returns the number of sessions for which a wake nudge was enqueued.
func dispatchIdleRecoveryTick(
	ctx context.Context,
	cityPath string,
	cfg *config.City,
	store beads.Store,
	rigStores map[string]beads.Store,
	sp runtime.Provider,
	sessionBeads *sessionBeadSnapshot,
	now time.Time,
	stderr io.Writer,
) int {
	if cfg == nil || store == nil || sessionBeads == nil {
		return 0
	}
	if stderr == nil {
		stderr = io.Discard
	}
	delivered := 0
	for _, sb := range sessionBeads.Open() {
		if ctx != nil && ctx.Err() != nil {
			return delivered
		}
		sb := sb
		if maybeDispatchIdleRecovery(cityPath, cfg, store, rigStores, sp, sb, now, stderr) {
			delivered++
		}
	}
	return delivered
}

// maybeDispatchIdleRecovery evaluates a single session bead for idle recovery
// and, if appropriate, enqueues a wake nudge and stamps the cooldown marker.
// Returns true when a nudge was enqueued.
func maybeDispatchIdleRecovery(
	cityPath string,
	cfg *config.City,
	store beads.Store,
	rigStores map[string]beads.Store,
	sp runtime.Provider,
	sb beads.Bead,
	now time.Time,
	stderr io.Writer,
) bool {
	if !sessionBeadEligibleForIdleRecovery(sb) {
		return false
	}
	target := resolveNudgeTargetFromSessionBead(cityPath, cfg, sb)
	if target.sessionName == "" {
		return false
	}
	obs, err := workerObserveNudgeTarget(target, store, sp)
	if err != nil {
		fmt.Fprintf(stderr, "idle recovery: observing %s: %v\n", target.agentKey(), err) //nolint:errcheck
		return false
	}
	if !obs.Running {
		// Live recovery only applies to running sessions. Stopped sessions
		// take the standard wake path in beadReconcileTick.
		return false
	}
	if !sessionIsAtPrompt(obs.LastActivity, now) {
		// Session is actively processing — its turn will end at the prompt
		// and any queued nudge will be delivered then. Avoid stacking new
		// wake nudges on a busy worker.
		return false
	}
	if !idleRecoveryCooldownAllowsDelivery(sb, obs.LastActivity) {
		return false
	}
	hasWork, err := sessionHasOpenAssignedWorkForReachableStore(cityPath, cfg, store, rigStores, sb)
	if err != nil {
		fmt.Fprintf(stderr, "idle recovery: checking assigned work for %s: %v\n", target.agentKey(), err) //nolint:errcheck
		return false
	}
	if !hasWork {
		return false
	}
	item := newQueuedNudgeWithOptions(
		target.agentKey(),
		idleRecoveryMessage,
		idleRecoverySource,
		now,
		queuedNudgeOptionsFromTarget(target),
	)
	if err := enqueueQueuedNudgeWithStore(cityPath, store, item); err != nil {
		fmt.Fprintf(stderr, "idle recovery: enqueueing wake nudge for %s: %v\n", target.agentKey(), err) //nolint:errcheck
		return false
	}
	if err := store.SetMetadata(sb.ID, idleRecoveryLastDeliveredMetadata, now.UTC().Format(time.RFC3339)); err != nil {
		fmt.Fprintf(stderr, "idle recovery: stamping cooldown for %s: %v\n", target.agentKey(), err) //nolint:errcheck
	}
	return true
}

// sessionBeadEligibleForIdleRecovery reports whether a session bead is in a
// state where idle recovery should consider delivering a wake nudge. Sessions
// that are draining, asleep, or quarantined go through other lifecycle paths
// and must not absorb a wake here.
func sessionBeadEligibleForIdleRecovery(sb beads.Bead) bool {
	if sb.Status == "closed" {
		return false
	}
	state := strings.TrimSpace(sb.Metadata["state"])
	switch sessionpkg.State(state) {
	case "", sessionpkg.StateActive, sessionpkg.StateAwake, sessionpkg.StateCreating:
		// Eligible: alive or expected-to-be-alive bead states.
	default:
		return false
	}
	if strings.TrimSpace(sb.Metadata["sleep_intent"]) != "" {
		// A pending sleep/drain takes precedence — don't fight it.
		return false
	}
	return true
}

// sessionIsAtPrompt reports whether a running session has been quiet long
// enough to be considered at the prompt rather than mid-turn. Providers that
// do not report activity (nil lastActivity) are treated as at the prompt —
// the safer default for the wake path, since the consequence of a stray
// nudge is a duplicate prompt while the consequence of a held nudge is a
// stranded wisp.
func sessionIsAtPrompt(lastActivity *time.Time, now time.Time) bool {
	if lastActivity == nil {
		return true
	}
	return now.Sub(*lastActivity) >= idleRecoveryAtPromptThreshold
}

// idleRecoveryCooldownAllowsDelivery implements the per-session cooldown the
// mayor approved: skip when last_idle_recovery_at is set unless observable
// runtime activity has advanced past it. Activity advancing past the marker
// means the session has acted on the previous nudge — the cooldown has
// "reset on at-prompt transition" as the design note phrases it, just
// derived from the runtime activity timestamp rather than a separate
// last_prompt_ready_at field. (The provider already tracks LastActivity;
// adding a parallel last_prompt_ready_at field would duplicate that signal.)
func idleRecoveryCooldownAllowsDelivery(sb beads.Bead, lastActivity *time.Time) bool {
	last, ok := parseRFC3339Metadata(sb.Metadata[idleRecoveryLastDeliveredMetadata])
	if !ok {
		return true
	}
	if lastActivity == nil {
		// No activity signal available. Be conservative: hold the cooldown
		// until the next lifecycle event clears the marker. Providers that
		// surface activity (tmux, codex, acp) won't take this branch.
		return false
	}
	return lastActivity.After(last)
}
