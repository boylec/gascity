# PRD Review: UI Prototype — Users (SAF-446)

## Executive Summary

Six parallel review legs (requirements, gaps, ambiguity, feasibility, scope,
stakeholders) independently converged on three blocking findings:

1. **The proposed `/users` route duplicates existing `/identity` pages.** The
   existing `/identity` surface already implements user list, detail, create,
   role assignment, and deactivation using the same API functions. The PRD does
   not acknowledge this or explain the relationship.

2. **Three API capabilities assumed by the PRD do not exist:**
   - `fetchUsersByTenant` has no search, filter, or pagination parameters
   - No `updateUser` endpoint exists (edit page is blocked)
   - No `fetchRoles` endpoint exists (role assignment UI is blocked)

3. **No testable acceptance criteria.** Goals and user stories describe happy-path
   interactions but define no measurable success conditions, error behaviors,
   or verification method.

Overall confidence: **Low-Medium.** The component library, routing patterns, and
data-fetching approach are solid. But the PRD cannot be implemented as written
without resolving the `/identity` overlap and missing API surface.

## Before You Build: Critical Questions

These must be answered before implementation begins:

1. **What is the relationship between `/users` and `/identity`?**
   Does `/users` replace `/identity`? Coexist alongside it? Extend it?
   Four of six reviewers flagged this independently — the PRD is either
   unaware of the duplication or intentionally silent about it.

2. **What new interaction pattern is being validated?**
   If `/identity` already proves the CRUD model, what does `/users` add?
   The stated goal is to "validate the interaction model" — what model
   isn't already validated?

3. **What signals that the prototype succeeded?**
   No acceptance criteria exist. What measurement or demo result ends the
   prototype and triggers production investment?

4. **Is client-side search acceptable at prototype scale?**
   `fetchUsersByTenant(tenantId)` returns the full user list with no
   server-side filtering. Is this acceptable for expected tenant sizes?
   If not, an API change is required before Phase 1 starts.

5. **Is the edit page (S5) still in scope given no `updateUser` API?**
   The backend has no user-update endpoint. Either descope the edit page
   or plan the API extension as a prerequisite task.

6. **How should prototype auth work?**
   The PRD marks production auth as a non-goal but exposes destructive
   actions (deactivate, create) with no access control. Is the prototype
   behind a VPN? Single-user? The existing `/identity` pages call
   `requireCurrentUser()` — should `/users` replicate this?

## Important But Non-Blocking

These should be resolved but do not block starting work:

- **Goal 5 self-contradicts**: "edit user page ... or inline-edit capability"
  specifies two different implementations. Open Question 5 defers the choice,
  but Phase 3 assumes the separate-route approach. Pick one.

- **`deactivateUser` and `assignRole` require user context parameters**
  (`deactivatedBy`, `assignedBy`) sourced from `requireCurrentUser()`. The PRD
  does not mention this — implementers need to know.

- **Deactivation is irreversible with no confirmation UX.** No reactivate
  method exists in the domain. A confirmation dialog and "this is permanent"
  warning should be specified.

- **Validation rules are undefined.** S4 says "validation errors inline" but
  never specifies what is validated (email format? required fields? max
  lengths?). The domain enforces 255-char max on displayName and trims
  whitespace.

- **Missing stakeholder personas.** Support staff need read-only filtered
  views, status history, and last-login timestamps. Affected users (the people
  being managed) are invisible — no notification, consent, or deactivation
  experience is described.

- **Accessibility gaps.** The new `UsersIcon` nav button needs `aria-label`,
  tooltip, and keyboard navigation. Verify the existing `BellIcon` pattern
  handles these before replicating it.

- **Duplicate-email handling.** `registerUser` has no visible uniqueness guard.
  What happens when an admin registers an already-taken email?

- **`RoleAssignmentDto` shape is undefined** in the PRD but needed for detail
  page and role-assignment UI.

## Observations and Suggestions

- **Collapse 4 phases to 2.** Phase A: nav icon + list page with client-side
  search. Phase B: detail page with deactivate action. Create, edit, and role
  assignment are already proven patterns in `/identity` and add no new
  prototype signal.

- **Cut Phase 4 (role assignment).** `AssignRoleForm` already exists at
  `/identity/[id]/assign-role-form.tsx`. Rebuilding it proves nothing new.

- **Cut the separate edit route.** For two mutable fields (displayName,
  isActive) on a prototype, a toggle + inline edit on the detail page is
  simpler and requires no new API endpoint.

- **Reuse existing components directly.** `DeactivateButton` at
  `/identity/[id]/deactivate-button.tsx` and the create form at
  `/identity/new/page.tsx` are directly reusable or cloneable.

- **Consider renaming `/identity` to `/users` instead of building new.**
  If the goal is a "Users" surface with the existing CRUD pattern, a route
  rename + nav icon addition would achieve the PRD's goals with ~10% of the
  implementation work.

## Confidence Assessment

| Leg | Confidence | Key Concern |
|-----|------------|-------------|
| Requirements | Low | No testable acceptance criteria; error behaviors absent |
| Gaps | Medium | `/identity` overlap; missing `updateUser` API |
| Ambiguity | Low | Missing search API; undefined validation; self-contradicting goal |
| Feasibility | Medium | Edit page blocked by missing API; search needs API or descoping |
| Scope | Medium | 2x overscoped due to `/identity` duplication |
| Stakeholders | Medium | Support staff, affected users, and auth posture undefined |

**Aggregate: Low-Medium.** The PRD is a solid interaction outline built on
proven patterns, but it cannot be implemented as written. The `/identity`
overlap, missing API surface, and absent acceptance criteria require resolution
first.

## Next Steps

1. Answer the 6 critical questions above (human gate)
2. Revise PRD scope based on answers (likely 2-phase, not 4)
3. Proceed to design doc with revised scope
