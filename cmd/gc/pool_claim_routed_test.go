package main

import (
	"bytes"
	"testing"

	"github.com/gastownhall/gascity/internal/beads"
	"github.com/gastownhall/gascity/internal/config"
)

func activeSessionBead(id, template, sessionName string) beads.Bead {
	return beads.Bead{
		ID:     id,
		Status: "open",
		Type:   "session",
		Labels: []string{"gc:session"},
		Metadata: map[string]string{
			"template":     template,
			"session_name": sessionName,
			"state":        "active",
		},
	}
}

func asleepSessionBead(id, template, sessionName string) beads.Bead {
	b := activeSessionBead(id, template, sessionName)
	b.Metadata["state"] = "asleep"
	return b
}

func routedWorkBead(id, routedTo string, priority int) beads.Bead {
	p := priority
	return beads.Bead{
		ID:       id,
		Status:   "open",
		Type:     "task",
		Priority: &p,
		Metadata: map[string]string{"gc.routed_to": routedTo},
	}
}

func TestClaimRoutedWork_AssignsToIdleActiveSession(t *testing.T) {
	store := beads.NewMemStore()
	wb, _ := store.Create(beads.Bead{
		Title:    "routed work",
		Status:   "open",
		Type:     "task",
		Metadata: map[string]string{"gc.routed_to": "rig/worker"},
	})

	cfg := &config.City{
		Agents: []config.Agent{poolAgent("worker", "rig", nil, 1)},
	}
	sessions := []beads.Bead{
		activeSessionBead("sess-1", "rig/worker", "city--worker-1"),
	}
	var stderr bytes.Buffer

	n := claimRoutedWorkForIdleSessions(cfg, []beads.Store{store}, sessions, nil, &stderr)

	if n != 1 {
		t.Fatalf("claimed = %d, want 1", n)
	}
	got, err := store.Get(wb.ID)
	if err != nil {
		t.Fatalf("Get(%s): %v", wb.ID, err)
	}
	if got.Assignee != "sess-1" {
		t.Errorf("Assignee = %q, want %q", got.Assignee, "sess-1")
	}
}

func TestClaimRoutedWork_SkipsSessionsWithAssignedWork(t *testing.T) {
	store := beads.NewMemStore()
	wb, _ := store.Create(beads.Bead{
		Title:    "routed work",
		Status:   "open",
		Type:     "task",
		Metadata: map[string]string{"gc.routed_to": "rig/worker"},
	})

	cfg := &config.City{
		Agents: []config.Agent{poolAgent("worker", "rig", nil, 1)},
	}
	sessions := []beads.Bead{
		activeSessionBead("sess-1", "rig/worker", "city--worker-1"),
	}
	existingWork := []beads.Bead{
		workBead("existing-work", "rig/worker", "sess-1", "in_progress", 2),
	}
	var stderr bytes.Buffer

	n := claimRoutedWorkForIdleSessions(cfg, []beads.Store{store}, sessions, existingWork, &stderr)

	if n != 0 {
		t.Fatalf("claimed = %d, want 0 (session has work)", n)
	}
	got, _ := store.Get(wb.ID)
	if got.Assignee != "" {
		t.Errorf("Assignee = %q, want empty", got.Assignee)
	}
}

func TestClaimRoutedWork_SkipsAsleepSessions(t *testing.T) {
	store := beads.NewMemStore()
	store.Create(beads.Bead{
		Title:    "routed work",
		Status:   "open",
		Type:     "task",
		Metadata: map[string]string{"gc.routed_to": "rig/worker"},
	})

	cfg := &config.City{
		Agents: []config.Agent{poolAgent("worker", "rig", nil, 1)},
	}
	sessions := []beads.Bead{
		asleepSessionBead("sess-1", "rig/worker", "city--worker-1"),
	}
	var stderr bytes.Buffer

	n := claimRoutedWorkForIdleSessions(cfg, []beads.Store{store}, sessions, nil, &stderr)

	if n != 0 {
		t.Fatalf("claimed = %d, want 0 (session asleep)", n)
	}
}

func TestClaimRoutedWork_SkipsAlreadyAssignedBeads(t *testing.T) {
	store := beads.NewMemStore()
	store.Create(beads.Bead{
		Title:    "already assigned",
		Status:   "open",
		Type:     "task",
		Assignee: "someone-else",
		Metadata: map[string]string{"gc.routed_to": "rig/worker"},
	})

	cfg := &config.City{
		Agents: []config.Agent{poolAgent("worker", "rig", nil, 1)},
	}
	sessions := []beads.Bead{
		activeSessionBead("sess-1", "rig/worker", "city--worker-1"),
	}
	var stderr bytes.Buffer

	n := claimRoutedWorkForIdleSessions(cfg, []beads.Store{store}, sessions, nil, &stderr)

	if n != 0 {
		t.Fatalf("claimed = %d, want 0 (bead already assigned)", n)
	}
}

func TestClaimRoutedWork_MultipleBeadsMultipleSessions(t *testing.T) {
	store := beads.NewMemStore()
	wb1, _ := store.Create(beads.Bead{
		Title:    "routed work 1",
		Status:   "open",
		Type:     "task",
		Metadata: map[string]string{"gc.routed_to": "rig/worker"},
	})
	wb2, _ := store.Create(beads.Bead{
		Title:    "routed work 2",
		Status:   "open",
		Type:     "task",
		Metadata: map[string]string{"gc.routed_to": "rig/worker"},
	})

	cfg := &config.City{
		Agents: []config.Agent{poolAgent("worker", "rig", nil, 2)},
	}
	sessions := []beads.Bead{
		activeSessionBead("sess-1", "rig/worker", "city--worker-1"),
		activeSessionBead("sess-2", "rig/worker", "city--worker-2"),
	}
	var stderr bytes.Buffer

	n := claimRoutedWorkForIdleSessions(cfg, []beads.Store{store}, sessions, nil, &stderr)

	if n != 2 {
		t.Fatalf("claimed = %d, want 2", n)
	}
	got1, _ := store.Get(wb1.ID)
	got2, _ := store.Get(wb2.ID)
	assignees := map[string]bool{got1.Assignee: true, got2.Assignee: true}
	if !assignees["sess-1"] || !assignees["sess-2"] {
		t.Errorf("expected both sess-1 and sess-2 assigned, got %q and %q", got1.Assignee, got2.Assignee)
	}
}

func TestClaimRoutedWork_MoreBeadsThanSessions(t *testing.T) {
	store := beads.NewMemStore()
	wb1, _ := store.Create(beads.Bead{
		Title:    "routed work 1",
		Status:   "open",
		Type:     "task",
		Metadata: map[string]string{"gc.routed_to": "rig/worker"},
	})
	store.Create(beads.Bead{
		Title:    "routed work 2",
		Status:   "open",
		Type:     "task",
		Metadata: map[string]string{"gc.routed_to": "rig/worker"},
	})

	cfg := &config.City{
		Agents: []config.Agent{poolAgent("worker", "rig", nil, 1)},
	}
	sessions := []beads.Bead{
		activeSessionBead("sess-1", "rig/worker", "city--worker-1"),
	}
	var stderr bytes.Buffer

	n := claimRoutedWorkForIdleSessions(cfg, []beads.Store{store}, sessions, nil, &stderr)

	if n != 1 {
		t.Fatalf("claimed = %d, want 1 (only 1 idle session)", n)
	}
	got, _ := store.Get(wb1.ID)
	if got.Assignee != "sess-1" {
		t.Errorf("Assignee = %q, want %q", got.Assignee, "sess-1")
	}
}

func TestClaimRoutedWork_SkipsNamedSessions(t *testing.T) {
	store := beads.NewMemStore()
	store.Create(beads.Bead{
		Title:    "routed work",
		Status:   "open",
		Type:     "task",
		Metadata: map[string]string{"gc.routed_to": "rig/worker"},
	})

	cfg := &config.City{
		Agents: []config.Agent{poolAgent("worker", "rig", nil, 1)},
	}
	named := activeSessionBead("sess-1", "rig/worker", "city--worker-1")
	named.Metadata["configured_named_session"] = "true"
	sessions := []beads.Bead{named}
	var stderr bytes.Buffer

	n := claimRoutedWorkForIdleSessions(cfg, []beads.Store{store}, sessions, nil, &stderr)

	if n != 0 {
		t.Fatalf("claimed = %d, want 0 (named session excluded)", n)
	}
}

func TestClaimRoutedWork_SkipsDrainedSessions(t *testing.T) {
	store := beads.NewMemStore()
	store.Create(beads.Bead{
		Title:    "routed work",
		Status:   "open",
		Type:     "task",
		Metadata: map[string]string{"gc.routed_to": "rig/worker"},
	})

	cfg := &config.City{
		Agents: []config.Agent{poolAgent("worker", "rig", nil, 1)},
	}
	drained := activeSessionBead("sess-1", "rig/worker", "city--worker-1")
	drained.Metadata["state"] = "drained"
	sessions := []beads.Bead{drained}
	var stderr bytes.Buffer

	n := claimRoutedWorkForIdleSessions(cfg, []beads.Store{store}, sessions, nil, &stderr)

	if n != 0 {
		t.Fatalf("claimed = %d, want 0 (drained session excluded)", n)
	}
}

func TestClaimRoutedWork_NilStoresOrConfig(t *testing.T) {
	var stderr bytes.Buffer

	if n := claimRoutedWorkForIdleSessions(nil, nil, nil, nil, &stderr); n != 0 {
		t.Errorf("nil cfg: claimed = %d, want 0", n)
	}
	cfg := &config.City{
		Agents: []config.Agent{poolAgent("worker", "rig", nil, 1)},
	}
	if n := claimRoutedWorkForIdleSessions(cfg, nil, nil, nil, &stderr); n != 0 {
		t.Errorf("nil stores: claimed = %d, want 0", n)
	}
}

func TestClaimRoutedWork_SkipsClosedWorkBeads(t *testing.T) {
	store := beads.NewMemStore()
	wb, _ := store.Create(beads.Bead{
		Title:    "closed routed work",
		Status:   "open",
		Type:     "task",
		Metadata: map[string]string{"gc.routed_to": "rig/worker"},
	})
	store.Close(wb.ID)

	cfg := &config.City{
		Agents: []config.Agent{poolAgent("worker", "rig", nil, 1)},
	}
	sessions := []beads.Bead{
		activeSessionBead("sess-1", "rig/worker", "city--worker-1"),
	}
	var stderr bytes.Buffer

	n := claimRoutedWorkForIdleSessions(cfg, []beads.Store{store}, sessions, nil, &stderr)

	if n != 0 {
		t.Fatalf("claimed = %d, want 0 (work bead is closed)", n)
	}
}
