#!/usr/bin/env bash
# verified-sling.sh — validate a bead exists before slinging it.
#
# Usage: verified-sling.sh <target> <bead-id> [extra gc-sling flags...]
#
# Wraps `gc sling` with a pre-flight check: the bead must resolve via
# `bd show` before the sling executes. Exits non-zero with a clear error
# if the bead is missing, preventing molecules with dead references.
#
# Created to prevent quartermaster template-substitution bugs where an AI
# agent fabricates bead IDs instead of creating them (hq-7zv).

set -euo pipefail

target="${1:?Usage: verified-sling.sh <target> <bead-id> [flags...]}"
bead_id="${2:?Usage: verified-sling.sh <target> <bead-id> [flags...]}"
shift 2

if ! bd show "$bead_id" --json >/dev/null 2>&1; then
    echo "FATAL: bead '$bead_id' does not exist. Refusing to sling a dead reference." >&2
    echo "The bead must be created with 'gc bd create' (or 'bd create') BEFORE slinging." >&2
    echo "If you just ran bd create, verify the output contained a valid ID." >&2
    exit 1
fi

exec gc sling "$target" "$bead_id" "$@"
