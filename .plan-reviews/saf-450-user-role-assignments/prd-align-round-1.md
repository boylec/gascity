# PRD Alignment Round 1: Requirements & Goals

## Applied Fixes

### Must-fix (applied)
1. **US-6 deactivated-user reads**: Added explicit note that `USER_DEACTIVATED` 422 applies only to POST/DELETE. GET endpoints succeed on deactivated users.
2. **Auth claim mapping**: Specified `tenantId` ← `org_id` claim, `actorId` ← `sub` claim in the dual-auth middleware section.
3. **POST body validation**: Added `INVALID_BODY` 400 to error table for missing/malformed `role` field.
4. **Tenant isolation enforcement**: Added explicit path description: middleware → route → `findByTenantAndId` → SQL WHERE. Clarified 404 (not 403) for cross-tenant.

### Should-fix (noted, not blocking)
5. v1/v2 versioning strategy for `:roleName` → `:roleId` migration could be more explicit.
6. API response shape forward compat for SAF-448 (when `roleId` is added to response) not addressed at API level.
7. Hono mount pattern compatibility implicitly covered by the mount snippet.

## Verification
- All 5 PRD Goals verified as covered (Goals 1-4 pass, Goal 5 pass at DB level)
- All 5 Non-Goals verified as respected
- All 6 User Stories verified as addressed
- All 6 Constraints verified as covered or explicitly deferred
