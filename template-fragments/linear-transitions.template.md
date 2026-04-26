{{ define "linear-transitions" }}
## Linear State Transitions

When a bead is linked to a Linear issue, keep Linear's state in sync with the
bead's lifecycle. The `linear-server` MCP tool `save_issue` accepts `state`
by name — pass `"In Progress"` or `"In Review"` directly, no state-ID lookup.

### Detect the link

A bead is Linear-linked when either:

- `bd show --long <BEAD>` displays an `External:` line of the form
  `linear-SAF-XX` (set by `mol-sc-idea-to-plan` via `--external-ref`).
- `metadata.linear_id` is set on the bead (also stamped by
  `mol-sc-idea-to-plan`; inherited by every child task bead in the convoy).

Either source resolves to a Linear issue identifier like `SAF-123`. If
neither is present, this fragment does not apply — proceed without
transitioning.

```bash
LINEAR_ID=$(bd show "$BEAD" --json | jq -r '
  .[0].external_ref // (.[0].metadata.linear_id // empty)
' | sed 's/^linear-//')
```

### Transition: claim → "In Progress"

The moment you claim a Linear-linked bead — same step that runs
`bd update --claim` or `--status in_progress` — call `save_issue`:

Tool: `mcp__linear-server__save_issue`
Args: `{ "id": "$LINEAR_ID", "state": "In Progress" }`

### Transition: push → "In Review"

After a successful `git push` of the PR-bearing branch (the branch that
becomes the PR for this bead), transition Linear to "In Review":

Tool: `mcp__linear-server__save_issue`
Args: `{ "id": "$LINEAR_ID", "state": "In Review" }`

Run this *only after* `git push` returns success. A failed push must not
flip Linear to In Review.

### What you do NOT do

- Do not transition to "Done" yourself. The convoy-cleanup molecule
  (`mol-convoy-cleanup.sc-linear-transition`) handles that on convoy
  close. The order `mol-sc-linear-sync` (every 10m) catches misses.
- Do not use GitHub auto-close keywords (`Closes SAF-XX`, `Fixes SAF-XX`)
  in PR bodies — Gas City lifecycle owns Linear transitions, not GitHub.
- Do not transition issues that aren't linked. If `LINEAR_ID` is empty,
  this fragment is silent.
{{ end }}
