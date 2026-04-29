package main

import (
	"bytes"
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

// hookStampLine returns a version-stamp comment for hook scripts. The stamp
// embeds the build date and commit so that installBeadHooks can enforce
// forward-only writes — a stale gc binary will not overwrite hooks installed
// by a newer binary.
func hookStampLine() string {
	return fmt.Sprintf("# gc-hook-stamp: %s %s", date, commit)
}

// parseHookStampDate extracts the build date from a hook script's stamp line.
// Returns empty string if no stamp is found.
func parseHookStampDate(content []byte) string {
	for _, line := range bytes.Split(content, []byte("\n")) {
		line = bytes.TrimSpace(line)
		if bytes.HasPrefix(line, []byte("# gc-hook-stamp: ")) {
			parts := bytes.Fields(line)
			if len(parts) >= 3 {
				return string(parts[2])
			}
		}
	}
	return ""
}

// hookScript returns the shell script content for a bd hook that forwards
// events to the Gas City event log via gc event emit.
func hookScript(eventType string) string {
	return fmt.Sprintf(`#!/bin/sh
%s
# Installed by gc — forwards bd events to Gas City event log.
# Args: $1=issue_id  $2=event_type  stdin=issue JSON
GC_BIN="${GC_BIN:-gc}"
DATA=$(cat)
PAYLOAD=$(printf '{"bead":%%s}' "$DATA")
title=$(echo "$DATA" | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
(
  "$GC_BIN" event emit %s --subject "$1" --message "$title" --payload "$PAYLOAD" >/dev/null 2>&1 || true
) </dev/null >/dev/null 2>&1 &
`, hookStampLine(), eventType)
}

// closeHookScript returns the on_close hook script. It forwards the
// bead.closed event, triggers convoy autoclose for the closed bead's
// parent convoy (if any), and auto-closes any open molecule/wisp
// children attached to the closed bead. Workflow-control watches the city
// event stream directly, so the close hook no longer sends a separate poke.
func closeHookScript() string {
	return fmt.Sprintf(`#!/bin/sh
%s
# Installed by gc — forwards bd close events, auto-closes completed convoys,
# and auto-closes orphaned wisps.
# Args: $1=issue_id  $2=event_type  stdin=issue JSON
GC_BIN="${GC_BIN:-gc}"
DATA=$(cat)
PAYLOAD=$(printf '{"bead":%s}' "$DATA")
title=$(echo "$DATA" | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
(
  "$GC_BIN" event emit bead.closed --subject "$1" --message "$title" --payload "$PAYLOAD" >/dev/null 2>&1 || true
  # Auto-close parent convoy if all siblings are now closed.
  "$GC_BIN" convoy autoclose "$1" >/dev/null 2>&1 || true
  # Auto-close open molecule/wisp children so they don't outlive the parent.
  "$GC_BIN" wisp autoclose "$1" >/dev/null 2>&1 || true
) </dev/null >/dev/null 2>&1 &
`, hookStampLine())
}

// installBeadHooks writes bd hook scripts into dir/.beads/hooks/ so that
// bd mutations (create, close, update) emit events to the Gas City event
// log. Forward-only — a stale gc binary will not overwrite hooks installed
// by a newer binary. Returns nil on success.
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

		if existing, err := os.ReadFile(path); err == nil {
			if date != "unknown" {
				onDiskDate := parseHookStampDate(existing)
				if onDiskDate != "" && onDiskDate != "unknown" && date < onDiskDate {
					continue
				}
			}
		}

		if err := fsys.WriteFileIfContentOrModeChangedAtomic(fsys.OSFS{}, path, []byte(content), 0o755); err != nil {
			return fmt.Errorf("writing hook %s: %w", filename, err)
		}
	}
	return nil
}
