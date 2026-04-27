# PRD Review Synthesis: SAF-450 User-Role Assignments API

Synthesized from 6 parallel review legs: requirements, gaps, ambiguity,
feasibility, scope, stakeholders.

## Executive Summary

The PRD is well-structured, correctly scoped to the identity bounded
context, and maps cleanly to existing domain operations (`User.assignRole`,
`User.revokeRole`, `resolvePermissions`). Sizing is **M** — a comfortable
sprint, not a quick task. The domain layer is complete; the primary work is
infrastructure greenfield (DB, repository, auth middleware, routes).

However, the PRD has **7 blocking issues** that must be resolved before
implementation begins. Three open questions (auth mechanism, actor
extraction, `:roleId` semantics) are not deferrable — they gate route
design, test harness, and API contract stability. A domain-layer bug
(`toSnapshot()` drops audit fields) will break repository round-tripping.
The downstream consumer picture is substantially under-represented.

**Overall confidence: Medium.** The PRD is a strong draft that needs one
revision pass to close blocking gaps before it becomes an implementable
spec.

## Before You Build: Critical Questions

These must be resolved before any implementation work starts.

### 1. Auth mechanism + actor extraction (blocking — gates everything)

The existing identity service is a pure cookie-based BFF (OAuth2 flows).
The new `/api/v1/` routes need programmatic access for service-to-service
calls. The PRD leaves this as Open Question 1 + 3 but it gates:
- Route middleware design
- How `actorId: UniqueId` is extracted for `assignRole()` / `revokeRole()`
- What integration tests authenticate with
- Whether SAF-449 enforcement middleware can reuse the same auth path

**Recommendation:** Add a single middleware that accepts either a session
cookie or a `Bearer` JWT, extracts `tenantId` + `actorId`, and injects
them into Hono context. Decide and document this before coding starts.

### 2. Authorization model for write operations (blocking — undefined)

The PRD says "tenant admin" can assign/revoke roles but never defines what
makes a caller an admin. `ROLE_PERMISSIONS` shows `oc:users:manage` is an
admin permission. The PRD must specify:
- Which permission(s) each endpoint requires
- Who can call GET endpoints (any authenticated user in tenant? admins only?)
- How the permission check is implemented (middleware or per-route)

### 3. `:roleId` parameter semantics (blocking — breaking-change trap)

`DELETE /api/v1/users/:userId/roles/:roleId` uses `:roleId` as a path
param but the value is actually the role name string (e.g., `operator`).
When SAF-448 introduces UUID role IDs, this becomes a breaking change on
a versioned route. Three options:
- **A.** Commit to role name as the stable key (rename param to `:roleName`)
- **B.** Use query param `?role=operator` so the path can later accept a UUID
- **C.** Ship with role name, accept the v2 migration when SAF-448 lands

Pick one and document it. Deferring is scope risk, not scope reduction.

### 4. `toSnapshot()` drops audit fields (blocking — domain bug)

`User.toSnapshot()` (line 76-87 of `user.ts`) omits the `audit` field
from the returned object, but `UserSnapshot` declares it. A
`PgUserRepository` round-tripping through `reconstitute()` will corrupt
or panic on `audit` data. This is a one-line fix that must land before
any repository work begins.

### 5. `UserRepository` port needs explicit tenant-scoped method

The generic `Repository<T>.findById(id)` lacks a `tenantId` parameter.
Cross-tenant isolation (US-5) requires a domain-defined method like
`findByTenantAndId(tenantId, userId): Promise<User | null>`. The existing
`UserRepository` only adds `findByEmail` and `existsByEmail`. Extend it
before writing infra.

### 6. Dual source of truth for roles: DB vs Keycloak `/me`

Currently `/api/identity/me` returns `roles` and `permissions` from the
Keycloak JWT. SAF-450 introduces a second source: the
`user_role_assignments` PostgreSQL table. The PRD's non-goal ("no Keycloak
sync") defers IdP sync but does not address the read path. Downstream BCs
base their ACL translation on whatever `/me` returns. If the two stores
diverge, permissions become inconsistent.

**Recommendation:** Decide whether `/me` reads from DB (authoritative) or
Keycloak (legacy), and document the interim behavior.

### 7. Downstream BC consumers are unacknowledged

Three bounded contexts — operational-context, operational-components, and
quality-rules — each maintain ACL files with TODOs waiting for the role
& permission model. SAF-450 produces the data those TODOs depend on.
The PRD does not mention these consumers or define a coordination plan
for when they activate real permission checks.

**Recommendation:** Add a "Consumers & Coordination" section listing the
three downstream BCs and their expected activation timeline.

## Important But Non-Blocking

These should be addressed in the PRD revision but won't block starting
implementation.

### 8. DB bootstrap is a hidden milestone

Identity has no `infra/db/` directory — no Drizzle config, no schema, no
migrations, no Aspire resource. This is standing up an entire persistence
layer, not just implementing a repository. The effort should be split into
a named pre-condition task or explicitly called out in the scope statement.

### 9. Error catalog is incomplete

The PRD mentions RFC 7807 problem details but does not enumerate all
expected HTTP status codes, `type` URIs, or response bodies. Missing cases:
- Invalid UUID in path (400 vs 422)
- User not found (404)
- Unknown role on POST (422)
- Unauthenticated (401)
- Unauthorized (403)
- Duplicate assignment (409 — mentioned but no body spec)
- Deactivated user (422 — mentioned but no body spec)

### 10. No performance/SLA requirements

No latency targets, no rate limiting, no pagination contract. What happens
at 100 assigned roles? What's the p99 target for `GET .../permissions`?
SAF-449 will call this on every request — latency matters.

### 11. Concurrency control should be decided, not deferred

`User` has a `version` field. Without `WHERE version = $expected` in
`PgUserRepository.save()`, concurrent admin writes silently last-write-wins.
The PRD lists this as OQ-5 but for a write API on a versioned aggregate,
this is correctness. At minimum: add a `version` column now; defer ETag
to a follow-up.

### 12. Compliance/audit gap

`AuthorizationResult` cites FDA 21 CFR Part 11 compliance. Role
assignment/revocation domain events are raised but the event-persistence
pipeline is deferred. For a food-safety product, shipping mutable role
state with no durable event log is a compliance risk. Name the owner and
the ticket that closes this gap.

### 13. `resolvePermissions()` silently drops unknown roles

If a persisted role is later removed from `ROLE_PERMISSIONS`, the user
silently loses permissions with no error. Document this as a known risk,
and consider a `warnings` field in the permissions response.

### 14. `GET .../permissions` response shape undefined

US-4 says "deduplicated, sorted list" but does not define sort key,
envelope shape, or whether `grantedBy` is included. Lock the baseline
response shape now even if extensions are deferred.

### 15. `assignedBy` is a bare UUID

The `RoleAssignment` response includes `assignedBy: UniqueId`. Callers
will need a display name. Adding it later is a contract change. Consider
returning `{ id, displayName }` from the start, or document the UUID-only
contract as intentional.

## Observations and Suggestions

- **Goal 5** ("forward-compatible with Roles aggregate") is an
  implementation constraint, not a user-facing goal. Move it to
  Constraints.
- **US-6** (deactivated user) relies on domain concepts (`isActive`,
  `UserDeactivated` error) that already exist in the codebase. No new
  domain work needed — but this should be stated explicitly.
- The DB setup effort is bounded and low-risk: the quality-rules Drizzle
  pattern (`schema.ts` + `drizzle.ts` + `init.ts`) is directly replicable.
  The schema is simple: `users` table + `user_role_assignments` child table.
- Defer ETag/If-Match (OQ-5) to a follow-up but add the `version` column
  to the DB schema now so the data is available when needed.
- Close OQ-6 (richer permissions response): ship the flat list, document
  the decision, file a follow-up if `grantedBy` is needed later.

## Confidence Assessment

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Completeness | 6/10 | Strong structure but too many unresolved OQs that are actually blocking |
| Clarity | 7/10 | Well-written but `:roleId` naming and auth path cause confusion |
| Feasibility | 8/10 | Domain model is solid, infra pattern exists to copy |
| Scope | 7/10 | DB bootstrap effort is under-counted; otherwise well-bounded |
| Stakeholder coverage | 5/10 | Downstream BCs, compliance, and /me dual-source all missing |

**Overall: Medium confidence.** One revision pass closing items 1-7 above
would raise this to High.

## Next Steps

1. Resolve the 7 blocking items (auth, authorization model, `:roleId`,
   `toSnapshot()` bug, `UserRepository` port, `/me` source of truth,
   downstream consumers).
2. Add error catalog, performance targets, and compliance acknowledgment.
3. Re-draft and proceed to design exploration.
