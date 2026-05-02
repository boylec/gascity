package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/gastownhall/gascity/internal/fsys"
)

// beadHooks maps bd hook filenames to the Gas City event types they emit.
var beadHooks = map[string]string{
	"on_create": "bead.created",
	"on_close":  "bead.closed",
	"on_update": "bead.updated",
}

// hookScript returns the shell script content for a bd hook that forwards
// events to the Gas City event log via gc event emit. Failures are
// captured to ${BEADS_DIR}/hooks.log so silent breakage (missing gc on
// PATH, store-resolution errors) is diagnosable after the fact.
func hookScript(eventType string) string {
	return fmt.Sprintf(`#!/bin/sh
# Installed by gc — forwards bd events to Gas City event log.
# Args: $1=issue_id  $2=event_type  stdin=issue JSON
GC_BIN="${GC_BIN:-gc}"
HOOK_LOG="${BEADS_DIR:-.beads}/hooks.log"
DATA=$(cat)
PAYLOAD=$(printf '{"bead":%%s}' "$DATA")
title=$(echo "$DATA" | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
(
  "$GC_BIN" event emit %[1]s --subject "$1" --message "$title" --payload "$PAYLOAD" 2>>"$HOOK_LOG" \
    || echo "[$(date -u +%%FT%%TZ)] %[2]s $1: gc event emit %[1]s failed (gc=$GC_BIN)" >>"$HOOK_LOG" 2>/dev/null \
    || true
) </dev/null >/dev/null 2>&1 &
`, eventType, hookNameFromEventType(eventType))
}

// hookNameFromEventType maps event types back to the hook filename
// (e.g. "bead.created" → "on_create") so diagnostic log lines name the
// hook the operator can grep for.
func hookNameFromEventType(eventType string) string {
	for hook, evt := range beadHooks {
		if evt == eventType {
			return hook
		}
	}
	return "hook"
}

// closeHookScript returns the on_close hook script. It forwards the
// bead.closed event, triggers convoy autoclose for the closed bead's
// parent convoy (if any), and auto-closes any open molecule/wisp
// children attached to the closed bead. Workflow-control watches the city
// event stream directly, so the close hook no longer sends a separate poke.
//
// Failures of any of the three gc invocations are logged with a dated
// diagnostic line to ${BEADS_DIR}/hooks.log. Without this, missing gc
// or a store-resolution error here leaves no record at all and the
// cascade-close of sling scaffolding fails invisibly.
func closeHookScript() string {
	return `#!/bin/sh
# Installed by gc — forwards bd close events, auto-closes completed convoys,
# and auto-closes orphaned wisps.
# Args: $1=issue_id  $2=event_type  stdin=issue JSON
GC_BIN="${GC_BIN:-gc}"
HOOK_LOG="${BEADS_DIR:-.beads}/hooks.log"
DATA=$(cat)
PAYLOAD=$(printf '{"bead":%s}' "$DATA")
title=$(echo "$DATA" | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
(
  "$GC_BIN" event emit bead.closed --subject "$1" --message "$title" --payload "$PAYLOAD" 2>>"$HOOK_LOG" \
    || echo "[$(date -u +%FT%TZ)] on_close $1: gc event emit bead.closed failed (gc=$GC_BIN)" >>"$HOOK_LOG" 2>/dev/null \
    || true
  # Auto-close parent convoy if all siblings are now closed.
  "$GC_BIN" convoy autoclose "$1" 2>>"$HOOK_LOG" \
    || echo "[$(date -u +%FT%TZ)] on_close $1: gc convoy autoclose failed (gc=$GC_BIN)" >>"$HOOK_LOG" 2>/dev/null \
    || true
  # Auto-close open molecule/wisp children so they don't outlive the parent.
  "$GC_BIN" wisp autoclose "$1" 2>>"$HOOK_LOG" \
    || echo "[$(date -u +%FT%TZ)] on_close $1: gc wisp autoclose failed (gc=$GC_BIN)" >>"$HOOK_LOG" 2>/dev/null \
    || true
) </dev/null >/dev/null 2>&1 &
`
}

// installBeadHooks writes bd hook scripts into dir/.beads/hooks/ so that
// bd mutations (create, close, update) emit events to the Gas City event
// log. Idempotent — leaves matching hooks in place. Returns nil on success.
func installBeadHooks(dir string) error {
	hooksDir := filepath.Join(dir, ".beads", "hooks")
	if err := os.MkdirAll(hooksDir, 0o755); err != nil {
		return fmt.Errorf("creating hooks directory: %w", err)
	}

	for filename, eventType := range beadHooks {
		path := filepath.Join(hooksDir, filename)
		content := hookScript(eventType)
		if filename == "on_close" {
			content = closeHookScript()
		}
		if err := fsys.WriteFileIfContentOrModeChangedAtomic(fsys.OSFS{}, path, []byte(content), 0o755); err != nil {
			return fmt.Errorf("writing hook %s: %w", filename, err)
		}
	}
	return nil
}
