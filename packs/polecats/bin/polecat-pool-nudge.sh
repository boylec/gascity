#!/bin/bash
# polecat-pool-nudge.sh — overnight duct tape for autonomous bead drain.
#
# Nudges every active polecat session to run `gc hook` so it picks up its
# next routed bead. Polecats don't auto-poll today; when they finish a
# bead they go idle and sit forever. This script (invoked every few
# minutes via orders/polecat-pool-nudge.toml) keeps them pulling work
# until the gc-grn / gc-o0ys fixes land in the daemon.
#
# Cheap & idempotent: nudge delivery mode is wait-idle, so it never
# interrupts a polecat that's actively working a bead.

set -eu

# Select active sessions of any polecat-ish template. Bail if none.
SESSIONS=$(gc session list --json 2>/dev/null \
  | jq -r '.[]
    | select(.State == "active")
    | select((.Template // "") | test("(^|/)polecats\\.|(^|/)gastown\\.polecat$"))
    | .ID')

if [ -z "$SESSIONS" ]; then
  echo "polecat-pool-nudge: no active polecat sessions"
  exit 0
fi

COUNT=0
for id in $SESSIONS; do
  gc session nudge "$id" "Run gc hook — pull the next routed bead. If no work: drain-ack and return to pool." \
    --delivery wait-idle >/dev/null 2>&1 || true
  COUNT=$((COUNT + 1))
done
echo "polecat-pool-nudge: nudged $COUNT session(s)"
