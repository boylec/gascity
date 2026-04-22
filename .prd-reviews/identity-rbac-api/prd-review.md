# PRD Review: Identity Bounded-Context RBAC API Surface

**Review ID**: identity-rbac-api
**Date**: 2026-04-21
**Reviewer**: quartermaster-2 (6-leg parallel review against enterprise codebase)
**PRD**: `.prd-reviews/identity-rbac-api/prd-draft.md`
**Molecule**: hq-jrpiz (mol-sc-idea-to-plan)

---

## Executive Summary

The PRD describes a well-structured RBAC API surface with clear domain boundaries, 7 user stories, and a phased implementation approach grounded in the real codebase. However, the review uncovered a fundamental misframing: the PRD describes a "PermissionResolver refactor" when in fact **permission resolution has never been wired into the production request pipeline**. The auth middleware hardcodes `permissions: []` on every request (`auth.ts:153`), and all three downstream BCs (OC, OCC, QR) run permissive ACL defaults. This is not a refactor — it is first-time activation of permission enforcement across the entire system, with a blast radius that touches every authenticated request.

Additionally, there are two competing `/me` endpoints (BFF cookie-auth vs. proposed Bearer-auth), a contradiction between seed role "immutability" and "extensibility," and the Identity BC has zero database infrastructure today — requiring a Phase 0 bootstrap not scoped in the PRD.

The PRD is a strong draft. With the questions below resolved, it will be ready for implementation planning.

---

## Before You Build: Critical Questions

These must be answered before implementation begins. Each was flagged independently by 2+ review legs.

### 1. Where does permission resolution happen in the request pipeline?

`resolvePermissions` is exported from `contexts/identity/domain/mod.ts` but has **zero callers in production code** — only in tests. The auth middleware at `platform/platform-core/http/middleware/auth.ts:153` hardcodes `permissions: []`. The PRD must specify:

- **Where**: Auth middleware? `/me` handler only? Lazy on first access?
- **When**: Every request (adds ~2-5ms DB query to hot path) or embedded in JWT via Keycloak protocol mapper?
- **How**: The current `extractClaims` function is synchronous. DB-backed resolution requires an async call. What is the caching strategy? TTL-based? Invalidation on role-assignment events?

**Why this blocks**: Without this decision, the PermissionResolver refactor, the `/me` endpoint, the middleware integration, and the downstream ACL activation are all undesignable.

### 2. How do the two `/me` endpoints coexist?

The existing OAuth BFF serves `GET /api/identity/me` (`contexts/identity/app/routes.ts:183`) returning `AuthenticatedIdentity` from a cookie-based access token. The PRD proposes `GET /api/v1/me` returning profile + roles + resolved permissions via Bearer token auth. The response shapes differ. The PRD must state:

- Do both coexist (different auth mechanisms for different clients)?
- Does the new one replace the old?
- Which is canonical for the frontend (SAF-446)?

### 3. What is the downstream ACL cutover plan?

Three BCs consume `AuthenticatedIdentity` and all run permissive defaults:
- **OC** (`contexts/operational-context/app/acl/identity-acl.ts:29-41`): All capabilities hardcoded to `true`, with commented-out permission checks
- **OCC** (`contexts/operational-components/app/acl/identity-acl.ts`): Extracts only actorId/tenantId
- **QR** (`contexts/quality-rules/app/acl/identity-acl.ts`): Same

Once the middleware starts populating permissions and ACLs start checking them, any seed data mismatch causes authorization failures. The PRD needs:
- Feature-flag-gated activation per BC
- Contract tests proving DB-backed resolver matches the hardcoded `ROLE_PERMISSIONS` map for seed roles
- Named BC teams as stakeholders with acceptance criteria

### 4. Are seed roles immutable or extensible?

US-4 acceptance states: "Four seed roles are immutable (cannot delete, **can extend permissions**)." These are contradictory. If admins can modify the permission set, the role is mutable. Additionally: what happens when a future deploy adds new system permissions to a seed role that an admin has already customized?

**Proposed resolution**: Seed roles are `delete_protected` with a `basePermissions` set that is always included. Admins can add permissions but cannot remove base ones.

### 5. What is the authoritative tenant scoping mechanism?

Open Question 5 flags `X-Tenant-Id` vs JWT `tenant_id`/`org_id`, but the constraints assume JWT claims. The auth middleware defaults to `org_id` (`auth.ts:40`). Since the Identity endpoints are the foundational layer — every other BC inherits whatever pattern is chosen here — this must be resolved to a single answer before implementation.

---

## Important But Non-Blocking

These should be resolved during implementation planning but do not block the start of work.

### 6. Identity BC needs a Phase 0: Database Bootstrap
The Identity context has no Drizzle config, no schema, no migrations, no DB connection. `main.ts` explicitly notes "No database — delegates to Keycloak." This is ~1-2 days of bootstrapping using the OC context's `infra/db/` as a template. Should be an explicit Phase 0 prerequisite.

### 7. PermissionResolver refactor warrants its own phase gate
The scope review recommends splitting this into a separate PRD or at minimum a hardened Phase 0 with its own acceptance criteria and rollback strategy. The current resolver is 71 lines of pure function with zero I/O; the proposed change alters latency on every authenticated request across every BC.

### 8. KeycloakAdminPort expansion is under-scoped
The port defines only `createOrganization` and `createUser` (2 operations). The PRD requires ~7-9 new operations. The adapter (~315 lines) will roughly triple. Each operation needs idempotency handling, error mapping, and test coverage. This should be explicitly phased — read operations first (to unblock Users list), then mutations.

### 9. Keycloak dual-write consistency
User CRUD proxies to Keycloak while role assignments persist in Postgres. If Keycloak succeeds but the DB write fails, you have an orphaned Keycloak user. The adapter has a 10-second timeout with no retry logic. Define saga/compensation or accept-and-reconcile strategy.

### 10. Missing reactivate() on User aggregate
The PRD proposes `POST /:id:reactivate` but the User aggregate has only `deactivate()` (line 255). No `reactivate()` method or `UserReactivated` event exists. Consider deferring reactivation to a follow-up and shipping deactivate-only MVP.

### 11. Error responses not specified per endpoint
The API conventions mandate RFC 9457 Problem Details. Only 409 is mentioned (US-2). Missing: 404 for nonexistent resources, 422 for invalid prefixed IDs, 412 for ETag precondition failures, 409 for deleting a role with active assignments, 400 for invalid filter syntax. Add an error response table per endpoint group.

### 12. Security review gate required
The enterprise is governed for SOC2 Type II compliance. The PRD introduces privilege-escalation-sensitive operations (role assignment, permission-set modification) with no mention of security review, privilege-escalation guards (can a manager create an admin role?), or OWASP authorization testing.

### 13. Token staleness on permission changes
When an admin revokes a role, active sessions carry stale permissions in their JWT until token expiry. The PRD does not describe cache-invalidation or session-revocation. Document the accepted staleness window or add a short-lived cache with invalidation signals.

### 14. Audit event disposition
The PRD defers audit trails (Non-Goals) but the User aggregate already emits domain events (`RoleAssigned`, `RoleRevoked`, `UserDeactivated`). If emitted but not persisted, the system looks auditable but is not. State whether events are persisted to an event store or explicitly suppressed until the audit PRD lands.

### 15. `perm` prefix registration timing
Listed as Phase 4 in the PRD but needed in Phase 1 for the Permission seed migration. Move to Phase 1.

---

## Observations and Suggestions

### 16. Pagination naming mismatch
US-1 specifies `?cursor=...&limit=25` but API conventions (`.claude/rules/api-routes.md`) and existing routes use `pageToken`/`pageSize`. Use the established parameter names.

### 17. Endpoint count is ~17-18, not ~20
Permissions(2) + Roles(5) + Users(6-7) + User-Roles(3) + /me(1) = 17-18. If the PRD intends ~20, name the missing endpoints (e.g., `POST /users:search`, `GET /roles/:id/users`).

### 18. Permission count is known: 11 unique strings, 4 roles
The `ROLE_PERMISSIONS` map at `permission-resolver.ts:12-50` contains exactly 11 unique permission strings across 4 roles. This is answerable from the codebase and should be stated as a known quantity.

### 19. PUT-only role update is error-prone for API consumers
PUT replaces the entire permission set atomically. Adding one permission to a 30-permission role requires sending all 31. Consider documenting that PATCH is intentionally deferred, or add it.

### 20. Phase 1 lacks a shippable artifact
Phase 1 (domain model + schema + seed) has no user-visible deliverable. Adding the read-only Permissions API (`GET /permissions`) to Phase 1 provides a smoke test endpoint.

### 21. QA reset endpoint
US-7 acceptance says "seed data migration can be re-run or an admin endpoint exists to reset to defaults" but neither is defined. QA needs `POST /admin/reset-rbac-defaults` or documented CLI access.

### 22. Frontend convenience data
SAF-446 will likely need: role-usage counts (users per role), user-count-by-status, user-with-roles-inline in a single response. The PRD separates `/users/:id` and `/users/:id/roles`. Consider `?include=roles` query parameter.

### 23. "Soft-delete" vs "deactivate" terminology
The PRD uses "soft-delete" for both users and roles but they are different state machines. Use "deactivate" for users (reversible) and "soft-delete" for roles (different lifecycle). Define each explicitly.

### 24. KeycloakAdminPort can be parallelized with Phase 1
The port interface changes and adapter methods are independent of the DB schema work. Starting them in parallel saves calendar time.

---

## Confidence Assessment

| Dimension | Score | Notes |
|-----------|-------|-------|
| Requirements | 7/10 | Well-formed user stories but missing error specs and endpoint precision |
| Completeness | 5/10 | Critical gaps in permission resolution pipeline and ACL cutover |
| Clarity | 6/10 | Several ambiguities that will force implementation-time decisions |
| Feasibility | 8/10 | Technically sound; codebase patterns support the approach |
| Scope | 6/10 | PermissionResolver refactor may warrant separation; audit/security gaps |
| Stakeholder Alignment | 5/10 | Downstream BCs not named as stakeholders; QA/DevOps under-served |
| **Overall** | **6/10** | Strong draft with 5 critical questions to resolve before implementation |

---

## Next Steps

1. **Resolve the 5 critical questions** in the "Before You Build" section — these should be answered in a PRD revision before creating implementation tasks.
2. **Decide on PermissionResolver phasing** — separate PRD or hardened Phase 0 with own gate.
3. **Add Phase 0 (Identity DB Bootstrap)** as an explicit prerequisite.
4. **Name all 4 BC teams as stakeholders** with acceptance criteria for the permission-enforcement cutover.
5. **Add security review gate** before Phase 3 endpoints go live.
6. **Revise and resubmit** the PRD with these changes for a focused re-review on the critical questions.
