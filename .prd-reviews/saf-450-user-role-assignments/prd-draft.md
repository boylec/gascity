# PRD: User-Role Assignments API

## Problem Statement

The SafetyChain Identity context needs REST API endpoints for managing
role assignments on users and resolving computed permissions. The domain
model already supports roles -- the `User` aggregate has `assignRole()`,
`revokeRole()`, and `roleAssignments` getter, and a pure
`resolvePermissions()` service maps roles to permission strings. However,
there are no HTTP routes to expose these operations, no persistence
infrastructure for the User aggregate (the infra/repositories dir is empty
with only a `.gitkeep`), and no database schema or migrations.

This feature unblocks the broader RBAC flow: once users can be assigned
roles via API, the downstream enforcement middleware (SAF-449) and
eventually the Roles aggregate (SAF-448) can build on it.

## Goals

1. **Expose role assignment operations via REST API**:
   - `GET /api/v1/users/:userId/roles` -- list a user's current role assignments
   - `POST /api/v1/users/:userId/roles` -- assign a role to a user
   - `DELETE /api/v1/users/:userId/roles/:roleId` -- revoke a role from a user
   - `GET /api/v1/users/:userId/permissions` -- resolve the user's computed permission set

2. **Implement User persistence**: Provide a PostgreSQL-backed
   `UserRepository` implementation (the domain port exists, the infra is
   empty) so role assignments survive restarts.

3. **Tenant isolation**: All endpoints operate within the authenticated
   user's tenant boundary. A user in tenant A cannot read or modify
   assignments for a user in tenant B.

4. **Consistent API contract**: Follow the existing SafetyChain API
   conventions (`application/json`, RFC 7807 problem details for errors,
   `data` envelope, versioned route prefix `/api/v1`).

5. **Forward-compatible with Roles aggregate**: The current
   `RoleAssignment` references roles by string. When SAF-448 introduces a
   `Role` aggregate with `roleId`, the migration path should be minimal.
   Design the API and DB schema so the switch from `role: string` to
   `roleId: UUID` is an internal change, not a contract break.

## Non-Goals

- **Roles CRUD (SAF-448)**: This PRD does not create, list, update, or
  delete Role definitions. Roles are system-defined strings managed in
  `ROLE_PERMISSIONS` (`permission-resolver.ts`). SAF-448 will elevate
  roles to an aggregate.

- **Middleware enforcement (SAF-449)**: This PRD does not wire the
  resolved permissions into request-level authorization middleware.
  Permissions are returned read-only for now.

- **UI for role management**: No frontend work. API-first.

- **Audit log / event sourcing infrastructure**: Domain events
  (`RoleAssigned`, `RoleRevoked`) are raised but this PRD does not build
  the event-persistence pipeline. That's a cross-cutting concern.

- **Keycloak synchronization**: Role assignments live in the
  SafetyChain DB, not in Keycloak. No IdP sync in this scope.

## User Stories / Scenarios

**US-1: Admin lists a user's roles**
As a tenant admin, I call `GET /api/v1/users/:userId/roles` and receive
the list of `RoleAssignment` objects (`{ role, assignedAtUtc, assignedBy }`).
If the user has no roles, I get an empty array, not a 404.

**US-2: Admin assigns a role**
As a tenant admin, I call `POST /api/v1/users/:userId/roles` with
`{ "role": "operator" }`. The server validates the role is a known system
role, runs `User.assignRole()`, persists via `UserRepository.save()`, and
returns the new assignment with 201. If the role is already assigned, I
get a 409 Conflict with a problem-detail body.

**US-3: Admin revokes a role**
I call `DELETE /api/v1/users/:userId/roles/:roleId` (where `:roleId` is
the role string, e.g. `operator`). The server runs `User.revokeRole()`,
persists, and returns 204. If the role isn't assigned, I get 404.

**US-4: Service resolves a user's permissions**
I call `GET /api/v1/users/:userId/permissions` and receive the
deduplicated, sorted list of permission strings computed from the user's
currently assigned roles. This is a read-only projection.

**US-5: Cross-tenant isolation**
If I'm authenticated as tenant A and request roles for a user in tenant B,
I get 404 (not 403, to avoid leaking existence).

**US-6: Deactivated user**
If the target user is deactivated, assign and revoke return 422
(`UserDeactivated`). List and permissions still return current state
(read-only operations succeed on deactivated users).

## Constraints

1. **Depends on SAF-448 (Roles)**: The `DELETE` route uses `:roleId`
   which is currently the role string itself (`admin`, `operator`, etc.).
   When SAF-448 introduces real role IDs, the route segment semantics
   change. API versioning or a `role` query parameter may be needed -- flag
   this during design.

2. **No DB exists for identity**: The quality-rules and operational-components
   contexts use Drizzle ORM with PostgreSQL. Identity has no `infra/db/`
   directory. A DB schema, Drizzle config, and migration must be created.

3. **Authentication**: The existing identity routes use cookie-based
   auth (BFF pattern). The new `/api/v1/` routes may need bearer token
   auth for service-to-service calls. Design must clarify which auth
   mechanism applies.

4. **System roles are compile-time constants**: `SYSTEM_ROLES` is
   derived from `ROLE_PERMISSIONS` keys in `permission-resolver.ts`.
   Assign validation must reject unknown role strings. When SAF-448
   arrives, this check shifts to a DB lookup.

5. **Hono routing**: The app uses Hono. New routes must integrate with
   the existing `app.route()` mount pattern in `main.ts`.

6. **Target branch**: All work targets `boylec/develop`.

## Open Questions

1. **Auth mechanism for `/api/v1/` routes**: Cookie-based (BFF, same as
   `/api/identity/*`) or bearer token? Or both via a shared middleware
   that accepts either?

2. **`:roleId` semantics**: Should the DELETE route use the role name
   string (current state) or anticipate UUID role IDs from SAF-448?
   Using the string now is simpler but means a breaking change later.

3. **Actor identity extraction**: `assignRole()` and `revokeRole()` need
   an `actor: UniqueId`. Where does the actor ID come from -- JWT claim,
   `/me` identity, or a header?

4. **Database provisioning**: Does the identity service get its own
   Postgres database, or share the existing one from another context?
   The Aspire AppHost may need a new resource.

5. **Concurrency control**: The `User` aggregate has a `version` field.
   Should the API expose optimistic concurrency (ETag / If-Match)?

6. **Should `GET .../permissions` include the source role for each
   permission?** The current `resolvePermissions()` returns a flat list.
   Returning `{ permission, grantedBy: [roles] }` is richer but changes
   the contract.

## Rough Approach

1. **DB bootstrap** (infra layer): Create `identity/infra/db/` with
   Drizzle schema for `users` and `user_role_assignments` tables, config,
   migration. Follow the pattern in `quality-rules/infra/db/`.

2. **Repository implementation**: Implement `PgUserRepository` in
   `identity/infra/repositories/` satisfying the `UserRepository` port.
   Map between DB rows and `User.reconstitute()` / `User.toSnapshot()`.

3. **Route module**: Create `identity/app/user-role-routes.ts` with the
   four endpoints. Use the existing `createDomainErrorHandler` pattern for
   error mapping. Mount under `/api/v1/users` in `main.ts`.

4. **Auth middleware**: Add a middleware that extracts the authenticated
   identity (from cookie or bearer token) and sets `tenantId` + `actorId`
   on the Hono context. Apply to all `/api/v1/*` routes.

5. **Validation**: POST body schema validation (role must be in
   `SYSTEM_ROLES`). Path param validation (userId is a valid UUID).

6. **Tests**: Unit tests for route handlers with a stubbed repository.
   Integration tests with a real Postgres instance following the pattern
   in `tests/api-integration/`.

---

## Clarifications from Human Review

Autonomous path: `require_human_approval=false`. Accepting the
review's own recommendations verbatim. See
`.prd-reviews/saf-450-user-role-assignments/prd-review.md` §"Before You Build:
Critical Questions" for the grounded answers.

### Resolved Critical Questions

**1. Auth mechanism + actor extraction:** Add a single middleware that
accepts either a session cookie or a `Bearer` JWT, extracts `tenantId` +
`actorId`, and injects them into Hono context. This also unblocks SAF-449.

**2. Authorization model for write operations:** Require
`oc:users:manage` permission for POST/DELETE. GET endpoints require
any authenticated user within the same tenant.

**3. `:roleId` parameter semantics:** Rename to `:roleName` and commit
to using the role name string as the stable key. The DELETE route becomes
`DELETE /api/v1/users/:userId/roles/:roleName`. When SAF-448 introduces
UUIDs, a v2 route can be added without breaking v1.

**4. `toSnapshot()` audit bug:** Fix `User.toSnapshot()` to include
`audit` in the returned object, matching `UserSnapshot`.

**5. `UserRepository` port:** Extend with
`findByTenantAndId(tenantId: UniqueId, userId: UniqueId): Promise<User | null>`.

**6. `/me` source of truth:** For this delivery, `/me` continues to read
from Keycloak (no change). The new `/api/v1/` routes read/write the DB.
A follow-on ticket reconciles the two sources.

**7. Downstream BC consumers:** Acknowledged. SAF-450 produces the data
but does not activate permission checks in OC/OCC/QR. A coordination
section is added to the design doc noting the downstream activation
dependency.
