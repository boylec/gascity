# PRD: Permissions API — System-Defined Permission Registry (SAF-449)

## Problem Statement

SAF-449 calls for a read-only Permissions API that exposes the system-defined
permission catalog via REST endpoints. The core question was whether to use a
static in-code registry or a DB-seeded approach.

**Current state: Phase 1 is implemented.** The static registry exists at
`contexts/identity/app/routes/permissions.ts` (on `boylec/develop`) with:
- `GET /api/v1/permissions` — lists all 11 system permissions
- `GET /api/v1/permissions/:id` — gets a permission by `perm_`-prefixed ID
- 11 permissions following `<context>:<resource>:<action>` pattern
- Stable hardcoded UUIDs with `perm_` prefix
- Mounted behind customer JWT auth middleware at `/api/v1/*`
- Tests at `contexts/identity/app/routes/permissions_test.ts`

The route is mounted in `contexts/identity/app/api/main.ts` (line 306):
```typescript
app.route("/api/v1/permissions", permissionRoutes());
```

The decision was made: **static registry in code** for Phase 1, with a TODO
for DB migration (SAF-449 comment + `permission-resolution.ts` docblock
referencing SAF-447..450 epic).

## Goals

- **Verify Phase 1 completeness**: confirm the implementation matches the
  Linear spec (endpoints, pagination, resource prefix, error handling).
- **Document the Phase 2 path**: the existing code has extension points
  (`PermissionResolutionPort`, `createAsyncPermissionResolver`) for DB-backed
  resolution. Document the migration path so future work doesn't re-discover
  these hooks.
- **Validate consistency**: ensure the 11 permissions in
  `routes/permissions.ts` match the string literals in
  `identity-contracts/permission-resolution.ts` (ROLE_PERMISSIONS map).
  Divergence between the API catalog and the resolver would be a bug.
- **Address the cursor-pagination gap**: Linear spec says "cursor-paginated"
  but the current implementation returns all 11 permissions in a single
  response with `hasMore: false`. For 11 items this is fine, but the API
  contract should either support cursors now or document why it doesn't.

## Non-Goals

- Implementing DB-backed permissions (Phase 2 / SAF-447..450 epic).
- Custom permissions or tenant-level CRUD (explicitly system-managed).
- Custom roles — that's a separate feature (SAF-448 or similar).
- Changing the permission string format (`<context>:<resource>:<action>`).

## User Stories / Scenarios

1. **Frontend developer builds a permissions management UI**: calls
   `GET /api/v1/permissions` to populate a permission picker when assigning
   roles. Needs the full list with human-readable descriptions and categories.

2. **Platform admin views permission details**: calls
   `GET /api/v1/permissions/perm_01000000-...` to see what a specific
   permission grants. Needs the description and category.

3. **Future: DB migration**: when the team implements runtime-editable RBAC
   (Phase 2), the static `PERMISSIONS` array moves to a DB table seeded from
   the same data. The API contract (endpoints, response shape, resource IDs)
   must not change — only the data source.

## Constraints

- Permission IDs are stable UUIDs with `perm_` prefix — they must not change
  between Phase 1 (static) and Phase 2 (DB), as clients may store them.
- The 11 permissions in the API response MUST match the string literals in
  `ROLE_PERMISSIONS` (identity-contracts). If a permission exists in
  `ROLE_PERMISSIONS` but not in the API catalog (or vice versa), the resolver
  and the API are out of sync.
- The API runs behind the `/api/v1/*` auth middleware (customer JWT + tenant).
  Unauthenticated access is blocked.
- Next.js rewrite at `/api/v1/permissions/:path*` → identity-api already
  exists on `boylec/develop` (added per ADR-028 Amendment 1).

## Open Questions

1. **Should the list endpoint support cursor pagination now?** The Linear spec
   says "cursor-paginated" but with 11 items it's unnecessary overhead. If the
   answer is "yes," the implementation needs a cursor parameter and
   `next_cursor` in the response. If "no," document the deviation from spec.

2. **Are the hardcoded UUIDs the permanent IDs?** The current implementation
   uses `perm_01000000-0000-4000-8000-00000000000X` which are clearly
   synthetic. When Phase 2 migrates to DB, will these be the seeded IDs or
   will real UUIDs be generated? This affects client compatibility.

3. **Should the API expose which roles include each permission?** The current
   response has `permissionId`, `name`, `description`, `category`. Adding a
   `roles` field (which system roles include this permission) would be useful
   for UI but couples the permission endpoint to the role registry.

## Approach

Since Phase 1 is already implemented, the remaining work is:

### 1. Review and verify the existing implementation

- Confirm endpoints match Linear spec
- Verify permission catalog matches ROLE_PERMISSIONS
- Check error handling (invalid ID format, 404 for unknown permission)
- Verify auth middleware coverage

### 2. Address the pagination question

Either add cursor pagination support or document the intentional deviation
(small fixed set, no pagination needed).

### 3. Document the Phase 2 migration path

Add a section to the identity architecture docs explaining:
- Where the extension points are (`PermissionResolutionPort`,
  `createAsyncPermissionResolver`)
- What changes when moving from static to DB-backed
- That permission IDs and API contract must remain stable

### 4. File follow-on beads

- Phase 2: DB-backed permission registry (SAF-447..450 epic)
- Permission-role inverse lookup endpoint (if Open Question 3 is "yes")

## Acceptance Criteria

- [ ] Existing implementation passes review against Linear SAF-449 spec
- [ ] Permission catalog in `routes/permissions.ts` matches ROLE_PERMISSIONS
  in `identity-contracts/permission-resolution.ts` (automated or manual check)
- [ ] Pagination decision documented (cursor support added or deviation noted)
- [ ] Phase 2 migration path documented in identity architecture docs
- [ ] SAF-449 Linear issue transitioned appropriately

---

## Clarifications from Human Review

Autonomous path: `require_human_approval=false`. Accepting the
review's own recommendations verbatim. See
`.prd-reviews/permissions-api/prd-review.md` §"Before You Build:
Critical Questions" for the grounded answers.
