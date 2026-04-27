# Plan Review Round 3: Testability & Coherence

## Testability Findings

### Applied (SHOULD-FIX)
1. **Cross-tenant isolation test**: Added to step 14 integration tests — must test US-5 (tenant A auth, tenant B user → 404).
2. **Seed verification test**: Added to step 14 — seeded admin can POST a role assignment.

### Deferred (NICE-TO-HAVE)
- Smoke test specification for step 12: left as "end-to-end smoke test" — implementer discretion on exact sequence.
- Step 8 test token clarification: not added to doc — implementer will use dev Keycloak tokens.

## Coherence Findings

### Applied (SHOULD-FIX)
1. **Actor ID wiring**: Added explicit statement to routes section — handlers extract `actorId` from Hono context and pass to domain methods.

### Noted (no change)
2. **PRD `:roleId` vs design `:roleName`**: The PRD body text (US-3) still says `:roleId` but the PRD's own clarifications section resolves this to `:roleName`. Design doc is authoritative. Not updating the PRD body — it serves as the "before" record; the clarifications section is the correction.

### Verified
- No internal contradictions in design doc
- All PRD elements (goals, non-goals, user stories, constraints, open questions) mapped to design ✓
- Risk table complete with mitigations ✓
- Rollback plan present ✓

---

# Iterative Review Summary

## PRD Alignment (3 rounds)

### Round 1: Requirements & Goals
- Fixed US-6 deactivated-user behavior for reads
- Added auth claim mapping (`org_id` → tenantId, `sub` → actorId)
- Added INVALID_BODY 400 error
- Added tenant isolation enforcement path description
- All PRD goals, non-goals, user stories, constraints verified

### Round 2: Constraints & Non-Goals
- Added target branch `boylec/develop` to implementation plan
- All constraints satisfied, no scope creep

### Round 3: User Stories & Open Questions
- All user stories complete end-to-end
- All open questions resolved
- Permissions response shape decision documented as trade-off
- Relabeled "Open Questions" → "Implementation Pre-conditions"

## Plan Self-Review (3 rounds)

### Round 1: Completeness & Sequencing
- Added rollback plan section
- Expanded DB schema step with migration sub-steps
- Updated port extension to include stub implementations
- Added dual-auth middleware to unit test scope
- Parallelized Phase 2 into Group A / Group B
- Added per-step verification checkpoints
- Added 2 pre-conditions (JWKS, Drizzle dependencies)

### Round 2: Risk & Scope-Creep
- Added transaction boundary risk + mitigation for PgUserRepository.save()
- Added first-user bootstrap risk + seed step (4b)
- Made Aspire AppHost (step 5) conditionally deferrable
- No gold-plating or over-engineering found

### Round 3: Testability & Coherence
- Added cross-tenant isolation and seed verification to integration tests
- Added explicit actor ID wiring path in routes section
- Final completeness pass: all PRD elements mapped ✓

## Final Artifact Paths

- Design doc: `.designs/saf-450-user-role-assignments/design-doc.md`
- PRD draft: `.prd-reviews/saf-450-user-role-assignments/prd-draft.md`
- PRD review: `.prd-reviews/saf-450-user-role-assignments/prd-review.md`
- PRD alignment logs: `.plan-reviews/saf-450-user-role-assignments/prd-align-round-{1,2,3}.md`
- Plan review logs: `.plan-reviews/saf-450-user-role-assignments/review-round-{1,2,3}.md`
