# Plan Review Round 2: Risk & Scope-Creep

## Risk Findings

### Applied (SHOULD-FIX)
1. **Transaction boundary on save**: Clarified that PgUserRepository.save() must wrap version check + role assignment delete + insert in a single DB transaction. Prevents concurrent-save interleaving. Updated both the PgUserRepository section and the Risks table.
2. **First-user bootstrap**: Added seed step (4b) to Phase 2, Group B. Migration seed or bootstrap CLI creates initial admin from Keycloak claim. Added to Risks table.

### Verified adequate (no changes)
- All 5 pre-existing risks have solid mitigations ✓
- Keycloak JWKS risk (added round 1) ✓
- Rollback plan (added round 1) ✓
- No unknown-unknowns identified

## Scope-Creep Findings

### Applied (SHOULD-FIX)
1. **Aspire AppHost conditionality**: Added note to step 5 — check if identity's dev workflow depends on Aspire; if not, deferrable to separate infra ticket.

### No scope removed
The design is lean. Every component serves a direct need from the PRD:
- Dual-auth: required by auth constraint
- OpenAPI: drives validation + documentation
- Readiness probe: operational standard
- Optimistic concurrency: already in domain model
- RFC 7807 errors: existing convention

### Observations (no action)
- `validRoles` in POST 422 response is minor API surface area that will be redundant after SAF-448. Low cost, keep.
- Self-assignment guard deferral is correct — policy question, not technical.
