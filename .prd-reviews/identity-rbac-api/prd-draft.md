# PRD: Identity Bounded-Context RBAC API Surface

## Problem Statement

SafetyChain's Identity bounded context needs a complete RBAC API surface to support user management, role assignment, and permissions querying. Currently, the `PermissionResolver` uses a hardcoded map of role-to-permission strings — roles are not persisted aggregates and permissions are not queryable entities. This blocks the Users admin UI (SAF-446) and prevents QA from operating on global data as if a tenant were fresh (no API surface to seed/reset user-role state).

The ask: ~20 REST endpoints spanning Users CRUD + `/me`, Role CRUD with permission-set replace, user-role assignment, and Permissions read-only list/get. ID prefixes: `usr_`, `rol_`, `perm_`. This work produces the backend API that SAF-446's UI will consume and is prerequisite to SAF-450.

## Goals

1. **Users API** — Full CRUD for user management within a tenant: create, get, list (paginated), update profile, deactivate (soft-delete), reactivate. Plus a `/me` endpoint for the authenticated user's own profile and permissions.
2. **Roles API** — CRUD for tenant-managed roles: create role with a permission set, get, list, update (replace permission set), delete (soft). Each role maps to N system-defined permissions.
3. **Permissions API** — Read-only surface: list all system-defined permissions, get by ID. Permissions are value objects seeded at deploy time, not user-created.
4. **User-Role Assignments API** — Assign/revoke roles for a user. List a user's current roles. List users holding a given role.
5. **Persisted Role aggregate** — Migrate Role from string literals in `PermissionResolver` to a persisted Postgres aggregate with a many-to-many relationship to system-defined Permissions.
6. **PermissionResolver refactor** — Change from hardcoded map lookups to querying the Role aggregate's permission sets. Maintain backward compatibility during migration via seed data for the four existing roles (admin, manager, operator, viewer).
7. **Prefixed IDs** — All entities use deterministic prefixed IDs: `usr_`, `rol_`, `perm_` (consistent with the existing `tt_`, `itm_` patterns in other BCs).
8. **Seed data** — Migration seeds the four existing system roles with their current permission sets, and seeds the full Permission lookup table from the existing hardcoded values.

## Non-Goals

- **User storage in Postgres** — Per ADR-014/016, Keycloak owns user identity. The Users API proxies Keycloak Admin API for user CRUD; SafetyChain stores only the role-assignment relationship and any domain-specific user profile extensions.
- **Custom permission creation** — Permissions are system-defined, seeded at deploy. No create/update/delete endpoints for permissions.
- **UI implementation** — This PRD covers the API surface only. SAF-446 covers the frontend.
- **Authentication flows** — Login, SSO, token refresh, OAuth BFF are out of scope. This is about the management/admin API behind auth middleware.
- **Cross-tenant operations** — All endpoints are tenant-scoped. No super-admin cross-tenant queries.
- **Audit trail storage** — Audit events (who assigned what role when) are a separate concern. This PRD exposes the CRUD surface; event sourcing/audit is deferred.

## User Stories / Scenarios

### US-1: Admin lists users in their tenant
As a tenant admin, I want to GET `/api/v1/users?cursor=...&limit=25&search=jane` and receive a paginated list of users in my tenant with their current roles, so the Users UI can render a searchable table.

**Acceptance**: Response envelope `{ "data": [...], "pagination": {...} }`. Supports `search` (name/email substring), `status` filter (active/inactive), `role` filter, cursor-based pagination.

### US-2: Admin creates a user
As a tenant admin, I want to POST `/api/v1/users` with email, display name, and optional initial role to provision a new user in Keycloak and optionally assign them a role.

**Acceptance**: Creates user in Keycloak via Admin API, returns `usr_`-prefixed ID, optionally creates role assignment. 409 on duplicate email within tenant.

### US-3: User views own profile
As an authenticated user, I want to GET `/api/v1/me` and receive my profile, assigned roles, and resolved permissions, so the frontend can render role-aware UI.

**Acceptance**: Returns user profile, list of assigned roles, and flattened unique permission set derived from all assigned roles.

### US-4: Admin manages roles
As a tenant admin, I want to CRUD roles with named permission sets, so I can define what each role in my organization can do.

**Acceptance**: POST creates a role with a name and `permission_ids` array. PUT replaces the permission set atomically. GET returns role with its permissions. DELETE soft-deletes (cannot delete if users are assigned). Four seed roles are immutable (cannot delete, can extend permissions).

### US-5: Admin assigns/revokes roles
As a tenant admin, I want to POST `/api/v1/users/:id/roles` to assign a role and DELETE to revoke, so I can manage user access levels.

**Acceptance**: Assignment is idempotent (re-assigning same role is 200, not 409). Revocation returns 204. Cannot assign a deleted/inactive role.

### US-6: Developer queries available permissions
As a developer or admin, I want to GET `/api/v1/permissions` to see all system-defined permissions with descriptions, so I can understand what to assign to roles.

**Acceptance**: Returns full list of permissions with `perm_`-prefixed IDs, names, and descriptions. No pagination needed (small fixed set). Cacheable.

### US-7: QA resets tenant user-role state
As a QA engineer, I want the API surface to allow creating users, roles, and assignments programmatically so I can seed a tenant to a known state for testing.

**Acceptance**: All CRUD endpoints are callable via API (not just UI). Seed data migration can be re-run or an admin endpoint exists to reset to defaults.

## Constraints

- **Keycloak as user store**: Per ADR-014/016. User CRUD operations proxy to Keycloak Admin API via `KeycloakAdminPort`. SafetyChain Postgres stores only Role aggregates, Permission lookups, and user-role assignment relationships.
- **Tech stack**: Deno/Hono API, PostgreSQL 16, Drizzle ORM for schema/migrations.
- **Route pattern**: Base `/api/v1/`, plural nouns, kebab-case. Collections max 2-level nesting. Custom actions use colon syntax (e.g., `/users:search`). Follow existing route patterns in `services/api/routes/` as used by tenant-taxonomy, items, item-custom-types BCs.
- **API conventions**: Response envelope `{ "data": ..., "pagination": {...} }`. Cursor-based pagination (never offset). Errors follow RFC 9457 Problem Details. Follow `/contexts/api-routes.md` (25 sections, 217 lines) and `.claude/rules/api-routes.md`.
- **Tenant isolation**: All queries scoped by `tenantId` from JWT claims (`sub` for userId, `tenant_id`/`org_id` for scoping). No cross-tenant data leakage.
- **Auth middleware**: Existing middleware at `platform/platform-core/http/middleware/auth.ts` validates Bearer tokens via jose JWKS, populates Hono context with `AuthenticatedIdentity`. Admin endpoints require `oc:users:manage` permission. `/me` requires only authentication.
- **Backward compatibility**: The `PermissionResolver` refactor must not break existing permission checks. Current resolver at `contexts/identity/domain/services/permission-resolver.ts` uses `ROLE_PERMISSIONS` map with 4 roles. Downstream BCs consume `AuthenticatedIdentity` contract (from `contexts/identity/contracts/authenticated-identity.ts`) which includes `roles[]`, `permissions[]`, and `securityAxisGrants` Map.
- **ID format per ADR-019**: `{prefix}_{uuid}` with full RFC 4122 dashes. `usr` prefix already registered (uses Keycloak UUID per ADR-016), `rol` already registered, `perm` needs registration. Domain uses raw UUIDs; prefix encoding/decoding in application layer only.
- **Existing domain model**: User aggregate at `contexts/identity/domain/aggregates/user.ts` (userId, tenantId, email, displayName, roleAssignments, isActive). RoleAssignment value object at `contexts/identity/domain/value-objects/role-assignment.ts` (role string, assignedAtUtc, assignedBy). Role and Permission aggregates planned for sc-1hz build phase.
- **Permission format**: Existing permissions follow `<context>:<resource>:<action>` pattern (e.g., `oc:items:read`, `occ:deviations:approve`). This granularity must be preserved.
- **Keycloak adapter**: `contexts/identity/infra/adapters/keycloak-admin-client.ts` and `keycloak-provider.ts` exist. Currently supports `createOrganization` and `createUser`. Migration tooling at `tools/keycloak-migration/`.

## Open Questions

1. **KeycloakAdminPort expansion scope**: The port (at `contexts/identity/infra/adapters/keycloak-admin-client.ts`) currently has `createOrganization` and `createUser`. This PRD requires ~7 additional operations (getUser, listUsers, updateUser, enableUser, disableUser, assignRealmRole, removeRealmRole). Keycloak migration tooling exists at `tools/keycloak-migration/` — is the Keycloak Admin SDK already a dependency there, or does it need to be added to the identity context?
2. **Role mutability for seed roles**: Should the four seed roles (admin, manager, operator, viewer) be fully mutable (admins can change their permission sets) or immutable (permission sets are fixed, only custom roles are mutable)?
3. **Permission granularity**: Confirmed from codebase — permissions follow `<context>:<resource>:<action>` pattern (e.g., `oc:items:read`, `occ:deviations:approve`). Fine-grained. How many total permissions exist in the current `ROLE_PERMISSIONS` map? Should the Permission entity include a `category` field grouping by context (oc, occ, qr)?
4. **SecurityAxisGrants interaction**: `AuthenticatedIdentity` includes a `securityAxisGrants` Map for ABAC. How does the RBAC role-permission system interact with ABAC axis grants? Are they independent (RBAC for feature access, ABAC for data scoping)?
5. **X-Tenant-Id vs JWT tenantId**: The API guidelines PRD (SAF-88) flagged an inconsistency between `X-Tenant-Id` header and JWT `tenantId` claim. Current auth middleware extracts from `tenant_id`/`org_id` JWT claims or KC Organizations. Which is authoritative for Identity endpoints?

## Rough Approach

### Phase 1: Permission & Role Domain Model
- Add Permission value object and Role aggregate to `contexts/identity/domain/` (alongside existing User aggregate and RoleAssignment VO)
- Define Drizzle schema tables in `services/api/db/schema/identity-context.ts`: `permissions` (perm_ ID, name, description, category), `roles` (rol_ ID, tenant_id, name, description, is_system, is_active, created_at, updated_at), `role_permissions` join table
- Seed migration: populate `permissions` from current `ROLE_PERMISSIONS` map in `permission-resolver.ts`; populate four system `roles` (admin, manager, operator, viewer) with their current permission sets
- Refactor `PermissionResolver` at `contexts/identity/domain/services/permission-resolver.ts` to query DB-backed roles instead of hardcoded map. Keep fallback to hardcoded map during migration.
- Update `AuthenticatedIdentity` contract at `contexts/identity/contracts/authenticated-identity.ts` if needed (currently already carries `roles[]` and `permissions[]`)

### Phase 2: User-Role Assignment Model
- Evolve `RoleAssignment` VO (at `contexts/identity/domain/value-objects/role-assignment.ts`) from role-string to role-aggregate reference
- Define `user_role_assignments` table (usr_ ID from Keycloak, rol_ ID FK, tenant_id, assigned_at, assigned_by)
- Implement assignment/revocation domain operations on User aggregate
- Wire into existing auth middleware (`platform/platform-core/http/middleware/auth.ts`) so resolved permissions come from DB

### Phase 3: API Endpoints (all under `/api/v1/`)
- `/permissions` — GET list, GET by ID (read-only)
- `/roles` — POST create, GET list, GET by ID, PUT update (permission set replace), DELETE soft-delete
- `/users` — POST create (proxy Keycloak via `keycloak-admin-client.ts`), GET list (proxy Keycloak + join assignments), GET by ID, PUT update, POST `/:id:deactivate`, POST `/:id:reactivate`
- `/users/:id/roles` — GET list, POST assign, DELETE revoke
- `/me` — GET (profile + roles + resolved permissions)
- Route handlers in `services/api/routes/identity/`, mounted in `main.ts`

### Phase 4: Integration & Migration
- Gateway routing: ensure new `/api/v1/users/*`, `/api/v1/roles/*`, `/api/v1/permissions/*` route to identity-api without breaking existing OAuth BFF paths (`/identity/login`, `/callback`, `/logout`, `/me`, `/refresh`)
- Backward compatibility tests: verify downstream BCs consuming `AuthenticatedIdentity` (via ACLs) still resolve permissions correctly with DB-backed resolver
- Seed data verification: confirm four system roles match current `ROLE_PERMISSIONS` behavior exactly
- Register `perm` prefix in ADR-019 prefix registry
