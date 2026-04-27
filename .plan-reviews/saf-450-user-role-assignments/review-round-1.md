# Plan Review Round 1: Completeness & Sequencing

## Completeness Findings

### Applied (SHOULD-FIX)
1. **Rollback plan**: Added dedicated "Rollback Plan" section — greenfield tables can be dropped, routes unmounted. Down migration required alongside up migration.
2. **Migration sub-steps**: Expanded step 4 with explicit sub-steps: (a) define schema.ts, (b) `drizzle-kit generate`, (c) init script runs `drizzle-kit migrate`. Added verification checkpoint.
3. **In-memory UserRepository**: Updated step 2 to include updating any stub/in-memory implementations for the new `findByTenantAndId` method.
4. **Dual-auth middleware tests**: Added to Phase 4, step 13 — middleware isolation tests for cookie path, bearer path, malformed token, missing header.

### Applied (NICE-TO-HAVE → pre-condition)
5. **CORS**: Deferred — confirm existing Hono CORS covers `/api/v1/*` during implementation.
6. **Keycloak JWKS**: Added as risk row + pre-condition #5.
7. **Drizzle dependencies**: Added as pre-condition #6.

### Deferred
- Structured logging for role operations: acknowledged in Risks section (audit event persistence row). Not adding to plan scope — it's a cross-cutting concern per the PRD non-goals.
- Strict body parsing: added to step 10 description ("strict — reject extra fields").

## Sequencing Findings

### Applied (SHOULD-FIX)
1. **Parallel group annotations**: Replaced "partially parallelizable" with explicit Group A / Group B notation in Phase 2.
   - Group A (after Phase 1): steps 4, 8, 9 in parallel
   - Group B (after step 4): steps 5, 6, 7 in parallel
2. **Verification points**: Added inline "Verify:" checkpoints to steps 4, 6, 8, 12.

### Confirmed correct
- Phase 1 steps are independent and parallel ✓
- Critical path: Phase 1 → step 4 → step 6 → step 11 → step 12 → Phase 4 ✓
- No circular dependencies ✓
- Phase boundaries are clean ✓
