# Design: SAF-446 — Users Feature UI Prototype

## Executive Summary

This design implements a production-ready Users admin UI backed by Keycloak as the sole user store (Path A, per ADR-014/016). The design adds 7 operations to `KeycloakAdminPort`, creates identity-api user admin routes at `/identity/users/*`, adds a YARP gateway rule, and completes the existing ~80% frontend scaffold with pagination, search, edit, reactivation, role revocation, permissions matrix, and audit trail.

Three security pre-conditions must be met before any admin routes go live: permission gate enforcement (`oc:users:manage`), CSRF protection on mutation endpoints, and tenant-scoped Keycloak organization queries.

## Problem Statement

The enterprise platform has a minimal Users/Identity UI at `/identity/` (~80% scaffolded) backed by a Keycloak identity provider that currently only supports `createOrganization` and `createUser`. Users cannot be listed with pagination, searched, edited, reactivated, or have roles revoked through the admin UI. The Identity bounded context has no database (per ADR-014) and delegates all user storage to Keycloak.

## Proposed Design

### Architecture

```
Browser → Next.js RSC → YARP Gateway → identity-api → KeycloakAdminClient → Keycloak
                                                    → Keycloak Events (audit)
```

- **No SafetyChain-owned users table.** Keycloak is the sole source of truth for user data.
- **identity-api** gets new routes at `/identity/users/*` that wrap `KeycloakAdminPort` operations.
- **YARP gateway** gets a new rule routing `/identity/users/{**remainder}` → identity-api (Order 150).
- **Frontend** extends the existing scaffold in `presentation/builder-studio/src/app/identity/`.
- **Audit trail** sources from Keycloak admin events feed.

## Key Components

### 1. KeycloakAdminPort Expansion (7 new operations)

Add to `contexts/identity/domain/ports/keycloak-admin.ts`:

| Operation | Keycloak Admin API | Notes |
|-----------|-------------------|-------|
| `getUser(orgId, userId)` | `GET /admin/realms/{realm}/users/{id}` | Single user fetch |
| `listUsersByOrganization(orgId, opts)` | `GET /admin/realms/{realm}/organizations/{orgId}/members` | Offset pagination via `first`+`max` |
| `updateUser(orgId, userId, data)` | `PUT /admin/realms/{realm}/users/{id}` | Display name, email |
| `enableUser(orgId, userId)` | `PUT /admin/realms/{realm}/users/{id}` with `enabled: true` | Reactivation |
| `disableUser(orgId, userId)` | `PUT /admin/realms/{realm}/users/{id}` with `enabled: false` | Soft delete (deactivation) |
| `assignRealmRoleToUser(orgId, userId, role)` | `POST /admin/realms/{realm}/users/{id}/role-mappings/realm` | Role assignment |
| `removeRealmRoleFromUser(orgId, userId, role)` | `DELETE /admin/realms/{realm}/users/{id}/role-mappings/realm` | Role revocation |

No `deleteUser` — hard delete is out of scope per human decision (Part 11 compliance).

`KeycloakAdminClient` adapter implements these using `fetch()` with the existing token caching (30s expiry buffer).

### 2. Identity API Routes (`contexts/identity/app/routes/users.ts`)

| Method | Path | Operation | Response |
|--------|------|-----------|----------|
| GET | `/identity/users` | List users (paginated) | `{ data: User[], pagination: { offset, limit, total } }` |
| GET | `/identity/users/:id` | Get user detail | `{ data: User }` |
| POST | `/identity/users` | Register user | `{ data: User }` + 201 + Location |
| PUT | `/identity/users/:id` | Update profile | `{ data: User }` |
| POST | `/identity/users/:id/deactivate` | Soft delete | `{ data: User }` |
| POST | `/identity/users/:id/reactivate` | Re-enable | `{ data: User }` |
| POST | `/identity/users/:id/roles` | Assign role | `{ data: RoleAssignment }` |
| DELETE | `/identity/users/:id/roles/:role` | Revoke role | 204 |
| GET | `/identity/users/:id/audit` | Audit trail | `{ data: AuditEvent[] }` |

Query params for list: `?offset=0&limit=25&search=<text>&status=active|inactive&role=admin|manager|operator|viewer`

### 3. Gateway Rule

Add to `services/gateway/appsettings.json`:
```json
{
  "RouteId": "identity-users",
  "ClusterId": "identity-api",
  "Match": { "Path": "/identity/users/{**remainder}" },
  "Order": 150
}
```

Order 150 sits between specific routes (100) and the catch-all (1000). Does not conflict with ADR-025 BFF bypass since `/identity/login|callback|logout|me|refresh` are Next.js routes that never hit YARP.

### 4. Frontend Completion

**Existing scaffold (confirmed ~80%):**
- `page.tsx` — users list with table, StatusBadge, "Register User" button
- `[id]/page.tsx` — user detail with DetailSection pattern
- `new/page.tsx` — registration form
- `assign-role-form.tsx`, `deactivate-button.tsx`
- `api.ts` — `fetchUsersByTenant`, `fetchUserById`, `registerUser`, `assignRole`, `deactivateUser`

**New/modified:**
- `page.tsx` — add pagination controls, search input, status/role filters, Govern panel nav entry
- `[id]/page.tsx` — add edit button, reactivate button, revoke-role capability, permissions matrix display, audit trail timeline
- `[id]/edit/page.tsx` — new edit form (pre-fill current values)
- `api.ts` — add `updateUser`, `reactivateUser`, `revokeRole`, `fetchAuditTrail`, update `fetchUsersByTenant` with pagination/search/filter params

## Data Model

No SafetyChain-owned tables. All data lives in Keycloak:

- **Users**: Keycloak user entities within Organizations (tenants)
- **Roles**: Keycloak realm roles — `admin`, `manager`, `operator`, `viewer` (lowercase)
- **Role assignments**: Keycloak realm role mappings per user
- **Audit events**: Keycloak admin events (CRUD operations on users/roles)

Pagination: offset-based via Keycloak's `first` + `max` params. Total count via separate `GET /users/count` call.

## Trade-offs and Decisions

| Decision | Rationale | Trade-off |
|----------|-----------|-----------|
| All-Keycloak (no projection table) | ADR-014/016 compliance, single source of truth | Read latency depends on Keycloak; no local query optimization |
| Soft delete only | Part 11 audit trail integrity | Cannot permanently purge user records |
| Offset pagination (not cursor) | Keycloak Admin API only supports `first`+`max` | Degrades at high offsets for large tenants |
| Role name `manager` (not QualityManager) | Matches `permission-resolver.ts` domain code | PRD and UI copy need updating |
| Keycloak events for audit | Native data source, no sync needed | Limited to admin events; may need custom event types later |

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Keycloak Admin API latency at scale (>1K users/tenant) | HIGH | Define latency SLO (p95 < 500ms); run synthetic load test before prod; file follow-on ticket for caching layer if needed |
| Permission gate not enforced | CRITICAL (pre-Phase-1) | Add middleware enforcing `oc:users:manage` on all `/identity/users/*` routes |
| CSRF on mutation endpoints | HIGH (pre-Phase-1) | Extend CSRF protection beyond OAuth login to all POST/PUT/DELETE identity routes |
| Tenant scoping bypass | HIGH (pre-Phase-1) | Verify `listUsersByOrganization` scopes to the authenticated user's org, not a request param |
| Keycloak Admin API token management | LOW | Existing 30s-buffer token caching is adequate |
| No shared middleware root | MEDIUM | Follow `complianceFirewallMiddleware` pattern; add permission check in identity-api's `main.ts` |

## Implementation Plan

### Phase 1: Backend Foundation (identity-api)
1. Add 7 operations to `KeycloakAdminPort` interface + `KeycloakAdminClient` adapter
2. Add permission gate middleware to identity-api
3. Create `contexts/identity/app/routes/users.ts` with all 9 endpoints
4. Add YARP gateway rule for `/identity/users/*`
5. Add colocated `users_test.ts`
6. CSRF protection on mutation endpoints

### Phase 2: Frontend List Enhancement
1. Add pagination, search, status/role filters to users list
2. Add Users entry to Govern panel in `nav-config.ts`
3. Update `api.ts` with pagination/search params
4. Fix role name display (`manager` not `QualityManager`)

### Phase 3: User Detail & Management
1. Edit profile form + `updateUser` API
2. Reactivate button + `reactivateUser` API
3. Role revocation UI + `revokeRole` API
4. Permissions matrix display (static from `ROLE_PERMISSIONS`)
5. Audit trail timeline from Keycloak events

### Phase 4: Polish
1. Confirmation dialogs for destructive actions
2. Error handling and loading states
3. Input validation schemas (Zod)
4. Accessibility pass

## Open Questions

1. **Keycloak events API format**: What fields does Keycloak expose for admin events? Need to verify before building the audit trail UI.
2. **User count per tenant**: Expected range affects whether the offset pagination strategy is adequate or needs a caching layer.
3. **Multi-org users**: Can a Keycloak user belong to multiple Organizations? If yes, the tenant-scoped list must handle this.
