{{ define "target-branch-override" }}
## Target Branch

The base branch for SafetyChain work is `$GC_TARGET_BRANCH` (currently
`boylec/develop`), set workspace-wide via `[providers.*.env]` in
`pack.toml`. Use it in place of `main` for every branch / PR / push.

### Branch from the target

```bash
git fetch origin "$GC_TARGET_BRANCH"
git checkout -b "<branch-name>" "origin/$GC_TARGET_BRANCH"
```

Branch name convention: `<bead-id>-<short-slug>`, lowercase, hyphenated.
Example: `sc-wisp-uhht-add-tenant-quota`.

### Open the PR against the target

```bash
gh pr create \
  --base "$GC_TARGET_BRANCH" \
  --head "$(git branch --show-current)" \
  --title "<title>" \
  --body "<body>"
```

Never pass `--base main`. SafetyChain stacks PRs onto a long-lived
integration branch, not directly onto `main` — pushing to `main` bypasses
the integration branch and forces a manual revert.
{{ end }}
