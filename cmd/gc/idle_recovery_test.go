package main

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/gastownhall/gascity/internal/beads"
	"github.com/gastownhall/gascity/internal/nudgequeue"
	"github.com/gastownhall/gascity/internal/runtime"
	"github.com/gastownhall/gascity/internal/session"
)

const idleRecoveryTestSessionName = "worker-session"

// idleRecoverySessionBead constructs a session bead in StateActive with the
// metadata fields the idle-recovery path consults.
func idleRecoverySessionBead(t *testing.T, store beads.Store) beads.Bead {
	t.Helper()
	created, err := store.Create(beads.Bead{
		Title:  "Session: " + idleRecoveryTestSessionName,
		Type:   session.BeadType,
		Status: "open",
		Labels: []string{session.LabelSession},
		Metadata: map[string]string{
			"session_name": idleRecoveryTestSessionName,
			"agent_name":   "worker",
			"template":     "worker",
			"transport":    "tmux",
			"state":        string(session.StateActive),
		},
	})
	if err != nil {
		t.Fatalf("store.Create session bead: %v", err)
	}
	return created
}

// TestDispatchIdleRecoveryWakesLiveSessionWithAssignedWork is the core
// regression for gc-b4z1bl: a live session at the prompt with newly-assigned
// work (typical witness/refinery patrol next-iteration self-assignment) must
// receive a wake nudge from the reconciler tick. Without this scan, the
// session sits idle until something else nudges it.
func TestDispatchIdleRecoveryWakesLiveSessionWithAssignedWork(t *testing.T) {
	clearGCEnv(t)
	disableManagedDoltRecoveryForTest(t)
	clearInheritedCityRoutingEnv(t)
	t.Setenv("GC_BEADS", "file")

	dir := t.TempDir()
	store := openNudgeBeadStore(dir)
	if store == nil {
		t.Fatal("openNudgeBeadStore returned nil")
	}

	fake := runtime.NewFake()
	sessionName := idleRecoveryTestSessionName
	if err := fake.Start(context.Background(), sessionName, runtime.Config{}); err != nil {
		t.Fatalf("fake.Start: %v", err)
	}
	// Activity older than now allows the cooldown to be considered "reset"
	// on subsequent passes; for the first pass there is no marker, so any
	// LastActivity value is fine here.
	fake.SetActivity(sessionName, time.Now().Add(-30*time.Second))

	sessionBead := idleRecoverySessionBead(t, store)

	// Assigned, still-open work bead — exactly what witness next-iteration
	// produces when it pours a wisp and self-assigns via bd update.
	if _, err := store.Create(beads.Bead{
		Title:    "Wisp: review patrol",
		Status:   "open",
		Type:     "task",
		Assignee: sessionName,
	}); err != nil {
		t.Fatalf("store.Create work bead: %v", err)
	}

	snapshot, err := loadSessionBeadSnapshot(store)
	if err != nil {
		t.Fatalf("loadSessionBeadSnapshot: %v", err)
	}

	delivered := dispatchIdleRecoveryTick(context.Background(), dir, supervisorCfg(), store, nil, fake, snapshot, time.Now(), nil)
	if delivered != 1 {
		t.Fatalf("dispatchIdleRecoveryTick delivered = %d, want 1 (live session with assigned work must be nudged)", delivered)
	}

	state, err := nudgequeue.LoadState(dir)
	if err != nil {
		t.Fatalf("nudgequeue.LoadState: %v", err)
	}
	if len(state.Pending) != 1 {
		t.Fatalf("pending nudges = %d, want 1; state=%+v", len(state.Pending), state)
	}
	if state.Pending[0].Source != idleRecoverySource {
		t.Fatalf("queued nudge source = %q, want %q", state.Pending[0].Source, idleRecoverySource)
	}
	if !strings.Contains(state.Pending[0].Message, "gc hook") {
		t.Fatalf("queued nudge message = %q, want a `gc hook` prompt", state.Pending[0].Message)
	}

	// Cooldown marker must be stamped on the session bead so subsequent
	// reconciler ticks do not re-fire while the nudge is still being
	// processed.
	got, err := store.Get(sessionBead.ID)
	if err != nil {
		t.Fatalf("store.Get session bead: %v", err)
	}
	if got.Metadata[idleRecoveryLastDeliveredMetadata] == "" {
		t.Fatalf("session bead missing %s marker after delivery", idleRecoveryLastDeliveredMetadata)
	}
}

// TestDispatchIdleRecoverySkipsRunningSessionWithoutWork verifies the
// dispatcher does not spam wake nudges at idle sessions that have nothing to
// do. The witness/refinery patrol loops keep many sessions running between
// pours; firing on every tick would generate a storm.
func TestDispatchIdleRecoverySkipsRunningSessionWithoutWork(t *testing.T) {
	clearGCEnv(t)
	disableManagedDoltRecoveryForTest(t)
	clearInheritedCityRoutingEnv(t)
	t.Setenv("GC_BEADS", "file")

	dir := t.TempDir()
	store := openNudgeBeadStore(dir)
	if store == nil {
		t.Fatal("openNudgeBeadStore returned nil")
	}

	fake := runtime.NewFake()
	sessionName := idleRecoveryTestSessionName
	if err := fake.Start(context.Background(), sessionName, runtime.Config{}); err != nil {
		t.Fatalf("fake.Start: %v", err)
	}
	fake.SetActivity(sessionName, time.Now().Add(-30*time.Second))

	_ = idleRecoverySessionBead(t, store)

	snapshot, err := loadSessionBeadSnapshot(store)
	if err != nil {
		t.Fatalf("loadSessionBeadSnapshot: %v", err)
	}

	delivered := dispatchIdleRecoveryTick(context.Background(), dir, supervisorCfg(), store, nil, fake, snapshot, time.Now(), nil)
	if delivered != 0 {
		t.Fatalf("dispatchIdleRecoveryTick delivered = %d, want 0 (no assigned work)", delivered)
	}
}

// TestDispatchIdleRecoverySkipsStoppedSession verifies the dispatcher does
// not absorb wake delivery for sessions whose runtime is not running. Those
// take the standard !alive wake path in beadReconcileTick.
func TestDispatchIdleRecoverySkipsStoppedSession(t *testing.T) {
	clearGCEnv(t)
	disableManagedDoltRecoveryForTest(t)
	clearInheritedCityRoutingEnv(t)
	t.Setenv("GC_BEADS", "file")

	dir := t.TempDir()
	store := openNudgeBeadStore(dir)
	if store == nil {
		t.Fatal("openNudgeBeadStore returned nil")
	}

	sessionName := idleRecoveryTestSessionName
	sb := idleRecoverySessionBead(t, store)
	if _, err := store.Create(beads.Bead{
		Title:    "Wisp: review patrol",
		Status:   "open",
		Type:     "task",
		Assignee: sessionName,
	}); err != nil {
		t.Fatalf("store.Create work bead: %v", err)
	}

	snapshot, err := loadSessionBeadSnapshot(store)
	if err != nil {
		t.Fatalf("loadSessionBeadSnapshot: %v", err)
	}

	// Fake has no started session, so IsRunning(sessionName) is false.
	delivered := dispatchIdleRecoveryTick(context.Background(), dir, supervisorCfg(), store, nil, runtime.NewFake(), snapshot, time.Now(), nil)
	if delivered != 0 {
		t.Fatalf("dispatchIdleRecoveryTick delivered = %d, want 0 (stopped session must take !alive wake path)", delivered)
	}

	got, err := store.Get(sb.ID)
	if err != nil {
		t.Fatalf("store.Get: %v", err)
	}
	if got.Metadata[idleRecoveryLastDeliveredMetadata] != "" {
		t.Fatalf("cooldown marker set for stopped session; got %q", got.Metadata[idleRecoveryLastDeliveredMetadata])
	}
}

// TestDispatchIdleRecoverySkipsBusySession verifies the at-prompt gate. A
// session whose LastActivity is within the idle threshold is in the middle
// of a turn and must not receive a wake nudge — its turn will return to the
// prompt and the next reconciler tick will re-evaluate. This bounds the
// hot loop the mayor explicitly flagged.
func TestDispatchIdleRecoverySkipsBusySession(t *testing.T) {
	clearGCEnv(t)
	disableManagedDoltRecoveryForTest(t)
	clearInheritedCityRoutingEnv(t)
	t.Setenv("GC_BEADS", "file")

	dir := t.TempDir()
	store := openNudgeBeadStore(dir)
	if store == nil {
		t.Fatal("openNudgeBeadStore returned nil")
	}

	fake := runtime.NewFake()
	sessionName := idleRecoveryTestSessionName
	if err := fake.Start(context.Background(), sessionName, runtime.Config{}); err != nil {
		t.Fatalf("fake.Start: %v", err)
	}
	// Activity just now — session is actively processing.
	fake.SetActivity(sessionName, time.Now())

	_ = idleRecoverySessionBead(t, store)
	if _, err := store.Create(beads.Bead{
		Title:    "Wisp: review patrol",
		Status:   "open",
		Type:     "task",
		Assignee: sessionName,
	}); err != nil {
		t.Fatalf("store.Create work bead: %v", err)
	}
	snapshot, err := loadSessionBeadSnapshot(store)
	if err != nil {
		t.Fatalf("loadSessionBeadSnapshot: %v", err)
	}
	delivered := dispatchIdleRecoveryTick(context.Background(), dir, supervisorCfg(), store, nil, fake, snapshot, time.Now(), nil)
	if delivered != 0 {
		t.Fatalf("dispatchIdleRecoveryTick delivered = %d, want 0 (busy session must wait until at-prompt)", delivered)
	}
}

// TestIdleRecoveryCooldownHoldsUntilActivityAdvances exercises the
// per-session cooldown contract: once we deliver a wake nudge, subsequent
// passes must skip until runtime activity advances past the marker
// (signaling the session has acted on the prior nudge). This bounds the
// hot loop mayor explicitly called out.
func TestIdleRecoveryCooldownHoldsUntilActivityAdvances(t *testing.T) {
	now := time.Now().UTC()

	sb := beads.Bead{
		Metadata: map[string]string{
			idleRecoveryLastDeliveredMetadata: now.Format(time.RFC3339),
		},
	}

	// No activity yet → cooldown holds.
	if idleRecoveryCooldownAllowsDelivery(sb, nil) {
		t.Fatalf("nil LastActivity must hold cooldown to avoid storming sessions whose provider lacks activity reporting")
	}

	// Activity before the marker → cooldown still holds.
	before := now.Add(-time.Second)
	if idleRecoveryCooldownAllowsDelivery(sb, &before) {
		t.Fatalf("activity (%s) older than marker (%s) must hold cooldown", before, now)
	}

	// Activity strictly newer than the marker → cooldown resets.
	after := now.Add(time.Second)
	if !idleRecoveryCooldownAllowsDelivery(sb, &after) {
		t.Fatalf("activity (%s) newer than marker (%s) must allow next delivery", after, now)
	}
}

// TestSessionBeadEligibleForIdleRecovery covers the lifecycle filter: only
// active/awake/creating session beads with no pending sleep intent are
// eligible. Draining/asleep/quarantined sessions go through other paths.
func TestSessionBeadEligibleForIdleRecovery(t *testing.T) {
	cases := []struct {
		name   string
		status string
		state  string
		intent string
		want   bool
	}{
		{name: "active no intent", state: string(session.StateActive), want: true},
		{name: "awake no intent", state: string(session.StateAwake), want: true},
		{name: "creating no intent", state: string(session.StateCreating), want: true},
		{name: "empty state treated as active", state: "", want: true},
		{name: "closed bead", status: "closed", state: string(session.StateActive), want: false},
		{name: "draining", state: string(session.StateDraining), want: false},
		{name: "asleep", state: string(session.StateAsleep), want: false},
		{name: "quarantined", state: string(session.StateQuarantined), want: false},
		{name: "suspended", state: string(session.StateSuspended), want: false},
		{name: "active with pending idle-stop", state: string(session.StateActive), intent: "idle-stop-pending", want: false},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			sb := beads.Bead{
				Status: tc.status,
				Metadata: map[string]string{
					"state":        tc.state,
					"sleep_intent": tc.intent,
				},
			}
			if got := sessionBeadEligibleForIdleRecovery(sb); got != tc.want {
				t.Fatalf("sessionBeadEligibleForIdleRecovery = %v, want %v", got, tc.want)
			}
		})
	}
}
