# PRD: UI Prototype — Users

## Problem Statement

SafetyChain's Builder Studio prototype has no user management surface.
Administrators need a way to view, search, create, and edit users without
leaving the application. The notification bell area in the top nav is the
natural home for a users icon, following the established header-action
pattern. This is a prototype-quality implementation to validate the
interaction model before production investment.

Linear: SAF-446 | Project: Identity & Access Management | Labels: ui, prototype

## Goals

1. Add a **Users icon** next to the existing notification bell in the nav bar
   (`nav-bar.tsx`), linking to a new `/users` route.
2. Build a **user list page** with search, pagination, and a "Create User"
   action button — matching the layout pattern used by `/identity` and `/items`.
3. Build a **user detail page** (`/users/[id]`) showing user properties
   (email, displayName, tenant, active status, role assignments) in the
   existing `DetailSection` / `DefinitionGrid` pattern.
4. Build a **create user page** (`/users/new`) with a form using the
   established `useActionState` + server-action pattern.
5. Build an **edit user page** (`/users/[id]/edit`) or inline-edit capability
   for mutable fields.
6. Wire all pages to the existing `UserDto` API functions in `lib/api.ts`
   (`fetchUsersByTenant`, `fetchUserById`, `registerUser`, `assignRole`,
   `deactivateUser`).

## Non-Goals

- Production-quality auth/authz enforcement (this is a prototype).
- Role management CRUD (roles are assigned to users, but the roles page is
  out of scope — use existing `assignRole` API only).
- Bulk operations (import/export, mass deactivation).
- Audit logging or activity history on the user detail page.
- Real-time updates or WebSocket subscriptions.
- Mobile-responsive layout beyond what Tailwind provides by default.

## User Stories / Scenarios

**S1 — Discover users surface**
As an admin, I see a Users icon (new `UsersIcon` in `@/components/icons`) next
to the notification bell. Clicking it navigates to `/users`.

**S2 — Browse and search users**
On `/users`, I see a paginated table of users (displayName, email, active
status). I can type in a search field to filter by name or email. Pagination
follows the same search-params pattern as `/identity`.

**S3 — View user detail**
Clicking a row navigates to `/users/[id]`. I see the user's properties in a
card layout: email, displayName, tenantId, isActive, createdAt, and a list of
role assignments. A back-link returns me to the list.

**S4 — Create a new user**
From the list page, I click "Create User" which navigates to `/users/new`. I
fill in email, displayName, and submit. The server action calls
`registerUser()` and redirects to the new user's detail page on success, or
shows validation errors inline.

**S5 — Edit a user**
From the detail page, I click "Edit" which navigates to `/users/[id]/edit`.
Pre-populated form lets me change displayName and active status. Submit calls
the appropriate API and redirects back to detail.

**S6 — Deactivate a user**
From the detail page or via a row-action menu on the list, I can deactivate a
user. This calls `deactivateUser()` and updates the UI to reflect the new
status.

**S7 — Assign a role**
From the detail page, I can assign a role to the user via a simple select +
submit pattern. This calls `assignRole()`.

## Constraints

- **Reuse existing components**: PageLayout, PageHeader, BackLink,
  TableWrapper, Table*, Card, DetailSection, DefinitionGrid, RowActionMenu,
  Input, Label, Button, SubmitButton, Alert. No new shared components unless
  strictly necessary.
- **Follow established routing**: Next.js App Router file-based routing under
  `src/app/users/`. Dynamic segments via `[id]` folders.
- **Follow established data pattern**: Server-side fetch with cache tags,
  server actions via `useActionState`, Suspense boundaries with skeleton
  fallbacks.
- **API surface already exists**: `lib/api.ts` has `UserDto` and all needed
  fetch/mutation functions. No new API endpoints required unless the existing
  ones prove insufficient during implementation.
- **Prototype fidelity**: Must look and behave consistently with existing
  identity and items pages. No experimental UI patterns.
- **Tech stack**: Next.js 16, React 19, Tailwind CSS 4, Radix UI, custom inline
  SVG icons via `@/components/icons` (not lucide-react).

## Open Questions

1. **Search implementation**: Should search be client-side filtering of fetched
   users, or should `fetchUsersByTenant` accept a search parameter? Need to
   check the existing API contract.
2. **Icon choice**: A new `UsersIcon` must be added to `@/components/icons/index.tsx`
   following the existing inline SVG pattern. Confirm it visually fits next to
   `BellIcon` in the nav.
3. **Role assignment UX**: Is a simple dropdown sufficient, or do we need a
   multi-select for assigning multiple roles? Depends on the role model.
4. **Tenant scoping**: Are users always scoped to the current tenant, or can
   admins see cross-tenant users? Prototype assumption: single-tenant view.
5. **Edit vs. inline edit**: Should edit be a separate route (`/users/[id]/edit`)
   matching the identity pattern, or inline editing on the detail page? The
   identity prototype uses a separate route — default to that.
6. **Deactivate vs. delete**: The API has `deactivateUser` but no delete. Is
   deactivation the only removal mechanism? Prototype assumption: yes.

## Rough Approach

### Phase 1 — Nav icon + list page
- Add `UsersIcon` to `@/components/icons/index.tsx` (inline SVG, same pattern as `BellIcon`)
- Add `UsersIcon` button to `nav-bar.tsx` next to the bell
- Create `src/app/users/page.tsx` with PageLayout, PageHeader ("Users" +
  "Create User" button), search input, and a table of users
- Wire to `fetchUsersByTenant()` with Suspense + skeleton fallback
- Add pagination via search params

### Phase 2 — Detail + create pages
- Create `src/app/users/[id]/page.tsx` with user detail card
- Create `src/app/users/new/page.tsx` with create form + server action
- Wire to `fetchUserById()`, `registerUser()`

### Phase 3 — Edit + actions
- Create `src/app/users/[id]/edit/page.tsx` with edit form
- Add `RowActionMenu` to list rows (View, Edit, Deactivate)
- Add deactivate action to detail page
- Wire to `deactivateUser()`

### Phase 4 — Role assignment
- Add role assignment section to detail page
- Simple select + assign button calling `assignRole()`
