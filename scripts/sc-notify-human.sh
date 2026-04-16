#!/usr/bin/env bash
# sc-notify-human.sh — multi-channel notification for SafetyChain flow gates.
#
# Usage: sc-notify-human.sh "<subject>" "<body>"
#
# Best-effort across all channels. Never fails the caller. Missing tools /
# unauthenticated services / detached tmux are all skipped silently.
#
# Channels (in order):
#   1. gc mail send human — audit trail in the Gas City human inbox
#   2. macOS osascript banner — desktop notification when at the Mac
#   3. Outbound webhook — optional, user-configured via $SC_NOTIFY_WEBHOOK
#      (Slack incoming-webhook, ntfy.sh topic URL, Pushover, etc; JSON POST
#      of {subject, body}). Recommended: https://ntfy.sh/<secret-topic>
#   4. tmux bell — audible nudge if Casey is attached to a tmux session
#
# When Gas City ships first-class `--human` notification (tracked upstream
# in examples/gastown/FUTURE.md), swap this helper's body without touching
# any formulas.

set -euo pipefail

subject="${1:?subject required}"
body="${2:?body required}"

# 1. Inbox trail — audit + catchup for all other channels
gc mail send human -s "$subject" -m "$body" >/dev/null 2>&1 || true

# 2. macOS banner
if command -v osascript >/dev/null 2>&1; then
    snippet=$(printf '%s' "$body" | tr '\n' ' ' | head -c 200)
    osascript \
        -e "display notification \"${snippet//\"/\\\"}\" with title \"SafetyChain Gas City\" subtitle \"${subject//\"/\\\"}\"" \
        >/dev/null 2>&1 || true
fi

# 3. Optional outbound webhook — payload shape selected by URL host.
#    Set SC_NOTIFY_DEBUG=1 to surface curl errors on stderr.
if [ -n "${SC_NOTIFY_WEBHOOK:-}" ] && command -v curl >/dev/null 2>&1; then
    dbg=${SC_NOTIFY_DEBUG:-}
    errlog=/dev/null
    [ -n "$dbg" ] && errlog=/dev/stderr

    case "$SC_NOTIFY_WEBHOOK" in
        *ntfy.sh/*|*ntfy.*/*)
            # ntfy.sh native shape: raw body + Title/Priority headers.
            # https://docs.ntfy.sh/publish/
            curl -fsS -m 5 \
                -H "Title: $subject" \
                -H "Priority: default" \
                -d "$body" \
                "$SC_NOTIFY_WEBHOOK" \
                >"$errlog" 2>&1 || true
            ;;

        *hooks.slack.com/*)
            # Slack incoming webhook: JSON with "text" field.
            if command -v jq >/dev/null 2>&1; then
                payload=$(jq -n --arg t "$subject" --arg b "$body" \
                    '{text: ("*" + $t + "*\n" + $b)}')
            else
                payload=$(printf '{"text":"*%s*\\n%s"}' \
                    "${subject//\"/\\\"}" "${body//\"/\\\"}")
            fi
            curl -fsS -m 5 -X POST \
                -H 'Content-Type: application/json' \
                --data "$payload" \
                "$SC_NOTIFY_WEBHOOK" \
                >"$errlog" 2>&1 || true
            ;;

        *)
            # Generic JSON fallback: {subject, body}. Works for homegrown
            # endpoints; will not satisfy most SaaS without adaptation.
            if command -v jq >/dev/null 2>&1; then
                payload=$(jq -n --arg s "$subject" --arg b "$body" \
                    '{subject:$s, body:$b}')
            else
                payload=$(printf '{"subject":"%s","body":"%s"}' \
                    "${subject//\"/\\\"}" "${body//\"/\\\"}")
            fi
            curl -fsS -m 5 -X POST \
                -H 'Content-Type: application/json' \
                --data "$payload" \
                "$SC_NOTIFY_WEBHOOK" \
                >"$errlog" 2>&1 || true
            ;;
    esac
fi

# 4. tmux bell when attached
if [ -n "${TMUX:-}" ]; then
    printf '\a' >&2
fi

exit 0
