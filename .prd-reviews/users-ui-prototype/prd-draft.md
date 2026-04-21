# PRD: Users Feature UI Prototype (SAF-446)

## Problem Statement

SafetyChain's enterprise platform has a basic Users/Identity UI at `/identity/` with minimal CRUD (register, view, deactivate, assign roles). This prototype needs to evolve into a production-ready user management experience that supports multi-tenant operations, scalable user lists, and the full lifecycle of user administration.

Current gaps: no pagination or search on the user list, no user editing after registration, no reactivation flow, no bulk operations, no audit visibility, no permissions matrix, hardcoded tenant context, and the feature is absent from the main sidebar navigation.

The backend Identity bounded context (Deno/Hono API + DDD hexagonal packages) is partially stubbed — frontend API client interfaces exist but the Deno API routes for Identity are not yet wired. Both frontend UI and backend API routes need to be built or completed.

## Goals

1. **Production-ready Users list** — Paginated, searchable, filterable table of users per tenant with status and role indicators.
2. **Complete user lifecycle** — Register, view, edit profile, deactivate, reactivate, and delete users.
3. **Role management UX** — Assign/revoke roles with a clear permissions matrix showing what each role (Admin, QualityManager, Operator, Viewer) grants.
4. **Navigation integration** — Add Users to the main sidebar under the Govern panel so it's discoverable.
5. **Backend API completion** — Wire Identity endpoints in the Deno API service (register, get, list, update, deactivate, reactivate, delete, role CRUD) following the existing route/repository pattern used by taxonomies, items, and item-custom-types.
6. **Tenant-aware context** — Replace hardcoded DEFAULT_TENANT with dynamic tenant resolution from session/auth context.
7. **Audit trail UI** — Surface role assignment history and user activity timestamps.

## Non-Goals

- **Authentication/login flow** — This is about user administration, not the login/signup experience itself.
- **SSO/SAML/OIDC integration** — Identity provider federation is out of scope for this prototype.
- **Custom role creation** — The four predefined roles (Admin, QualityManager, Operator, Viewer) are fixed for now.
- **Cross-tenant user management** — Each tenant manages only its own users.
- **Email/notification system** — No invite emails, password reset emails, or notification triggers.
- **Mobile-responsive design** — Desktop-first; responsive layout is a future concern.

## User Stories / Scenarios

### US-1: Tenant Admin views all users
As a tenant admin, I want to see a paginated list of all users in my tenant with search and filter capabilities, so I can quickly find and manage specific users.

**Acceptance**: List loads with pagination (25 per page), supports text search on name/email, can filter by status (Active/Inactive) and role.

### US-2: Admin registers a new user
As a tenant admin, I want to register a new user with email, display name, and initial role assignment, so they can access the platform.

**Acceptance**: Form validates email uniqueness, assigns to current tenant, optionally assigns an initial role, redirects to the new user's detail page.

### US-3: Admin edits a user profile
As a tenant admin, I want to update a user's display name and email, so I can correct errors or reflect name changes.

**Acceptance**: Edit form pre-fills current values, validates changes, shows success feedback, revalidates cached data.

### US-4: Admin manages user roles
As a tenant admin, I want to assign and revoke roles for a user, and see what each role permits, so I can grant appropriate access.

**Acceptance**: Role assignment shows a permissions matrix, can assign multiple roles, can revoke individual roles, shows assignment history (who assigned, when).

### US-5: Admin deactivates and reactivates users
As a tenant admin, I want to deactivate users who should no longer access the system, and reactivate them if needed, with confirmation dialogs.

**Acceptance**: Deactivate requires confirmation, shows impact warning, status updates immediately. Reactivate follows same pattern.

### US-6: Admin sees user audit trail
As a tenant admin, I want to see a timeline of changes to a user's account (creation, role changes, status changes), so I can audit access history.

**Acceptance**: Detail page shows chronological audit entries with actor, action, and timestamp.

## Constraints

- **Tech stack**: Next.js 16 App Router (RSC), React 19, Tailwind CSS 4.2 (dark theme with existing design tokens), Deno/Hono API, PostgreSQL 16.
- **Design system**: Must use existing custom Tailwind tokens (bg-base, bg-surface, accent-amber, etc.) and shared components (StatusBadge, ActionButton, SubmitButton).
- **Architecture**: Backend must follow the existing route/repository pattern — Drizzle ORM schema in `services/api/db/schema/`, route handlers in `services/api/routes/identity/`, mounted in `main.ts`. Match the structure of existing modules (taxonomies, items, item-custom-types).
- **Existing code**: Build on the existing `/apps/web/src/app/identity/` pages and `/apps/web/src/lib/api.ts` interfaces. Do not rewrite from scratch.
- **Routing convention**: Follow the existing App Router file structure pattern (`page.tsx`, `[id]/page.tsx`, `new/page.tsx`).
- **Server components default**: Pages are async RSC; only use `"use client"` for interactive elements (forms, buttons).
- **Target branch**: `boylec/develop`.

## Open Questions

1. **Tenant resolution**: How should the current tenant be determined? Is there a session/auth context to pull from, or should we implement a tenant selector as an interim solution?
2. **User deletion**: Should hard delete be supported, or only soft delete (deactivate)? Compliance implications?
3. **Pagination strategy**: Server-side cursor-based or offset-based? What's the expected user count per tenant?
4. **API authentication**: Are the Deno API endpoints behind auth middleware, or is that a separate concern?
5. **Permissions enforcement**: Should the UI enforce role-based access to the admin pages, or is that deferred?
6. **Existing data**: Are there existing users in the database to migrate/display, or is this a greenfield data model?

## Rough Approach

### Phase 1: Database Schema & Backend API
- Add `identity-context.ts` schema alongside `operational-context.ts` in `services/api/db/schema/`
- Define `users` table (id UUID, email, display_name, tenant_id, is_active, created_at, updated_at) and `role_assignments` table (id, user_id FK, role, assigned_at, assigned_by)
- Create `services/api/routes/identity/` with route handlers following existing patterns
- Mount `/identity` routes in `main.ts`
- Implement: register, get, list (paginated), update, deactivate, reactivate, delete, assign role, revoke role

### Phase 2: Users List Enhancement
- Replace simple table with paginated, searchable, filterable list
- Add StatusBadge integration for active/inactive states
- Add role chips/tags to list rows
- Wire into sidebar navigation under Govern panel

### Phase 3: User Detail & Edit
- Add edit profile form (display name, email)
- Add reactivation button alongside deactivation
- Show role permissions matrix
- Add role revocation capability
- Display audit trail timeline

### Phase 4: Polish & Integration
- Tenant context resolution (replace DEFAULT_TENANT)
- Confirmation dialogs for destructive actions
- Error handling and loading states
- Accessibility pass

---

## Clarifications from Human Review

Response to the 6 critical questions posed in `prd-review.md`. Human directive: **"accept your best recommendations"**, grounded in the review's own ADR-based guidance.

### Q1: User storage architecture — All-Keycloak or projection table?
**A: Path A — All-Keycloak.** Expand `KeycloakAdminPort` to cover read operations. Treat Keycloak as the sole user store per **ADR-014** (Enterprise is not an IdP) and **ADR-016** (Keycloak owns user storage, Part 11 UUID preservation). Record this decision as an ADR addendum or new ADR. Defer any projection table until a concrete query-pattern need proves Keycloak Admin API latency or query semantics insufficient.

### Q2: Delete semantics — hard vs soft?
**A: Soft delete only (Keycloak disable).** Required for Part 11 compliance — preserves actor references in audit records. Remove "delete users" from Goal 2 wording; re-frame as "deactivate users." Hard delete is explicitly out of scope for this phase; revisit only with a compliance-reviewed scope proposal.

### Q3: Which 7 KeycloakAdminPort operations to add?
**A: Add all 7 listed operations.** Current adapter has `createOrganization` + `createUser` only. Add: `getUser`, `listUsersByOrganization` (paginated, offset-based per Q-Q below), `updateUser`, `enableUser`, `disableUser`, `assignRealmRoleToUser`, `removeRealmRoleFromUser`. Do **not** add `deleteUser` (see Q2). Update the PRD's effort estimate to reflect this adapter work as part of Phase 1.

### Q4: Gateway routing for `/identity/users/*`?
**A: Add an explicit route** `/identity/users/*` → `identity-api` in the gateway config. Do **not** touch existing OAuth BFF paths (`/identity/login`, `/callback`, `/logout`, `/me`, `/refresh`) — they stay on the BFF bypass per ADR-025. Only the new `/users/*` subtree gets the explicit pass-through rule.

### Q5: Role naming — `QualityManager` vs `manager`?
**A: Use `manager` (lowercase).** Matches the existing `permission-resolver.ts` `ROLE_PERMISSIONS` keys. Update all PRD text, UI copy, and role-selector options to use `manager`. Display label can still be "Quality Manager" in the UI if desired, but the underlying role identifier is `manager`.

### Q6: Audit trail storage mechanism?
**A: Primary — Keycloak events feed.** Keycloak already emits admin/event logs covering create/update/disable/enable/role-change operations. Consume those via the existing event-store wiring. Defer any SafetyChain-side projection table to Phase 3 pending concrete query-pattern requirements (e.g. if timeline UI needs joins Keycloak's feed can't serve). Document the event types subscribed and the retention policy in Phase 3 planning.

### Important-but-non-blocking items (accepted as-is from review)

- **Goal 6 (tenant resolution)** — rescope to "add multi-tenant switching for users in multiple Keycloak Organizations"; remove "Replace hardcoded DEFAULT_TENANT" since `requireCurrentUser()` already resolves tenant from `/me`.
- **Repo path corrections** — update PRD to use actual DDD-hexagonal paths: `contexts/identity/infra/db/`, `contexts/identity/app/routes/`, `presentation/builder-studio/src/` per ADR-015.
- **Frontend scaffold delta** — Phase 2-4 are frontend deltas on existing `presentation/builder-studio/src/app/identity/` scaffold; list `edit`, `reactivate`, `revoke-role`, paginated/searchable list as the concrete additions.
- **Pagination** — offset-based (first/max) to match Keycloak Admin API and existing stack; document the pattern in Phase 1.
- **Authorization enforcement** — MVP: gate `/identity/*` UI routes by `oc:users:manage` permission in a server component or middleware. Non-negotiable security gap otherwise.
- **Multi-role** — confirm YES: concurrent multi-role is intended per `role_assignments` many-to-many table. Update US-2 wording ("initial role assignment" → "initial role assignments").
