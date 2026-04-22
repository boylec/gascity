#!/bin/bash
# polecat-pool-nudge.sh — overnight duct tape for autonomous bead drain.
#
# Covers pooled agents (polecats + quartermasters + furiosa-named polecats).
# Witness handles *dead* agents with orphan worktrees. This script fills
# three gaps witness doesn't address:
#
# (0) Pool-demand spawn: if beads are routed to a template but no session
#     of that template exists (active/asleep/creating), spawn one. The
#     reconciler's min_active_sessions only guarantees a floor — it doesn't
#     auto-scale on route demand, and pools that got killed won't respawn
#     until something triggers them.
#
# (1) Idle drain: nudge active + asleep pool sessions so they run
#     `gc hook` and pull the next routed bead. Pool sessions don't
#     auto-poll today (gc-grn bug); without external nudging they go
#     idle after each bead and sit forever.
#
# (2) Session-liveness salvage: for each in_progress bead whose
#     updated_at is older than STALE_MIN minutes:
#       - assignee session is `active` → hung probe (nudge "are you stuck?")
#       - assignee session is closed/asleep/absent → unassign + reopen
#     Witness's orphan-recovery check matches by template PATTERN, so it
#     misses cases where a specific session ID is dead but the pool's
#     next instance has a different ID. See gc-m7qm in the gascity fork.
#
# Nudge delivery is wait-idle so busy workers aren't interrupted mid-work.
# All nudges are idempotent.

set -eu

STALE_MIN="${STALE_MIN:-20}"
NOW_EPOCH=$(date +%s)
STALE_CUTOFF=$((NOW_EPOCH - STALE_MIN * 60))

# Templates that are city-scoped (spawned bare, no rig prefix).
CITY_SCOPED_RE='^(quartermaster|dog)$'

# Resolve a gc.routed_to value + originating rig to a spawnable template name.
#   "enterprise/polecats.sonnet" (already prefixed) → "enterprise/polecats.sonnet"
#   "polecats.sonnet" in rig=enterprise            → "enterprise/polecats.sonnet"
#   "quartermaster" (city-scoped)                  → "quartermaster"
resolve_template() {
  local route="$1"
  local rig="$2"
  case "$route" in
    */*)                  printf '%s' "$route" ;;       # already rig-prefixed
    "")                   return 1 ;;
    *)
      if printf '%s' "$route" | grep -qE "$CITY_SCOPED_RE"; then
        printf '%s' "$route"
      else
        printf '%s/%s' "$rig" "$route"
      fi
      ;;
  esac
}

# ---------- Pass 0: spawn pools that have routed work but no session ------

spawn_for_rig() {
  local rig_flag="$1"
  local rig_label="$2"
  local rows
  rows=$(gc bd $rig_flag list --limit 0 --json 2>/dev/null \
    | jq -r '.[] | select(.status == "open" or .status == "in_progress") | .metadata["gc.routed_to"] // empty' \
    | sort -u)
  [ -z "$rows" ] && return

  local sessions_json
  sessions_json=$(gc session list --state=all --json 2>/dev/null)

  local spawned=0
  for route in $rows; do
    local template
    template=$(resolve_template "$route" "$rig_label") || continue

    # Is there any non-closed session of this template?
    local have
    have=$(printf '%s' "$sessions_json" \
      | jq -r --arg t "$template" '[.[] | select(.Template == $t) | select(.State != "closed")] | length')
    [ "$have" -gt 0 ] && continue

    echo "polecat-pool-nudge: pass0 spawning $template (no live session, beads routed to it in rig=${rig_label})"
    gc session new "$template" --no-attach >/dev/null 2>&1 || echo "polecat-pool-nudge: pass0 spawn failed for $template"
    spawned=$((spawned + 1))
  done
  [ "$spawned" -gt 0 ] && echo "polecat-pool-nudge: pass0 rig=${rig_label} spawned ${spawned} template(s)"
}

spawn_for_rig "" "hq"
spawn_for_rig "--rig enterprise" "enterprise"

# ---------- Pass 1: nudge idle polecats to drain routed queue -------------

# Include both active and asleep pool sessions. Asleep sessions need
# waking to pull new work. Skip "creating" and "closed" — not reachable.
# Pool templates covered:
#   polecats.*               — sc implementation polecats
#   gastown.polecat          — rig-scoped base polecat (furiosa etc.)
#   quartermaster            — city-scoped planning coordinators
IDLE_SESSIONS=$(gc session list --state=all --json 2>/dev/null \
  | jq -r '.[]
    | select(.State == "active" or .State == "asleep")
    | select((.Template // "") | test("(^|/)polecats\\.|(^|/)gastown\\.polecat$|^quartermaster$"))
    | "\(.ID)\t\(.State)"')

IDLE_COUNT=0
while IFS=$'\t' read -r id state; do
  [ -z "$id" ] && continue
  # Wake asleep sessions first so the nudge actually lands.
  if [ "$state" = "asleep" ]; then
    gc session wake "$id" >/dev/null 2>&1 || true
  fi
  gc session nudge "$id" "Run gc hook — pull the next routed bead. If no work: drain-ack and return to pool." \
    --delivery wait-idle >/dev/null 2>&1 || true
  IDLE_COUNT=$((IDLE_COUNT + 1))
done <<< "$IDLE_SESSIONS"
echo "polecat-pool-nudge: pass1 nudged ${IDLE_COUNT} session(s)"

# ---------- Pass 2: probe hung sessions (in-progress beads gone stale) ----

probe_rig() {
  local rig_flag="$1"
  local rig_label="$2"

  # Use `gc bd` (wraps bd with --rig handling); bare `bd` doesn't accept --rig.
  local rows
  rows=$(gc bd $rig_flag list --status=in_progress --limit 0 --json 2>/dev/null \
    | jq -r '.[] | select(.assignee != null and .assignee != "") | "\(.id)\t\(.updated_at)\t\(.assignee)"' \
    2>/dev/null || true)

  [ -z "$rows" ] && { echo "polecat-pool-nudge: pass2 rig=${rig_label} no in_progress beads"; return; }

  local hung=0
  while IFS=$'\t' read -r bead_id updated_at assignee; do
    [ -z "$bead_id" ] && continue

    local updated_epoch
    updated_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${updated_at%%.*}Z" "+%s" 2>/dev/null || echo 0)
    [ "$updated_epoch" -eq 0 ] && continue
    [ "$updated_epoch" -ge "$STALE_CUTOFF" ] && continue

    # Assignee formats vary: "polecats__sonnet-hq-n7iy6", "polecat-hq-00ohd",
    # "s-hq-7k4g", or bare "hq-xxxx". Extract the hq-<id> portion.
    local session_guess
    session_guess=$(printf '%s' "$assignee" | grep -oE '(hq|sc|gc|de)-[a-z0-9]+' | tail -1)
    [ -z "$session_guess" ] && continue

    local state
    state=$(gc session list --state=all --json 2>/dev/null \
      | jq -r --arg id "$session_guess" '.[] | select(.ID == $id) | .State' 2>/dev/null | head -1)
    local age_min=$(( ( NOW_EPOCH - updated_epoch ) / 60 ))

    if [ "$state" = "active" ]; then
      # Session alive but bead stale — hung probe (nudge, don't act destructively).
      gc session nudge "$session_guess" "Status probe: your assigned bead ${bead_id} hasn't been touched in ${STALE_MIN}+ minutes. If making progress, continue. If stuck: escalate per the polecat prompt (set bead to blocked, mail witness), then gc runtime drain-ack && exit. Don't silently hang." \
        --delivery wait-idle >/dev/null 2>&1 || true
      echo "polecat-pool-nudge: hung-probe rig=${rig_label} bead=${bead_id} session=${session_guess} age=${age_min}m"
      hung=$((hung + 1))
    else
      # Assignee session is gone (closed / asleep / never-existed). Bead is
      # orphaned — unassign + reopen so the next polecat can claim it.
      # This is the dead-agent salvage that witness patrol doesn't currently
      # do for in_progress work.
      gc bd $rig_flag update "$bead_id" --assignee="" --status=open >/dev/null 2>&1 || true
      echo "polecat-pool-nudge: dead-salvage rig=${rig_label} bead=${bead_id} was=${session_guess} state=${state:-gone} age=${age_min}m → reopened"
      hung=$((hung + 1))
    fi
  done <<< "$rows"

  echo "polecat-pool-nudge: pass2 rig=${rig_label} probed ${hung} hung session(s)"
}

probe_rig "" "hq"
probe_rig "--rig enterprise" "enterprise"
