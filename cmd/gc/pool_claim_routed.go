package main

import (
	"fmt"
	"io"
	"strings"

	"github.com/gastownhall/gascity/internal/beads"
	"github.com/gastownhall/gascity/internal/config"
)

// claimRoutedWorkForIdleSessions assigns routed-but-unassigned work beads to
// active idle pool sessions. For each pool agent template, it queries stores
// for open beads with gc.routed_to matching the template but no assignee,
// then assigns each to an active session that has no currently assigned work.
//
// This bridges the gap where scale_check/min_active_sessions keeps a session
// alive but the session's hook only discovers assigned work. Without this,
// routed work sits unclaimed even though an idle session exists.
//
// Returns the number of assignments made.
func claimRoutedWorkForIdleSessions(
	cfg *config.City,
	stores []beads.Store,
	sessionBeads []beads.Bead,
	assignedWorkBeads []beads.Bead,
	stderr io.Writer,
) int {
	if cfg == nil || len(stores) == 0 {
		return 0
	}
	if stderr == nil {
		stderr = io.Discard
	}

	// Build set of session bead IDs that already have assigned work.
	busySessions := make(map[string]bool, len(assignedWorkBeads))
	for _, wb := range assignedWorkBeads {
		assignee := strings.TrimSpace(wb.Assignee)
		if assignee != "" {
			busySessions[assignee] = true
		}
	}

	// For each pool template, collect idle active sessions.
	type idleSession struct {
		beadID      string
		sessionName string
	}
	idleByTemplate := make(map[string][]idleSession)

	for _, sb := range sessionBeads {
		if sb.Status == "closed" {
			continue
		}
		if sb.Metadata["state"] != "active" {
			continue
		}
		if isDrainedSessionBead(sb) {
			continue
		}
		if isNamedSessionBead(sb) {
			continue
		}
		if isManualSessionBead(sb) {
			continue
		}
		if busySessions[sb.ID] {
			continue
		}
		template := strings.TrimSpace(sb.Metadata["template"])
		if template == "" {
			continue
		}
		agent := findAgentByTemplate(cfg, template)
		if agent == nil || agent.Suspended {
			continue
		}
		if !agent.SupportsGenericEphemeralSessions() {
			continue
		}
		idleByTemplate[template] = append(idleByTemplate[template], idleSession{
			beadID:      sb.ID,
			sessionName: strings.TrimSpace(sb.Metadata["session_name"]),
		})
	}

	if len(idleByTemplate) == 0 {
		return 0
	}

	claimed := 0
	for _, s := range stores {
		if s == nil {
			continue
		}
		for template, idle := range idleByTemplate {
			if len(idle) == 0 {
				continue
			}
			routed, err := s.List(beads.ListQuery{
				Status:   "open",
				Metadata: map[string]string{"gc.routed_to": template},
			})
			if err != nil {
				fmt.Fprintf(stderr, "claimRoutedWork: listing routed beads for %s: %v\n", template, err) //nolint:errcheck
				continue
			}
			for _, wb := range routed {
				if len(idle) == 0 {
					break
				}
				if strings.TrimSpace(wb.Assignee) != "" {
					continue
				}
				if beads.IsReadyExcludedType(wb.Type) {
					continue
				}
				target := idle[0]
				idle = idle[1:]
				idleByTemplate[template] = idle

				assignee := target.beadID
				if err := s.Update(wb.ID, beads.UpdateOpts{Assignee: &assignee}); err != nil {
					fmt.Fprintf(stderr, "claimRoutedWork: assigning %s to %s: %v\n", wb.ID, assignee, err) //nolint:errcheck
					continue
				}
				fmt.Fprintf(stderr, "claimRoutedWork: assigned %s → %s (%s)\n", wb.ID, target.sessionName, template) //nolint:errcheck
				claimed++
			}
		}
	}
	return claimed
}
