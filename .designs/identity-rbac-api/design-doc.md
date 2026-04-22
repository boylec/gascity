# Design: Identity Bounded-Context RBAC API Surface

## Executive Summary

This design implements ~18 REST endpoints for the Identity bounded context's RBAC surface: Users CRUD + /me, Roles CRUD with permission-set replace, user-role assignments, and Permissions read-only list/get. The design is split into 5 phases (Phase 0-4) to manage the cross-BC blast radius of wiring permission resolution into the auth middleware for the first time.

The key architectural insight from the PRD review: this is not a "PermissionResolver refactor" — it is **first-time activation of permission enforcement**. The auth middleware currently hardcodes `permissions: []` (`auth.ts:153`), and all downstream BCs run permissive ACL defaults. The design treats this activation as a separate, feature-flagged deliverable (Phase 1) before exposing any new API surface.

## Problem Statement

SafetyChain's Identity BC needs a complete RBAC API surface. The current `PermissionResolver` uses a hardcoded map (`ROLE_PERMISSIONS`) with 4 roles and 11 unique permission strings. Roles are not persisted aggregates. Permissions are not queryable. No API surface exists for user management, role assignment, or permission querying. This blocks SAF-446 (Users UI) and SAF-450.

## Proposed Design

### Phase 0: Identity DB Bootstrap

The Identity BC has zero database infrastructure today (`main.ts` line 6: "No database — delegates to Keycloak"). Bootstrap using OC context's `infra/db/` as template:

- Drizzle config and connection pool setup
- Migration runner integration
- UnitOfWork pattern (follow OCC pattern at `contexts/operational-components/infra/db/`)
- Test harness for DB-backed routes

**Deliverable**: Identity BC can connect to Postgres, run migrations, and execute queries.

### Phase 1: Permission & Role Domain Model + Resolution Pipeline

**Schema** (Drizzle, following existing patterns):

```
permissions
  id: uuid PK
  name: text NOT NULL UNIQUE  -- e.g., "oc:items:read"
  description: text
  category: text  -- e.g., "oc", "occ", "qr"
  created_at: timestamptz

roles
  id: uuid PK
  tenant_id: uuid NOT NULL
  name: text NOT NULL
  description: text
  is_system: boolean DEFAULT false
  is_active: boolean DEFAULT true
  created_at: timestamptz
  updated_at: timestamptz
  UNIQUE(tenant_id, name)

role_permissions
  role_id: uuid FK -> roles.id
  permission_id: uuid FK -> permissions.id
  PK(role_id, permission_id)
```

**Seed migration**: Extract the 4 roles and 11 permissions from `ROLE_PERMISSIONS` map at `permission-resolver.ts:12-50` into INSERT statements. This is the compatibility baseline.

**Register `perm` prefix** in ADR-019 registry (currently only `usr` and `rol` are registered).

**PermissionResolver refactor**: Change `resolvePermissions` to query the `role_permissions` join via the Role repository. Add a parity test: DB-backed resolver must produce identical output to the hardcoded map for all 4 seed roles.

**Permission Resolution Pipeline** (the critical design decision):

Two viable approaches:
1. **Middleware-level async resolution** — Add a DB query to `extractClaims` in `auth.ts`. Adds ~2-5ms per request. Requires making the middleware async.
2. **JWT-embedded via Keycloak protocol mapper** — Embed resolved permissions in the JWT claim at token-issue time. Middleware stays sync. Requires Keycloak configuration.

**Recommendation**: Approach 1 (middleware-level) with an in-memory TTL cache keyed on `{userId, roleSetHash}`. Cache TTL of 60s. Invalidation on role-assignment domain events. Reason: Approach 2 couples Keycloak config to the permission model and makes permission changes lag behind token refresh cycles.

**Feature flag**: `identity.rbac.resolve_permissions` (default: false). When false, middleware continues to pass `permissions: []`. When true, middleware calls `resolvePermissions` and populates the array. This allows Phase 1 to ship without activating enforcement.

**Read-only Permissions API**: Ship `GET /api/v1/permissions` and `GET /api/v1/permissions/:id` in Phase 1 as a smoke-test endpoint.

**Deliverable**: Domain model persisted, seed data migrated, resolver refactored with parity tests, feature flag in place, Permissions API live.

### Phase 2: User-Role Assignment Model + Keycloak Adapter Expansion

**Schema**:

```
user_role_assignments
  user_id: uuid NOT NULL  -- Keycloak UUID (usr_ prefix in API layer only)
  role_id: uuid FK -> roles.id
  tenant_id: uuid NOT NULL
  assigned_at: timestamptz NOT NULL
  assigned_by: uuid  -- userId of admin who assigned
  PK(user_id, role_id, tenant_id)
```

**RoleAssignment VO migration**: Evolve from `role: string` to `roleId: UUID` reference. Existing string role names ("admin", etc.) are resolved to `rol_` IDs via the seed data.

**KeycloakAdminPort expansion** (read operations first):

New port methods on `KeycloakAdminPort` interface at `contexts/identity/domain/ports/keycloak-admin.ts`:
- `getUser(userId: string): Promise<KeycloakUser | null>`
- `listUsers(tenantId: string, opts: ListUsersOpts): Promise<PagedResult<KeycloakUser>>`
- `updateUser(userId: string, updates: UserUpdates): Promise<void>`
- `enableUser(userId: string): Promise<void>`
- `disableUser(userId: string): Promise<void>`

Follow the existing adapter pattern at `keycloak-admin-client.ts` — raw `fetch` against Keycloak Admin REST API, structured error mapping, 10s timeout.

**User aggregate updates**:
- Add `reactivate()` method + `UserReactivated` domain event (or defer to follow-up — see Risks)
- Evolve `roleAssignments` from `RoleAssignment[]` (string-based) to `RoleAssignment[]` (UUID-based)

**Deliverable**: User-role assignments persisted in Postgres, Keycloak adapter supports user CRUD read/write, assignment/revocation domain operations working.

### Phase 3: API Endpoints

All under `/api/v1/`, following conventions in `.claude/rules/api-routes.md`.

**Permissions** (read-only, shipped in Phase 1):
- `GET /api/v1/permissions` — List all system permissions (no pagination, small fixed set)
- `GET /api/v1/permissions/:id` — Get by perm_-prefixed ID

**Roles**:
- `POST /api/v1/roles` — Create role with name + permission_ids array
- `GET /api/v1/roles` — List roles (pageToken/pageSize pagination, tenant-scoped)
- `GET /api/v1/roles/:id` — Get role with permission set
- `PUT /api/v1/roles/:id` — Replace permission set atomically
- `DELETE /api/v1/roles/:id` — Soft-delete (fails with 409 if users assigned)

**Users** (proxy to Keycloak + local assignments):
- `POST /api/v1/users` — Create user in Keycloak + optional role assignment
- `GET /api/v1/users` — List users (pageToken/pageSize, tenant-scoped, ?filter= for status/role)
- `GET /api/v1/users/:id` — Get user (supports ?include=roles query param)
- `PUT /api/v1/users/:id` — Update profile fields
- `POST /api/v1/users/:id:deactivate` — Soft-deactivate (Keycloak disable + local isActive=false)
- `POST /api/v1/users/:id:reactivate` — Re-enable (if included in scope)

**User-Role Assignments**:
- `GET /api/v1/users/:id/roles` — List user's roles
- `POST /api/v1/users/:id/roles` — Assign role (idempotent, 200 on re-assign)
- `DELETE /api/v1/users/:id/roles/:roleId` — Revoke role (204)

**Me**:
- `GET /api/v1/me` — Profile + roles + resolved permissions (Bearer token auth)

**Total**: 17 endpoints (18 with reactivate).

**Coexistence with BFF `/me`**: The existing `GET /api/identity/me` (cookie-auth, BFF flow) and `GET /api/v1/me` (Bearer-auth, API flow) serve different clients. Both coexist. The BFF `/me` is for browser sessions; the API `/me` is for programmatic consumers and SAF-446's Bearer-token-based frontend.

**Error responses**: Follow RFC 9457 Problem Details per existing conventions. Each endpoint group defines:
- 404 — Resource not found (with prefixed ID in detail)
- 409 — Conflict (duplicate email, role with active assignments on delete, concurrent modification)
- 422 — Invalid prefixed ID format
- 400 — Invalid filter/pagination parameters
- 403 — Insufficient permissions

**Route placement**: `services/api/routes/identity/` directory, mounted in `main.ts`. Follow the pattern established by `services/api/routes/` (tenant-taxonomy, items, item-custom-types).

**Deliverable**: All endpoints live behind auth middleware. Feature flag for permission enforcement still in place.

### Phase 4: Integration, Activation & Migration

**Gateway routing**: Ensure `/api/v1/users/*`, `/api/v1/roles/*`, `/api/v1/permissions/*`, `/api/v1/me` route to identity-api without breaking existing OAuth BFF paths (`/identity/login`, `/callback`, `/logout`, `/me`, `/refresh`).

**Downstream ACL cutover** (feature-flag-gated, per-BC):
1. Enable `identity.rbac.resolve_permissions` in staging
2. Run parity tests: DB-backed resolver produces identical permissions to hardcoded map for all seed roles
3. Enable per-BC: OC first (has commented-out permission checks ready), then OCC, then QR
4. Each BC activation is a separate deploy with rollback capability

**Backward compatibility tests**: Contract tests verifying `AuthenticatedIdentity` shape is unchanged. Verify downstream BCs consuming via ACLs still resolve correctly.

**Seed role policy**: Seed roles are `delete_protected` (cannot be deleted via API). Their permission sets are mutable (admins can extend). A `base_permissions` concept ensures system-defined permissions are always included even when admins add custom ones.

**Tenant scoping**: JWT `org_id` claim is authoritative (per existing auth middleware default at `auth.ts:40`). Close Open Question 5.

**Deliverable**: Permission enforcement active across all BCs. System operating with DB-backed RBAC.

## Key Components

| Component | Location | Change Type |
|-----------|----------|-------------|
| PermissionResolver | `contexts/identity/domain/services/permission-resolver.ts` | Refactor (sync -> async + DB) |
| Auth Middleware | `platform/platform-core/http/middleware/auth.ts` | Modify (wire resolution + cache) |
| User Aggregate | `contexts/identity/domain/aggregates/user.ts` | Extend (reactivate, role ref migration) |
| RoleAssignment VO | `contexts/identity/domain/value-objects/role-assignment.ts` | Evolve (string -> UUID) |
| KeycloakAdminPort | `contexts/identity/domain/ports/keycloak-admin.ts` | Expand (~7 new methods) |
| KeycloakAdminClient | `contexts/identity/infra/adapters/keycloak-admin-client.ts` | Expand (~7 new operations) |
| AuthenticatedIdentity | `contexts/identity/contracts/authenticated-identity.ts` | Unchanged (contract preserved) |
| OC ACL | `contexts/operational-context/app/acl/identity-acl.ts` | Activate (permissive -> enforced) |
| OCC ACL | `contexts/operational-components/app/acl/identity-acl.ts` | Activate |
| QR ACL | `contexts/quality-rules/app/acl/identity-acl.ts` | Activate |
| Identity DB | (new) `contexts/identity/infra/db/` | Greenfield |
| Identity Routes | (new) `services/api/routes/identity/` | Greenfield |

## Data Model

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────┐
│  permissions │     │ role_permissions  │     │    roles    │
│──────────────│     │──────────────────│     │─────────────│
│ id (PK)      │◄────│ permission_id(FK)│     │ id (PK)     │
│ name         │     │ role_id (FK)     │────►│ tenant_id   │
│ description  │     └──────────────────┘     │ name        │
│ category     │                              │ is_system   │
└──────────────┘                              │ is_active   │
                                              └──────┬──────┘
                                                     │
                     ┌────────────────────────┐      │
                     │ user_role_assignments   │      │
                     │────────────────────────│      │
                     │ user_id (Keycloak UUID) │      │
                     │ role_id (FK)            │──────┘
                     │ tenant_id               │
                     │ assigned_at             │
                     │ assigned_by             │
                     └────────────────────────┘
```

User identity (email, displayName, auth) lives in Keycloak. SafetyChain Postgres stores: Roles, Permissions (system-defined seed data), role-permission mappings, and user-role assignments.

## Trade-offs and Decisions

| Decision | Choice | Alternative | Rationale |
|----------|--------|-------------|-----------|
| Permission resolution | Middleware + cache | JWT-embedded | Avoids Keycloak coupling; immediate effect on role changes |
| Caching | In-memory TTL (60s) | Redis / no cache | Proportionate to load; avoids infra dependency |
| User storage | Keycloak (proxy) | Postgres | ADR-014/016 mandate; Keycloak is identity SoR |
| Role update | PUT (full replace) | PATCH (incremental) | Simpler contract; PATCH deferred to follow-up |
| Seed role policy | Delete-protected, permission-extensible | Fully immutable | Admins need customization; base_permissions ensures consistency |
| /me endpoints | Both coexist (BFF + API) | Replace BFF | Different auth mechanisms for different clients |
| ACL activation | Per-BC feature flag | Big-bang | Controls blast radius; allows per-BC rollback |
| Reactivate | Include in scope | Defer to follow-up | PRD requirement; but could be deferred if schedule tight |

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Permission resolution adds latency to every request | High | TTL cache (60s), feature flag for gradual activation |
| Keycloak dual-write inconsistency (create user + assign role) | Medium | Outbox pattern or accept-and-reconcile with compensating action |
| Seed data mismatch causes authorization failures on activation | High | Parity tests: DB resolver must match hardcoded map for all seed roles |
| ACL activation breaks existing functionality | High | Per-BC feature flags, staging validation, contract tests |
| Token staleness after role revocation | Medium | Document accepted 60s staleness window (cache TTL); future: short-lived event-driven invalidation |
| Identity DB bootstrap delays Phase 1 | Low | Well-established pattern from OC context; ~1-2 days |
| Audit events emitted but not persisted | Medium | Explicitly suppress domain event emission until audit PRD lands, OR persist to event store |

## Implementation Plan

| Phase | Description | Estimated Effort | Dependencies |
|-------|-------------|------------------|--------------|
| Phase 0 | Identity DB Bootstrap | 1-2 days | None |
| Phase 1 | Permission/Role model + resolver + Permissions API | 3-4 days | Phase 0 |
| Phase 2 | User-role assignments + Keycloak adapter expansion | 3-4 days | Phase 1; KC adapter can start in parallel with Phase 0 |
| Phase 3 | API endpoints (Roles, Users, Assignments, /me) | 4-5 days | Phase 2 |
| Phase 4 | Integration, ACL activation, gateway routing | 2-3 days | Phase 3 |
| **Total** | | **13-18 days** | |

## Open Questions

1. **Reactivate scope**: Include `POST /:id:reactivate` in initial scope or defer to follow-up? The User aggregate needs a new method + domain event. Deactivate-only MVP is simpler.
2. **Audit event disposition**: Suppress domain events until audit PRD, or persist now? The User aggregate already emits `RoleAssigned`, `RoleRevoked`, `UserDeactivated`.
3. **QA reset mechanism**: Drizzle migration re-run or dedicated admin endpoint? Neither is defined in the PRD.
4. **SecurityAxisGrants**: RBAC and ABAC are orthogonal (RBAC = feature gates, ABAC = data visibility via securityAxisGrants). Confirm no coupling is introduced.
5. **Security review gate**: When does the security review happen relative to Phase 3? Before endpoints go live in staging or before production activation?
