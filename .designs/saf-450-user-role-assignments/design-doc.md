# Design: SAF-450 User-Role Assignments API

## Executive Summary

Add four REST endpoints to the Identity bounded context for managing
user-role assignments and resolving computed permissions. The domain
layer is complete (`User.assignRole`, `revokeRole`, `resolvePermissions`);
this feature builds the infrastructure layer (PostgreSQL, Drizzle ORM,
repository), auth middleware, and HTTP routes to expose it.

Sizing: **M** (one sprint). The domain model is solid. Primary effort is
infrastructure greenfield and auth middleware.

## Problem Statement

The SafetyChain Identity context has a complete domain model for role
assignment (User aggregate, RoleAssignment value object,
PermissionResolver service) but no way to expose these operations via
HTTP. There is no persistence layer, no database schema, and no REST
routes. This blocks the broader RBAC flow: enforcement middleware
(SAF-449), Roles aggregate (SAF-448), and downstream bounded context
ACL activation all depend on role assignment capability.

## Proposed Design

### Architecture

```
┌─────────────────────────────────────────────────────┐
│ Identity Service (Hono, Deno)                        │
│                                                       │
│  /api/identity/*  ── BFF routes (login, callback,    │
│                       me, logout, refresh)            │
│                       Auth: cookie-based              │
│                                                       │
│  /api/v1/users/*  ── Role Assignment routes (NEW)    │
│                       Auth: cookie OR bearer middleware│
│                                                       │
│  Domain: User aggregate, PermissionResolver           │
│  Infra: PgUserRepository (NEW), Drizzle schema (NEW) │
└─────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│ PostgreSQL       │
│ identity DB      │
│ ┌─────────────┐  │
│ │ users       │  │
│ │ user_role_  │  │
│ │ assignments │  │
│ └─────────────┘  │
└─────────────────┘
```

### Endpoints

| Method | Path | Auth | Permission | Description |
|--------|------|------|------------|-------------|
| GET | `/api/v1/users/:userId/roles` | cookie\|bearer | any tenant member | List role assignments |
| POST | `/api/v1/users/:userId/roles` | cookie\|bearer | `oc:users:manage` | Assign a role |
| DELETE | `/api/v1/users/:userId/roles/:roleName` | cookie\|bearer | `oc:users:manage` | Revoke a role |
| GET | `/api/v1/users/:userId/permissions` | cookie\|bearer | any tenant member | Computed permissions |

### Response Contracts

**Success (2xx)**: `{ data: { ... } }` envelope, consistent with `/me`.

**Errors**: RFC 7807 `application/problem+json` without `data` wrapper.

| Error | HTTP | `type` URI suffix | Domain Error |
|-------|------|-------------------|--------------|
| Invalid UUID | 400 | `INVALID_PARAMS` | — |
| Unauthenticated | 401 | `UNAUTHORIZED` | — |
| Insufficient permission | 403 | `FORBIDDEN` | — |
| User not found / cross-tenant | 404 | `NOT_FOUND` | — |
| Duplicate assignment | 409 | `ROLE_ALREADY_ASSIGNED` | `RoleAlreadyAssigned` |
| Unknown role | 422 | `UNKNOWN_ROLE` | — |
| Role not assigned | 404 | `ROLE_NOT_ASSIGNED` | `RoleNotAssigned` |
| User deactivated (POST only) | 422 | `USER_DEACTIVATED` | `UserDeactivated` |
| Concurrency conflict (version mismatch) | 409 | `CONCURRENCY_CONFLICT` | — |
| Invalid request body (missing/bad `role` field) | 400 | `INVALID_BODY` | — |

**Note on deactivated users:** The `USER_DEACTIVATED` 422 applies only to
POST (assign). DELETE (revoke) succeeds on deactivated users — revoking
is a cleanup operation that should not require reactivation. GET endpoints
(list roles, get permissions) return current state for deactivated users —
reads always succeed regardless of activation status.

**POST `422 UNKNOWN_ROLE` response** includes `validRoles` array for
discoverability (sourced from `SYSTEM_ROLES`) until SAF-448 provides a
roles endpoint.

### Request/Response Shapes

**POST /api/v1/users/:userId/roles**
```json
// Request
{ "role": "operator" }

// Response 201
{
  "data": {
    "role": "operator",
    "assignedAtUtc": "2026-04-26T12:00:00.000Z",
    "assignedBy": "uuid-of-actor"
  }
}
```

**GET /api/v1/users/:userId/roles**
```json
// Response 200
{
  "data": {
    "roleAssignments": [
      { "role": "admin", "assignedAtUtc": "...", "assignedBy": "..." },
      { "role": "operator", "assignedAtUtc": "...", "assignedBy": "..." }
    ]
  }
}
```

**GET /api/v1/users/:userId/permissions**
```json
// Response 200
{
  "data": {
    "permissions": ["oc:items:read", "oc:items:write", "oc:locations:read", ...]
  }
}
```

**DELETE /api/v1/users/:userId/roles/:roleName** → 204 No Content

## Key Components

### 1. Dual-Auth Middleware

New Hono middleware at `/api/v1/*` that accepts either:
- Session cookie (same as existing BFF flow)
- `Authorization: Bearer <JWT>` header (for service-to-service)

Extracts `tenantId` and `actorId` from the validated token claims:
- `tenantId` ← `org_id` claim (flat) or first entry in `organization` map
- `actorId` ← `sub` claim (JWT subject, always a user UUID)

Sets both on the Hono context. Does NOT apply to `/api/identity/*` routes.

**Tenant isolation enforcement path:** Middleware extracts `tenantId` from
the caller's token → route handler passes this `tenantId` (NOT a path
param) to `findByTenantAndId(tenantId, userId)` → repository SQL includes
`WHERE tenant_id = $tenantId AND user_id = $userId`. If the user belongs
to a different tenant, the query returns null and the handler returns 404
(not 403), preventing existence leaks.

### 2. User Role Routes Module

New file: `identity/app/api/user-role-routes.ts`

Uses a separate `UserRolesEnv` type (not `IdentityAppEnv`) to avoid
coupling BFF concerns with DB-backed routes. Mounted in `main.ts`:

```typescript
app.use("/api/v1/*", dualAuthMiddleware());
app.route("/api/v1/users", createUserRoleRoutes(deps));
```

Route handlers extract `actorId` from Hono context (set by dual-auth
middleware) and pass it as the `actor` parameter to domain methods
(`assignRole`, `revokeRole`).

Error handling follows the existing `createDomainErrorHandler` pattern
with a `USER_STATUS_MAP` / `USER_TITLE_MAP` covering all domain errors.

### 3. PostgreSQL Schema (Drizzle ORM)

New directory: `identity/infra/db/`

Following the quality-rules pattern (`schema.ts` + `drizzle.ts` +
`init.ts` + `drizzle.config.ts`).

### 4. PgUserRepository

New file: `identity/infra/repositories/pg-user-repository.ts`

Implements `UserRepository` with the added
`findByTenantAndId(tenantId, userId)` method.

Save uses optimistic concurrency within a single DB transaction:
`BEGIN` → `UPDATE users SET ... WHERE user_id = $1 AND version = $expected`
→ `DELETE FROM user_role_assignments WHERE user_id = $1`
→ `INSERT INTO user_role_assignments ...` → `COMMIT`.

Role assignments are delete-and-reinsert on save (assignments are
aggregate-owned value objects with no external FK references). The
transaction boundary ensures concurrent saves cannot interleave
delete/insert operations.

## Data Model

### Table: `users`

| Column | Type | Constraints |
|--------|------|-------------|
| `user_id` | `uuid` | `PRIMARY KEY` |
| `tenant_id` | `uuid` | `NOT NULL` |
| `email` | `text` | `NOT NULL` |
| `display_name` | `text` | `NOT NULL` |
| `is_active` | `boolean` | `NOT NULL DEFAULT true` |
| `created_at_utc` | `timestamptz` | `NOT NULL` |
| `created_by` | `uuid` | `NOT NULL` |
| `updated_at_utc` | `timestamptz` | `NOT NULL` |
| `updated_by` | `uuid` | `NOT NULL` |
| `version` | `integer` | `NOT NULL DEFAULT 1` |

**Indexes**: `UNIQUE(tenant_id, email)`, `INDEX(tenant_id)`

### Table: `user_role_assignments`

| Column | Type | Constraints |
|--------|------|-------------|
| `user_id` | `uuid` | `NOT NULL REFERENCES users(user_id) ON DELETE CASCADE` |
| `role_name` | `text` | `NOT NULL` |
| `assigned_at_utc` | `timestamptz` | `NOT NULL` |
| `assigned_by` | `uuid` | `NOT NULL` |

**Primary key**: `(user_id, role_name)`

The `role_name` column (not `role_id`) signals this is a string key.
SAF-448 migration adds `role_id uuid REFERENCES roles(role_id) NULLABLE`,
then a follow-on migration makes it non-null after backfill.

## Interface

### UserRepository Port (extended)

```typescript
export interface UserRepository extends Repository<User> {
  findByEmail(tenantId: UniqueId, email: Email): Promise<User | null>;
  existsByEmail(tenantId: UniqueId, email: Email): Promise<boolean>;
  findByTenantAndId(tenantId: UniqueId, userId: UniqueId): Promise<User | null>;
}
```

### Domain Bug Fix: `User.toSnapshot()`

Add `audit` field to the `toSnapshot()` return object to match
`UserSnapshot`. Without this, the repository round-trip loses audit data.

## Trade-offs and Decisions

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| `:roleName` in DELETE path | Role name string | UUID role ID | Stable key until SAF-448; rename from `:roleId` to avoid confusion |
| Auth middleware | Dual cookie+bearer | Separate BFF/API services | Single service, simpler deployment; middleware scoped to `/api/v1/*` |
| DB provisioning | Separate logical DB for identity | Shared DB | Follows quality-rules precedent; BC autonomy |
| Concurrency | Optimistic lock via `version` column | No locking | `User` aggregate already tracks `version`; prevents silent data loss |
| Permission caching | None (deferred) | Redis/in-process TTL | Load is low pre-SAF-449; add cache when enforcement activates |
| `/me` source of truth | Keycloak (unchanged) | Switch to DB | Minimizes scope; reconciliation ticket filed separately |
| Permissions response shape | Flat sorted array | `{ permission, grantedBy: [roles] }` | Flat list matches domain service output; richer shape deferred to avoid contract churn before SAF-448 |
| Event persistence | Deferred (non-goal) | Build event store now | Domain events are raised; persistence is cross-cutting concern |
| Self-assignment guard | Deferred | Route-layer check | `oc:users:manage` permission gate already prevents non-admins from calling POST; self-escalation by existing admins is a policy question, not a technical one — defer to a follow-up ticket with explicit product decision |

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| DB bootstrap is hidden milestone | Schedule slip | Split into explicit pre-condition task; verify `createBcConnection("identity")` in platform-core |
| `/me` and DB diverge on roles | Stale permissions for downstream BCs | File reconciliation ticket as hard dependency before any downstream BC activates real permission checks; document prominently in API docs; add explicit hold on ACL activation in OC/OCC/QR until reconciliation ships |
| `resolvePermissions()` silently drops unknown roles | User gets fewer permissions than expected | Validate on assignment (POST rejects unknown roles); document as known behavior |
| No audit event persistence | Compliance gap (FDA 21 CFR Part 11) | `assigned_by` column is interim audit artifact; file event-persistence ticket with compliance owner |
| SAF-449 turns permissions endpoint into hot path | Performance regression | Design permissions handler to be cache-friendly; add TTL cache when SAF-449 activates |
| Keycloak JWKS not configured for identity service | Dual-auth middleware fails on bearer tokens | Verify JWKS discovery endpoint is reachable during step 8; add to pre-conditions |
| Role assignment save concurrency window | Duplicate or lost assignments under concurrent saves | PgUserRepository.save() must wrap version check + assignment delete + assignment insert in a single DB transaction |
| First-user bootstrap chicken-and-egg | No admin exists to assign admin role via POST endpoint | Add seed step to Phase 2 (after DB schema) — migration seed or bootstrap CLI creates initial admin from Keycloak claim |

## Rollback Plan

This is a greenfield feature — no existing data or routes are modified.
Rollback is safe at any point:

- **DB rollback**: `DROP TABLE IF EXISTS user_role_assignments; DROP TABLE IF EXISTS users;` in the identity schema. No other tables reference these.
- **Route rollback**: Remove `/api/v1/*` mount from `main.ts`. No existing routes are affected.
- **Migration**: Keep a `down` migration alongside the `up` migration generated by `drizzle-kit`. Verify it runs cleanly against the test DB before shipping.

## Implementation Plan

**Target branch**: `boylec/develop`

Execute in dependency order. Steps within a phase can be parallelized
where noted.

### Phase 1: Prerequisites (all three run in parallel)
1. **Fix `User.toSnapshot()`** — add `audit` to returned object
2. **Extend `UserRepository` port** — add `findByTenantAndId`; update any existing stub/in-memory implementations (test fixtures) to satisfy the new method
3. **Verify platform-core** — confirm `createBcConnection("identity")` works; if missing, add the entry before proceeding to Phase 2

### Phase 2: Infrastructure + API contract (parallel groups noted)

**Group A (parallel, start after Phase 1):**
4. **DB schema** — `identity/infra/db/` with Drizzle schema, config, init. Sub-steps: (a) define schema.ts, (b) `drizzle-kit generate` migration SQL, (c) init script that runs `drizzle-kit migrate`. Verify: migration runs clean against a fresh test DB.
8. **Dual-auth middleware** — cookie|bearer, scoped to `/api/v1/*` (no DB dependency; can start after step 2). Verify: Keycloak JWKS endpoint is reachable; cookie and bearer paths extract identity correctly with test tokens.
9. **OpenAPI spec** — declare endpoints, error schemas, request/response shapes, `SYSTEM_ROLES` enum (contract-first; drives route implementation)

**Group B (parallel, start after step 4):**
4b. **Seed initial admin** — migration seed script or bootstrap CLI that creates the first admin user from a Keycloak claim, avoiding the chicken-and-egg problem where POST requires `oc:users:manage` but no admin exists yet
5. **Aspire AppHost** — register identity DB resource + init resource (check if identity's dev workflow depends on Aspire; if not, deferrable to separate infra ticket)
6. **PgUserRepository** — implement in `identity/infra/repositories/`. Verify: CRUD smoke test against test DB passes.
7. **Update readiness probe** — add DB connectivity check to `/ready`

### Phase 3: Routes + wiring (sequential)
10. **Request body validation** — Zod/Valibot schema for POST body (`{ role: string }`, strict — reject extra fields) and path param validation (UUID for `:userId`, `SYSTEM_ROLES` allowlist for `:roleName`)
11. **User role routes** — 4 endpoints in `identity/app/api/user-role-routes.ts`
12. **Composition root** — wire `PgUserRepository` injection into `createUserRoleRoutes(deps)` and mount middleware + routes in `main.ts`. Verify: end-to-end smoke test before formal test suite.

### Phase 4: Quality
13. **Unit tests** — route handlers with stubbed repository; include concurrency conflict (version mismatch → 409), deactivated-user edge cases, and dual-auth middleware isolation tests (cookie path, bearer path, malformed token, missing header)
14. **Integration tests** — real Postgres, following `tests/api-integration/` pattern. Must include: cross-tenant isolation test (US-5: authenticated as tenant A, request user in tenant B → 404), and seed verification (seeded admin can POST a role assignment)

## Implementation Pre-conditions to Verify

These are not design open questions — the design decisions are made. These
are implementation-level checks to perform before coding starts.

1. Does `platform-core` support `createBcConnection("identity")` or does
   it need a new entry?
2. Does the Aspire AppHost have an existing Postgres cluster that identity
   can attach to, or is a new resource needed?
3. Actor identity for M2M tokens: is `sub` claim always set in Keycloak
   for service-to-service tokens?
4. Should `GET .../permissions` return empty array or 404 for a user with
   no roles? (Recommended: empty array, consistent with US-1.)
5. Is the Keycloak JWKS discovery endpoint configured and reachable from
   the identity service? Required for dual-auth bearer token validation.
6. Are `drizzle-orm`, `drizzle-kit`, and `pg` (or `postgres`) already in
   the identity service dependencies, or do they need to be added?

## Downstream Consumers & Coordination

Three bounded contexts have ACL files with TODOs waiting for the role &
permission model:
- `operational-context/app/acl/identity-acl.ts`
- `operational-components/app/acl/identity-acl.ts`
- `quality-rules/app/acl/identity-acl.ts`

SAF-450 produces the data those TODOs depend on. Activation of real
permission checks in each BC is a separate coordination effort that must
be planned after SAF-450 ships. Until then, the existing permissive
defaults remain in production.

SAF-449 (enforcement middleware) will consume `GET .../permissions` on
every authenticated request. Cache design should be deferred until
SAF-449 integration is scoped.
